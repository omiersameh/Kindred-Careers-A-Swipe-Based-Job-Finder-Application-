from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import List, Optional
import asyncio
import io

from models.user_profile import UserProfile
from models.job import Job, SwipeAction
from models.cv import CVContent, CVFeedback

from services.recommendation import get_recommended_jobs
from services.cv_generator import generate_tailored_cv, regenerate_tailored_cv
from services.cv_pdf_generator import generate_cv_pdf
from services.embeddings import embed_profile
from services.vector_store import search_jobs, get_job_count
from services.mock_jobs import get_mock_jobs
from worker import run_ingestion_pipeline, start_background_worker, get_worker_status


app = FastAPI(
    title="Kindred Careers API",
    description="Backend for RAG job matching and AI-powered CV generation",
    version="2.0.0"
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
    print(f"🚀 Kindred Careers API v2.0 starting up... (ChromaDB has {job_count} jobs)")
    if job_count > 0:
        print("✅ Fast path: serving from existing ChromaDB — skipping startup scrape.")
    else:
        print("⚠️  ChromaDB is empty. Triggering initial ingest in background...")
    # Always start the background refresh worker (first run delayed by _INTERVAL_MINUTES)
    asyncio.create_task(start_background_worker())

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
    n: int = 30
    exclude_ids: List[str] = []   # Job IDs already seen by this user

class IngestRequest(BaseModel):
    """Optional profile body for the ingest endpoint to personalize scraping."""
    user_profile: Optional[UserProfile] = None

# ── Endpoints ─────────────────────────────────────────────────

@app.get("/")
def read_root():
    return {"status": "ok", "message": "Kindred Careers API v2.0 - RAG Pipeline"}

# ─── 🆕 Phase 3: RAG Job Feed ───────────────────────────────

@app.post("/api/jobs/feed", response_model=List[dict])
async def get_job_feed(req: FeedRequest):
    """
    Returns personalized job recommendations from the ChromaDB vector store.
    Embeds the user profile → similarity search → returns ranked jobs.
    If database is empty, returns mock jobs.
    If all database jobs are seen/excluded, returns the most recent database jobs as fallback.
    """
    try:
        # Fallback if DB is empty
        if get_job_count() == 0:
            print("⚠️ ChromaDB is empty. Returning personalized mock jobs...")
            return get_mock_jobs(req.user_profile)

        profile_vector = embed_profile(req.user_profile)
        jobs = search_jobs(
            profile_vector=profile_vector,
            n=req.n,
            exclude_ids=req.exclude_ids,
        )

        # Fallback if all database jobs are excluded (user has seen everything)
        # We relax the exclude_ids constraint to return recent database jobs instead of blocking
        if not jobs:
            print("⚠️ All jobs excluded. Returning database jobs without exclusion filter...")
            jobs = search_jobs(
                profile_vector=profile_vector,
                n=req.n,
                exclude_ids=None,
            )

        # If it's still empty (should not happen since get_job_count > 0, but just in case)
        if not jobs:
            return get_mock_jobs(req.user_profile)

        return jobs
    except Exception as e:
        # Fallback to mock jobs on any unexpected error to prevent blocking onboarding
        print(f"⚠️ Error in get_job_feed: {e}. Falling back to mock jobs...")
        return get_mock_jobs(req.user_profile)


@app.post("/api/jobs/ingest")
async def ingest_jobs(req: IngestRequest = None, background_tasks: BackgroundTasks = None):
    """
    Manually triggers the scrape → summarize → embed → store pipeline.
    Accepts an optional user_profile to drive personalized job searches.
    Returns immediately; the pipeline runs in the background.
    """
    profile = req.user_profile if req else None
    background_tasks.add_task(run_ingestion_pipeline, profile)
    return {
        "status": "started",
        "message": "Ingestion pipeline started with profile-driven search. Check server logs for progress.",
        "personalized": profile is not None,
        "current_job_count": get_job_count()
    }


@app.get("/api/jobs/status")
def worker_status():
    """Returns current worker status and total number of jobs in DB."""
    return get_worker_status()


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
