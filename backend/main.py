from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import asyncio

from models.user_profile import UserProfile
from models.job import Job, SwipeAction
from models.cv import CVContent, CVFeedback

from services.recommendation import get_recommended_jobs
from services.cv_generator import generate_tailored_cv, regenerate_tailored_cv
from services.embeddings import embed_profile
from services.vector_store import search_jobs, get_job_count
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

# ── Startup: begin background scrape/embed worker ──────────────
@app.on_event("startup")
async def on_startup():
    print("🚀 Kindred Careers API starting up...")
    # Start background worker as a non-blocking background task
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
    """
    try:
        if get_job_count() == 0:
            raise HTTPException(
                status_code=503,
                detail="Job database is empty. Call POST /api/jobs/ingest first."
            )
        profile_vector = embed_profile(req.user_profile)
        jobs = search_jobs(
            profile_vector=profile_vector,
            n=req.n,
            exclude_ids=req.exclude_ids,
        )
        # Return 503 when all available jobs are excluded (user has seen everything)
        if not jobs:
            raise HTTPException(
                status_code=503,
                detail="No new jobs available. Check back later after the next scrape."
            )
        return jobs
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


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
