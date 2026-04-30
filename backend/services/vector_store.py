from __future__ import annotations
import os
import math
import hashlib
import chromadb
from datetime import datetime
from typing import List, Optional, Set

# ──────────────────────────────────────────────────────────────────
# ChromaDB setup
# ──────────────────────────────────────────────────────────────────
_DB_PATH        = os.getenv("CHROMA_PATH", "./chroma_db")
_COLLECTION_NAME = "job_listings"

_client: Optional[object]     = None
_collection: Optional[object] = None


def _get_collection():
    """Lazy-loads the ChromaDB collection."""
    global _client, _collection
    if _collection is None:
        _client     = chromadb.PersistentClient(path=_DB_PATH)
        _collection = _client.get_or_create_collection(
            name=_COLLECTION_NAME,
            metadata={"hnsw:space": "cosine"},
        )
        print(f"✅ ChromaDB ready. '{_COLLECTION_NAME}' has {_collection.count()} jobs.")
    return _collection


# ──────────────────────────────────────────────────────────────────
# Stable ID — prevents duplicate DB entries across scrape runs
# ──────────────────────────────────────────────────────────────────

def make_stable_id(title: str, company: str) -> str:
    """
    Returns a deterministic ID based on job title + company.
    Same job scraped twice → same ID → ChromaDB upsert prevents duplication.
    """
    key = f"{title.lower().strip()}|{company.lower().strip()}"
    return "job_" + hashlib.md5(key.encode()).hexdigest()[:20]


# ──────────────────────────────────────────────────────────────────
# Recency scoring
# ──────────────────────────────────────────────────────────────────

def _recency_factor(ingested_at: str) -> float:
    """
    Exponential decay based on how long ago the job was ingested.
    Returns 1.0 for brand-new jobs, ~0.5 after 7 days, ~0.25 after 14 days.
    """
    try:
        ingested = datetime.fromisoformat(ingested_at)
        age_days = (datetime.now() - ingested).total_seconds() / 86400
        return math.exp(-0.1 * max(age_days, 0))  # half-life ≈ 7 days
    except Exception:
        return 0.5


# ──────────────────────────────────────────────────────────────────
# add_job — stable upsert with ingested_at timestamp
# ──────────────────────────────────────────────────────────────────

def add_job(job: dict, embedding: List[float]) -> str:
    """
    Upserts a job into ChromaDB using a stable, deterministic ID.
    Re-scraping the same job updates it instead of creating a duplicate.
    """
    col = _get_collection()

    title   = str(job.get("title", ""))
    company = str(job.get("company", ""))
    job_id  = make_stable_id(title, company)

    ingested_at = datetime.now().isoformat()

    # Flatten all metadata (ChromaDB only stores scalar values)
    def safe_str(v, default="") -> str:
        return str(v) if v is not None else default

    def safe_float(v, default=0.0) -> float:
        try:
            return float(v)
        except (TypeError, ValueError):
            return default

    metadata = {
        "title":        safe_str(job.get("title")),
        "company":      safe_str(job.get("company")),
        "location":     safe_str(job.get("location")),
        "industry":     safe_str(job.get("industry")),
        "careerField":  safe_str(job.get("careerField")),
        "specialization": safe_str(job.get("specialization")),
        "workMode":     safe_str(job.get("workMode"), "Hybrid"),
        "minSalary":    safe_float(job.get("minSalary")),
        "maxSalary":    safe_float(job.get("maxSalary")),
        "imageUrl":     safe_str(job.get("imageUrl")),
        "vibeTag":      safe_str(job.get("vibeTag")),
        "requiredSkills": ", ".join(str(s) for s in job.get("requiredSkills", [])),
        "summaryBullets": " | ".join(str(b) for b in job.get("summaryBullets", [])),
        "description":  safe_str(job.get("description"))[:1000],
        "postedDate":   safe_str(job.get("postedDate")),
        "logoEmoji":    safe_str(job.get("logoEmoji"), "🏢"),
        "jobType":      safe_str(job.get("jobType"), "Full-Time"),
        "ingested_at":  ingested_at,   # ← timestamp for recency ranking
    }

    col.upsert(
        ids=[job_id],
        embeddings=[embedding],
        metadatas=[metadata],
        documents=[safe_str(job.get("description"))],
    )
    return job_id


# ──────────────────────────────────────────────────────────────────
# search_jobs — match score + recency ranked, with seen-ID exclusion
# ──────────────────────────────────────────────────────────────────

