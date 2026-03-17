"""
worker.py — Background pipeline worker.
Runs on FastAPI startup and every 30 minutes to keep the job database fresh.

Pipeline:
  Scrape (profile-driven) → LLM Summarize → Embed (nomic) → Store (ChromaDB)
"""

import asyncio
import traceback
from datetime import datetime
from typing import Optional

from services.scraper import scrape_all_sources
from services.job_summarizer import summarize_job
from services.embeddings import embed_job
from services.vector_store import add_job, get_job_count

_is_running = False
_last_run: datetime | None = None
_INTERVAL_MINUTES = 30
# Stores the last user profile so the recurring worker stays personalized
_last_known_profile = None


async def run_ingestion_pipeline(profile=None) -> dict:
    """
    Runs the full: Scrape → Summarize → Embed → Store pipeline.
    Accepts an optional UserProfile to personalize scraping keywords.
    Returns a status dict with counts.
    """
    global _is_running, _last_run, _last_known_profile

    # Store the profile for future scheduled runs
    if profile is not None:
        _last_known_profile = profile

    # Use last known profile when not provided (scheduled runs)
    active_profile = profile or _last_known_profile

    if _is_running:
        return {"status": "already_running", "message": "Pipeline is already running."}

    _is_running = True
    stats = {"scraped": 0, "processed": 0, "failed": 0, "job_count": 0}
    consecutive_failures = 0

    try:
        print(f"\n{'='*50}")
        print(f"🚀 Starting job ingestion at {datetime.now().strftime('%H:%M:%S')}")
        print(f"{'='*50}")

        # Step 1 — Scrape raw listings (profile-driven dynamic search)
        raw_jobs = await scrape_all_sources(profile=active_profile)
        stats["scraped"] = len(raw_jobs)

        # Step 2 — Summarize & embed each listing
        for i, raw in enumerate(raw_jobs):
            try:
                print(f"  [{i+1}/{len(raw_jobs)}] Processing: {raw.get('title', 'Unknown')[:50]}...")

                # Attempt summarization once (fail fast on hard API limits)
                job_data = await summarize_job(raw_text=raw["raw_text"])

                if not job_data:
                    stats["failed"] += 1
                    consecutive_failures += 1
                    print(f"  ⚠️  Failed to summarize job. ({consecutive_failures}/3 consecutive failures)")
                    if consecutive_failures >= 3:
                        print(f"  🛑 Aborting ingestion: 3 consecutive failures reached.")
                        break
                    continue

                # Carry over scraped metadata if Gemini didn't return them
                job_data.setdefault("id", raw["id"])
                job_data.setdefault("postedDate", raw.get("posted_date", ""))
                if not job_data.get("company"):
                    job_data["company"] = raw.get("company", "Unknown")
                if not job_data.get("imageUrl"):
                    job_data["imageUrl"] = raw.get("image_url", "")

                # Generate embedding
                embedding = embed_job(job_data)

                # Store in ChromaDB
                add_job(job_data, embedding)
                stats["processed"] += 1

                # Respect Gemini Free Tier: 15 RPM limit.
                # 4.5s per job ≈ 13 RPM — stays safely under the limit.
                await asyncio.sleep(4.5)
                
                # Reset consecutive failure counter on success
                consecutive_failures = 0

            except Exception as e:
                stats["failed"] += 1
                consecutive_failures += 1
                print(f"  ⚠️  Failed to process job: {e} ({consecutive_failures}/3 consecutive failures)")
                
                if consecutive_failures >= 3:
                    print(f"  🛑 Aborting ingestion: 3 consecutive failures reached.")
                    break

        stats["job_count"] = get_job_count()
        _last_run = datetime.now()
        print(f"\n✅ Ingestion complete: {stats['processed']} jobs added, {stats['failed']} failed")
        print(f"   Total jobs in DB: {stats['job_count']}")

    except Exception as e:
        print(f"❌ Fatal pipeline error: {e}")
        traceback.print_exc()
    finally:
        _is_running = False

    return stats


async def start_background_worker():
    """
    Starts the recurring background ingestion loop.
    Runs once on startup, then repeats every _INTERVAL_MINUTES.
    """
    while True:
        try:
            await run_ingestion_pipeline()
        except Exception as e:
            print(f"❌ Background worker error: {e}")
        print(f"⏳ Next ingestion in {_INTERVAL_MINUTES} minutes...\n")
        await asyncio.sleep(_INTERVAL_MINUTES * 60)


def get_worker_status() -> dict:
    return {
        "is_running": _is_running,
        "last_run":   _last_run.isoformat() if _last_run else None,
        "interval_minutes": _INTERVAL_MINUTES,
        "job_count":  get_job_count(),
    }
