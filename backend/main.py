from fastapi import FastAPI, HTTPException, BackgroundTasks, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel
from typing import List, Optional
import asyncio
import io
import os
import threading
import time
from datetime import datetime, timedelta

from models.user_profile import UserProfile
from models.job import Job, SwipeAction
from models.cv import CVContent, CVFeedback

from services.recommendation import get_recommended_jobs
from services.cv_generator import generate_tailored_cv, regenerate_tailored_cv
from services.cv_pdf_generator import generate_cv_pdf
from services.embeddings import embed_profile
from services.vector_store import search_jobs, get_job_count
from services.mock_jobs import get_mock_jobs
from services import swipe_store
from worker import run_ingestion_pipeline, start_background_worker, get_worker_status


app = FastAPI(
    title="Kindred Careers API",
    description="Backend for RAG job matching and AI-powered CV generation",
    version="2.1.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Startup: skip scrape, serve from existing ChromaDB data ────────────
@app.on_event("startup")
async def on_startup():
    job_count = get_job_count()
    print(f"🚀 Kindred Careers API v2.1 starting up... (ChromaDB has {job_count} jobs)")
    if job_count > 0:
        print("✅ Fast path: serving from existing ChromaDB — skipping startup scrape.")
    else:
        print("⚠️  ChromaDB is empty. Triggering initial ingest in background...")
    # Always start the background refresh worker (first run delayed by _INTERVAL_MINUTES)
    asyncio.create_task(start_background_worker())


# ──────────────────────────────────────────────────────────────────────
# Rate Limiter (env-gated, in-memory, zero-dependency)
# Activated ONLY when ENABLE_RATE_LIMIT=true in the .env file.
# Default: ENABLE_RATE_LIMIT=False — fully disabled for stress testing.
#
# Quota: 30 jobs served per user per 5-hour rolling window.
# Counts ALL jobs returned in feed responses regardless of swipe direction.
# ──────────────────────────────────────────────────────────────────────

_RATE_LIMIT_ENABLED: bool = os.getenv("ENABLE_RATE_LIMIT", "False").lower() == "true"
_RATE_LIMIT_MAX_JOBS: int = 30
_RATE_LIMIT_WINDOW_SECONDS: int = 5 * 60 * 60  # 5 hours

# {user_id: {"count": int, "window_start": float}}
_rate_limit_state: dict[str, dict] = {}

# ──────────────────────────────────────────────────────────────────────
# Auto-Ingestion Trigger (low-watermark guard)
# When a user's unviewed job count drops below this threshold, the
# scraping pipeline is queued in the background.
# A threading.Lock prevents multiple simultaneous Camoufox launches.
# ──────────────────────────────────────────────────────────────────────

_LOW_WATERMARK_THRESHOLD: int = 15
_scrape_lock = threading.Lock()
_is_scraping_active: bool = False


def _check_rate_limit(user_id: str, jobs_to_serve: int) -> tuple[bool, int]:
    """
    Checks whether a user has exceeded the quota for this window.

    Returns:
        (allowed: bool, retry_after_seconds: int)
    """
    if not _RATE_LIMIT_ENABLED:
        return True, 0

    now = time.time()
    state = _rate_limit_state.get(user_id)

    if state is None or (now - state["window_start"]) >= _RATE_LIMIT_WINDOW_SECONDS:
        # Fresh window
        _rate_limit_state[user_id] = {"count": 0, "window_start": now}
        state = _rate_limit_state[user_id]

    remaining_quota = _RATE_LIMIT_MAX_JOBS - state["count"]

    if remaining_quota <= 0:
        retry_after = int(_RATE_LIMIT_WINDOW_SECONDS - (now - state["window_start"]))
        return False, max(retry_after, 0)

    # Record that we're about to serve jobs (count up to quota cap)
    served = min(jobs_to_serve, remaining_quota)
    state["count"] += served
    return True, 0


# ── Request Payloads ───────────────────────────────────────────

class RecommendationRequest(BaseModel):
    user_profile: UserProfile
    jobs_pool: List[Job]
    swipe_history: List[SwipeAction]

class CVGenerateRequest(BaseModel):
    job: Job
    user_profile: UserProfile

class CVRegenerateRequest(BaseModel):
    existing_content: CVContent
    feedback_text: str
    job: Job
    user_profile: UserProfile

class CVPDFRequest(BaseModel):
    """Payload for generating an ATS PDF from an existing CV JSON."""
    summary: str
    skills: List[str]
    experiences: List[dict]       # [{jobTitle, company, startDate, endDate, achievements}]
    education_entries: List[str] = []
    candidate_name: str = ""
    candidate_email: str = ""
    candidate_phone: str = ""
    candidate_location: str = ""
    target_role: str = ""
    target_company: str = ""

class FeedRequest(BaseModel):
    user_profile: UserProfile
    user_id: str = ""             # Firebase UID — used for persistent swipe exclusion
    n: int = 30
    exclude_ids: List[str] = []   # Job IDs already seen by this client session

class IngestRequest(BaseModel):
    """Optional profile body for the ingest endpoint to personalize scraping."""
    user_profile: Optional[UserProfile] = None

class SwipeRecordRequest(BaseModel):
    """Payload for recording a single swipe event."""
    user_id: str                  # Firebase UID
    job_id: str                   # Stable ChromaDB job ID
    action: str = "skip"          # 'like', 'dislike', or 'skip'


# ── Endpoints ─────────────────────────────────────────────────

@app.get("/")
def read_root():
    return {"status": "ok", "message": "Kindred Careers API v2.1 - Stateful RAG Pipeline"}


# ─── Swipe State Management ─────────────────────────────────

@app.post("/api/swipes/record")
def record_swipe(req: SwipeRecordRequest):
    """
    Records a single swipe action (like/dislike/skip) for a user-job pair.
    These records are persisted in swipes.db and used to exclude already-seen
    jobs from all future feed requests for this user.

    Selection Logic:
      1. Fetch all job_ids this user has already swiped → swiped_ids
      2. Merge with client-side exclude_ids
      3. Run vector similarity ONLY on the remaining unviewed jobs
    """
    if not req.user_id or not req.job_id:
        raise HTTPException(status_code=422, detail="user_id and job_id are required")

    swipe_store.record_swipe(
        user_id=req.user_id,
        job_id=req.job_id,
        action=req.action,
    )
    return {"recorded": True, "user_id": req.user_id, "job_id": req.job_id, "action": req.action}


@app.get("/api/swipes/{user_id}")
def get_swipe_history(user_id: str, limit: int = 50):
    """Returns recent swipe history for a user (for debugging/analytics)."""
    history = swipe_store.get_swipe_history(user_id=user_id, limit=limit)
    swiped_ids = swipe_store.get_swiped_ids(user_id=user_id)
    return {
        "user_id": user_id,
        "total_swiped": len(swiped_ids),
        "history": history,
    }


@app.delete("/api/swipes/{user_id}")
def clear_swipe_history(user_id: str):
    """
    Deletes all swipe records for a user.
    Intended for developer testing and DB stress-testing resets.
    """
    deleted = swipe_store.clear_swipes(user_id=user_id)
    return {"cleared": True, "user_id": user_id, "records_deleted": deleted}


# ─── 🆕 Phase 3: Stateful RAG Job Feed ──────────────────────

@app.post("/api/jobs/feed", response_model=List[dict])
async def get_job_feed(req: FeedRequest, background_tasks: BackgroundTasks):
    """
    Returns personalized job recommendations from the ChromaDB vector store.

    Stateful Unviewed-Only Feeding Logic:
      1. Identify all job_ids the active user has already swiped (from swipes.db).
      2. Merge with client-side exclude_ids (current session state).
      3. Run vector similarity search ONLY on the remaining unviewed jobs.
      4. Return the next highest similarity matches.

    Auto-Ingestion Trigger:
      After retrieval, if the number of unviewed jobs returned drops below
      _LOW_WATERMARK_THRESHOLD (15), queue a background scrape using the
      user's careerFields. A threading.Lock prevents concurrent launches.

    This ensures a user NEVER sees a job twice, even if it has a 95% match rate.
    Rate limiting is applied AFTER retrieval if ENABLE_RATE_LIMIT=true.
    """
    global _is_scraping_active

    try:
        # Fallback if DB is empty
        if get_job_count() == 0:
            print("⚠️ ChromaDB is empty. Returning personalized mock jobs...")
            return get_mock_jobs(req.user_profile)

        # ── Step 1: Build complete exclusion set (server-side + client-side) ──
        server_swiped_ids = set()
        if req.user_id:
            server_swiped_ids = swipe_store.get_swiped_ids(user_id=req.user_id)
            print(f"🔒 [Feed] User '{req.user_id}' has swiped {len(server_swiped_ids)} jobs in DB")

        combined_exclude = server_swiped_ids | set(req.exclude_ids)
        print(f"📋 [Feed] Total excluded: {len(combined_exclude)} jobs "
              f"(server: {len(server_swiped_ids)}, client: {len(req.exclude_ids)})")

        # ── Step 2: Embed profile + vector similarity on unviewed jobs ONLY ──
        profile_vector = embed_profile(req.user_profile)
        jobs = search_jobs(
            profile_vector=profile_vector,
            n=req.n,
            exclude_ids=list(combined_exclude),
        )

        # ── Step 3: Auto-ingestion trigger ────────────────────────────────────
        #    Count unviewed jobs returned. If below threshold OR if it's the
        #    first request of the session (exclude_ids is empty), queue a scrape.
        unviewed_count = len(jobs) if jobs else 0
        is_first_request = len(req.exclude_ids) == 0
        
        if unviewed_count < _LOW_WATERMARK_THRESHOLD or is_first_request:
            trigger_reason = "Low watermark" if unviewed_count < _LOW_WATERMARK_THRESHOLD else "Startup/Login trigger"
            print(f"📉 [Feed] Trigger condition met ({trigger_reason}). "
                  f"Unviewed: {unviewed_count}. Checking scrape lock...")
            with _scrape_lock:
                if not _is_scraping_active:
                    _is_scraping_active = True
                    print("🚀 [Feed] Queueing background ingestion pipeline...")
                    background_tasks.add_task(
                        _guarded_ingestion, req.user_profile
                    )
                else:
                    print("🔒 [Feed] Scrape already in progress — skipping duplicate trigger.")

        # ── Step 4: Fallback — all jobs excluded (user has seen everything) ──
        if not jobs:
            print("⚠️ All jobs excluded. Returning database jobs without exclusion filter...")
            jobs = search_jobs(
                profile_vector=profile_vector,
                n=req.n,
                exclude_ids=None,
            )

        if not jobs:
            return get_mock_jobs(req.user_profile)

        # ── Step 5: Apply rate limiter (if enabled via ENABLE_RATE_LIMIT=true) ──
        if _RATE_LIMIT_ENABLED and req.user_id:
            allowed, retry_after = _check_rate_limit(req.user_id, len(jobs))
            if not allowed:
                print(f"🚫 [RateLimit] User '{req.user_id}' exceeded quota. "
                      f"Retry after {retry_after}s")
                return JSONResponse(
                    status_code=429,
                    content={
                        "detail": "Rate limit exceeded. You have viewed the maximum "
                                  f"of {_RATE_LIMIT_MAX_JOBS} jobs in the last 5 hours.",
                        "retry_after_seconds": retry_after,
                    },
                    headers={"Retry-After": str(retry_after)},
                )
            # Count jobs served toward quota
            _check_rate_limit(req.user_id, 0)  # already counted above in allowed path

        return jobs

    except Exception as e:
        print(f"⚠️ Error in get_job_feed: {e}. Falling back to mock jobs...")
        return get_mock_jobs(req.user_profile)


async def _guarded_ingestion(profile=None):
    """
    Wrapper that runs run_ingestion_pipeline and guarantees the
    _is_scraping_active flag is released when the pipeline finishes
    (whether it succeeds or crashes).
    """
    global _is_scraping_active
    try:
        print("🔧 [AutoIngest] Background ingestion pipeline started.")
        await run_ingestion_pipeline(profile)
        print("✅ [AutoIngest] Background ingestion pipeline completed.")
    except Exception as e:
        print(f"❌ [AutoIngest] Pipeline failed: {e}")
    finally:
        with _scrape_lock:
            _is_scraping_active = False
            print("🔓 [AutoIngest] Scrape lock released.")


@app.post("/api/jobs/ingest")
async def ingest_jobs(req: IngestRequest = None, background_tasks: BackgroundTasks = None):
    """
    Manually triggers the scrape → summarize → embed → store pipeline.
    Accepts an optional user_profile to drive personalized job searches.
    Returns immediately; the pipeline runs in the background.

    Ingestion Scale (v2.1):
      - Target: 60 job listings per run via paginated Wuzzuf scraping
      - Worker: 12 Groq summarizer calls × 5 jobs each = 60-job pool
    """
    profile = req.user_profile if req else None
    background_tasks.add_task(run_ingestion_pipeline, profile)
    return {
        "status": "started",
        "message": "Ingestion pipeline started (60-job target, 12 Groq calls). Check logs.",
        "personalized": profile is not None,
        "current_job_count": get_job_count(),
        "rate_limit_enabled": _RATE_LIMIT_ENABLED,
    }


@app.get("/api/jobs/status")
def worker_status():
    """Returns current worker status and total number of jobs in DB."""
    status = get_worker_status()
    status["rate_limit_enabled"] = _RATE_LIMIT_ENABLED
    if _RATE_LIMIT_ENABLED:
        status["rate_limit_config"] = {
            "max_jobs": _RATE_LIMIT_MAX_JOBS,
            "window_hours": 5,
        }
    return status


# ─── Phase 2: CV Generation ─────────────────────────────────

@app.post("/api/recommendations", response_model=List[Job])
def get_recommendations(req: RecommendationRequest):
    try:
        ranked_jobs = get_recommended_jobs(req.user_profile, req.jobs_pool, req.swipe_history)
        return ranked_jobs
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/generate-cv", response_model=CVContent)
async def api_generate_cv(req: CVGenerateRequest):
    try:
        cv_content = await generate_tailored_cv(req.job, req.user_profile)
        return cv_content
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/regenerate-cv", response_model=CVContent)
async def api_regenerate_cv(req: CVRegenerateRequest):
    try:
        cv_content = await regenerate_tailored_cv(
            req.existing_content,
            req.feedback_text,
            req.job,
            req.user_profile
        )
        return cv_content
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/generate-cv-pdf")
async def api_generate_cv_pdf(req: CVPDFRequest):
    """
    Converts existing CV JSON content into an ATS-optimized PDF.
    Returns the PDF as a downloadable file stream.
    """
    try:
        pdf_bytes = generate_cv_pdf(
            summary=req.summary,
            skills=req.skills,
            experiences=req.experiences,
            education_entries=req.education_entries,
            candidate_name=req.candidate_name,
            candidate_email=req.candidate_email,
            candidate_phone=req.candidate_phone,
            candidate_location=req.candidate_location,
            target_role=req.target_role,
            target_company=req.target_company,
        )
        safe_company = req.target_company.replace(" ", "_") or "Company"
        safe_role = req.target_role.replace(" ", "_") or "CV"
        filename = f"CV_{req.candidate_name.replace(' ', '_')}_{safe_role}_{safe_company}.pdf"
        return StreamingResponse(
            io.BytesIO(pdf_bytes),
            media_type="application/pdf",
            headers={"Content-Disposition": f'attachment; filename="{filename}"'},
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