def search_jobs(
    profile_vector: List[float],
    n: int = 30,
    exclude_ids: Optional[List[str]] = None,
) -> List[dict]:
    """
    Finds the best-matching jobs for a user profile vector.

    NOTE: Work mode preference is handled by the embedding similarity score,
    not by a hard filter, so all 170 (or however many) jobs are ranked and
    the most relevant ones surface naturally.

    Ranking formula:
        final_score = match_score * 0.65 + recency_score * 35

    Args:
        profile_vector: Embedding of the user profile.
        n:              Number of results to return.
        exclude_ids:    Job IDs already seen by the user.
    """
    col = _get_collection()
    if col.count() == 0:
        return []

    excluded: Set[str] = set(exclude_ids or [])

    # Fetch extra to account for excluded ones
    fetch_n = min(n + len(excluded) + 20, col.count())

    results = col.query(
        query_embeddings=[profile_vector],
        n_results=fetch_n,
        include=["metadatas", "distances"],
    )

    jobs = []
    for i, meta in enumerate(results["metadatas"][0]):
        job_id = results["ids"][0][i]

        # Skip jobs the user has already seen
        if job_id in excluded:
            continue

        distance    = results["distances"][0][i]
        match_score = round(max(0.0, (1.0 - distance / 2.0)) * 100, 1)
        recency_pct = round(_recency_factor(meta.get("ingested_at", "")) * 100, 1)

        # Combined ranking: 65% match quality + 35% freshness
        final_score = round(match_score * 0.65 + recency_pct * 0.35, 2)

        jobs.append({
            "id":             job_id,
            "title":          meta.get("title", ""),
            "company":        meta.get("company", ""),
            "location":       meta.get("location", ""),
            "industry":       meta.get("industry", ""),
            "careerField":    meta.get("careerField", ""),
            "specialization": meta.get("specialization", ""),
            "workMode":       meta.get("workMode", "Hybrid"),
            "minSalary":      meta.get("minSalary", 0),
            "maxSalary":      meta.get("maxSalary", 0),
            "imageUrl":       meta.get("imageUrl", ""),
            "vibeTag":        meta.get("vibeTag", ""),
            "requiredSkills": [
                s.strip()
                for s in meta.get("requiredSkills", "").split(",")
                if s.strip()
            ],
            "summaryBullets": [
                b.strip()
                for b in meta.get("summaryBullets", "").split("|")
                if b.strip()
            ],
            "description":  meta.get("description", ""),
            "postedDate":   meta.get("postedDate", ""),
            "logoEmoji":    meta.get("logoEmoji", "🏢"),
            "jobType":      meta.get("jobType", "Full-Time"),
            "matchScore":   match_score,    # Pure cosine similarity (display)
            "ingestedAt":   meta.get("ingested_at", ""),
            "_finalScore":  final_score,    # Used only for server-side sort
        })

    # Sort by combined score descending: best match + newest first
    jobs.sort(key=lambda j: j["_finalScore"], reverse=True)

    # Strip internal sort key before sending to client
    for j in jobs:
        j.pop("_finalScore", None)

    return jobs[:n]


# ──────────────────────────────────────────────────────────────────
# Utilities
# ──────────────────────────────────────────────────────────────────

def get_job_count() -> int:
    """Returns the total number of jobs stored in ChromaDB."""
    return _get_collection().count()


def get_existing_job_ids() -> Set[str]:
    """
    Returns the set of all stable job IDs currently in ChromaDB.
    Used by the ingestion worker to skip re-summarizing already-stored jobs.
    """
    col = _get_collection()
    if col.count() == 0:
        return set()
    return set(col.get(include=[])['ids'])


def delete_old_jobs(older_than_days: int = 30) -> int:
    """
    Removes jobs ingested more than `older_than_days` ago.
    Keeps the DB fresh and prevents stale listings from appearing.
    """
    col      = _get_collection()
    cutoff   = datetime.now().timestamp() - older_than_days * 86400
    all_data = col.get(include=["metadatas"])

    to_delete = []
    for i, meta in enumerate(all_data["metadatas"]):
        ingested_str = meta.get("ingested_at", "")
        try:
            ingested_ts = datetime.fromisoformat(ingested_str).timestamp()
            if ingested_ts < cutoff:
                to_delete.append(all_data["ids"][i])
        except Exception:
            pass  # Keep jobs with unparseable dates

    if to_delete:
        col.delete(ids=to_delete)
        print(f"🗑️  Removed {len(to_delete)} stale jobs (>{older_than_days} days old).")
    return len(to_delete)
