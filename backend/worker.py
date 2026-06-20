"""
worker.py — Background pipeline worker (v3.0 — Stream Ingestion Architecture).

Ingestion Architecture (v3.0):
  - Real-Time Stream: Each page task commits jobs to ChromaDB immediately
    after Groq extraction. No global batch. If a page hangs, previously
    committed jobs are safe on disk.
  - Defensive Navigation: Semaphore(3), 45s goto timeout, isolated
    try/except per page. A single timeout cannot stall other tasks.
  - Role-First Query Routing: Builds hyper-focused Wuzzuf search queries
    from the user's job titles (60%) and top skills (40%), falling back
    to broad careerFields only when granular queries fail.
  - Target: 60 job listings per run via paginated Wuzzuf scraping.
  - 12 Groq calls × 5 jobs = 60-job deep cache pool per run.
  - Embed + store in ChromaDB with dedup and freshness factor.
  - Purge stale jobs (> 14 days).
"""

import asyncio
import traceback
import json
import re
import math
import urllib.parse
from datetime import datetime
from typing import Optional, List, Set, Dict, Tuple

from camoufox.async_api import AsyncCamoufox
from services.job_summarizer import _client
from services.embeddings import embed_job
from services.vector_store import add_job, get_job_count, delete_old_jobs, get_existing_job_ids, make_stable_id

_is_running = False
_last_run: datetime | None = None
_INTERVAL_MINUTES = 60
_last_known_profile = None

# ── 60-job bulk ingestion constants ────────────────────────────────────
# Total Groq LLM calls per ingestion run (5 jobs extracted per call)
_TARGET_GROQ_CALLS = 12
# Jobs extracted per single Groq LLM call (per Wuzzuf page scrape)
_JOBS_PER_GROQ_CALL = 5
# Total job target per run: 12 calls × 5 jobs = 60 jobs
_TARGET_JOB_POOL = _TARGET_GROQ_CALLS * _JOBS_PER_GROQ_CALL  # 60
# Wuzzuf results per page (used to calculate &start= offset)
_WUZZUF_PAGE_SIZE = 10
# Maximum concurrent browser pages (balances CPU/RAM vs throughput)
_MAX_CONCURRENT_PAGES = 3
# Browser navigation timeout in milliseconds
_GOTO_TIMEOUT_MS = 45000


# ──────────────────────────────────────────────────────────────────────
# helper for logo emojis
# ──────────────────────────────────────────────────────────────────────

def _get_logo_emoji(industry: str) -> str:
    industry = industry.lower()
    mapping = {
        "tech": "💻", "software": "💻", "engineering": "⚙️",
        "design": "🎨", "marketing": "📢", "finance": "💰",
        "healthcare": "🏥", "education": "🎓", "legal": "⚖️",
        "retail": "🛍️", "logistics": "🚚", "media": "📺",
        "consulting": "💼", "research": "🔬", "hospitality": "🏨",
        "data": "📊", "ai": "🤖", "devops": "🔧",
    }
    for key, emoji in mapping.items():
        if key in industry:
            return emoji
    return "🏢"


# ──────────────────────────────────────────────────────────────────────
# Role-First Query Routing Matrix
#
# Builds hyper-focused Wuzzuf search queries from the user's profile:
#   Primary (60% → 7 calls): Most recent jobTitle from experiences
#   Secondary (40% → 5 calls): Top 2 specific skills (3+2 split)
#   Fallback: careerFields → static defaults
# ──────────────────────────────────────────────────────────────────────

def _build_search_queries(profile=None) -> List[Tuple[str, int, str]]:
    """
    Returns a list of (search_query, num_pages, fallback_query) tuples that sum to
    _TARGET_GROQ_CALLS total pages (12).

    Specialty-First Priority Matrix:
      - Primary Field Allocation (7 pages): Distribute across the user's selected specializations for their first career field.
      - Secondary Field Allocation (5 pages): Distribute across the user's selected specializations for their second career field (if any).
      - If only one field is selected, distribute all 12 pages across its specializations.
      - Fallback: The exact parent field of the specialization.
    """
    queries: List[Tuple[str, int, str]] = []

    if profile and hasattr(profile, "specializations") and profile.specializations:
        fields = list(profile.specializations.keys())

        def distribute(specs: List[str], total_pages: int, parent_field: str):
            if not specs:
                return []
            base = total_pages // len(specs)
            remainder = total_pages % len(specs)
            res = []
            for i, spec in enumerate(specs):
                pages = base + (1 if i < remainder else 0)
                if pages > 0:
                    res.append((spec, pages, parent_field))
            return res

        if len(fields) >= 2:
            primary_field = fields[0]
            primary_specs = profile.specializations[primary_field]
            secondary_field = fields[1]
            secondary_specs = profile.specializations[secondary_field]
            
            queries.extend(distribute(primary_specs, 7, primary_field))
            queries.extend(distribute(secondary_specs, 5, secondary_field))
            
            if not primary_specs:
                queries.append((primary_field, 7, primary_field))
            if not secondary_specs:
                queries.append((secondary_field, 5, secondary_field))
                
        elif len(fields) == 1:
            primary_field = fields[0]
            primary_specs = profile.specializations[primary_field]
            queries.extend(distribute(primary_specs, 12, primary_field))
            if not primary_specs:
                queries.append((primary_field, 12, primary_field))

    elif profile and hasattr(profile, "careerFields") and profile.careerFields:
        career_fields = list(profile.careerFields)
        per_field = max(1, _TARGET_GROQ_CALLS // len(career_fields))
        remainder = _TARGET_GROQ_CALLS % len(career_fields)
        for i, field in enumerate(career_fields):
            queries.append((field, per_field + (1 if i < remainder else 0), field))

    if not queries:
        # Absolute fallback — no profile data at all
        queries = [
            ("Technology", 4, "Technology"),
            ("Engineering", 4, "Engineering"),
            ("Business & Finance", 4, "Business & Finance"),
        ]

    # Ensure total pages sum to exactly _TARGET_GROQ_CALLS
    total_allocated = sum(p for _, p, _ in queries)
    if total_allocated < _TARGET_GROQ_CALLS and queries:
        deficit = _TARGET_GROQ_CALLS - total_allocated
        q, p, f = queries[0]
        queries[0] = (q, p + deficit, f)

    return queries


# ──────────────────────────────────────────────────────────────────────
# Step 1: Groq llama-3.1-8b-instant extractor & summarizer
# Processes up to 5 jobs per LLM call (1 Wuzzuf page = 1 Groq call)
# ──────────────────────────────────────────────────────────────────────

async def extract_jobs_from_text(text: str, career_field: str) -> List[dict]:
    if not text.strip():
        return []

    prompt = f"""You are an expert job listing extraction assistant.
Analyze the following text extracted from a job search results page (Wuzzuf) and extract the job listings.
Extract up to 5 job listings, prioritizing ones that are relevant to the career field '{career_field}'.

Return ONLY a valid JSON array of objects matching this exact schema:
[
  {{
    "title": "Clean job title",
    "company": "Company name",
    "location": "City, Country or Remote (e.g. Cairo, Egypt or Remote)",
    "workMode": "Remote or Hybrid or Onsite",
    "industry": "Industry type",
    "careerField": "{career_field}",
    "specialization": "A specific 1-3 word job specialization. Do NOT use slashes (/). Use '&' or '-' instead (e.g., 'Backend Developer', 'Frontend Developer', 'UX Designer', 'Mobile Developer')",
    "requiredSkills": ["skill1", "skill2"],
    "summaryBullets": ["Key point 1", "Key point 2", "Key point 3"],
    "vibeTag": "Short phrase like: Fast-paced Startup or Global Tech Giant",
    "minSalary": 0,
    "maxSalary": 0,
    "description": "One paragraph description summarizing the job based on the listing details",
    "jobType": "Full-Time or Part-Time or Contract or Internship"
  }}
]

Rules:
- Return ONLY the JSON array. Do NOT wrap it in markdown code blocks like ```json ... ```. No explanation, no intro, no outro.
- If no jobs are found in the text, return an empty array [].
- All fields are required. Use empty string or 0 if unknown.
"""
    try:
        response = await _client.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[
                {"role": "system", "content": prompt},
                {"role": "user", "content": f"Extracted Text:\n{text[:15000]}"}
            ],
            temperature=0.2,
            max_tokens=2500,
        )

        raw_response = response.choices[0].message.content or ""

        # Clean and parse JSON
        raw_response = raw_response.strip()
        if "</think>" in raw_response:
            raw_response = raw_response.split("</think>")[-1].strip()

        if "```" in raw_response:
            parts = raw_response.split("```")
            for part in parts:
                part = part.strip()
                if part.startswith("json"):
                    part = part[4:]
                if part.startswith("["):
                    raw_response = part
                    break

        raw_response = raw_response.strip()
        start = raw_response.find("[")
        end = raw_response.rfind("]")
        if start != -1 and end != -1:
            raw_response = raw_response[start:end + 1]

        raw_response = re.sub(r",\s*([\]}])", r"\1", raw_response)

        jobs = json.loads(raw_response)
        if not isinstance(jobs, list):
            return []

        print(f"📊 [Groq] Extracted {len(jobs)} jobs for query '{career_field}'")
        return jobs
    except Exception as e:
        print(f"❌ [Groq] Extraction failed for '{career_field}': {e}")
        return []


# ──────────────────────────────────────────────────────────────────────
# Step 2: Immediate per-page commit to ChromaDB
#
# Each page task calls this right after Groq extraction.
# Jobs are deduplicated against `existing_ids` (snapshot taken at pipeline
# start) and committed to ChromaDB inline. If a later page hangs or
# crashes, all previously committed jobs remain safe on disk.
# ──────────────────────────────────────────────────────────────────────

def _commit_jobs_immediately(
    extracted_jobs: List[dict],
    existing_ids: Set[str],
    stats_lock: asyncio.Lock,
    stats: Dict[str, int],
) -> int:
    """
    Deduplicates, embeds, and upserts a batch of jobs from a single page
    directly into ChromaDB. Returns the number of new jobs committed.

    This function is synchronous (embed_job and add_job are sync) but
    called from async context. Since embedding is CPU-bound and fast
    (~5ms per job on MiniLM-L6-v2), blocking the event loop briefly
    here is acceptable and simpler than wrapping in run_in_executor.
    """
    committed = 0
    for job_data in extracted_jobs:
        title = job_data.get("title", "")
        company = job_data.get("company", "")
        job_id = make_stable_id(title, company)

        if job_id in existing_ids:
            continue  # Already in ChromaDB — skip

        try:
            job_data["id"] = job_id
            job_data.setdefault("postedDate", datetime.now().strftime("%Y-%m-%d"))
            job_data["logoEmoji"] = _get_logo_emoji(job_data.get("industry", ""))
            job_data["imageUrl"] = ""

            embedding = embed_job(job_data)
            add_job(job_data, embedding)

            # Mark as existing so other concurrent tasks don't re-insert
            existing_ids.add(job_id)
            committed += 1

        except Exception as e:
            print(f"  ⚠️ [Commit] Embed/store failed for '{title}': {e}")

    return committed


# ──────────────────────────────────────────────────────────────────────
# Step 3: Paginated Camoufox scraper with stream ingestion
#
# Architecture (v3.0):
#   - Semaphore(3) bounds concurrent browser pages
#   - 45s goto timeout allows Cloudflare challenges to clear
#   - Each page task: scrape → Groq extract → commit to ChromaDB inline
#   - Per-page try/except isolation: one timeout ≠ pipeline failure
#   - Fallback: if a granular query returns 0 cards, retry with broad
#     career field string
# ──────────────────────────────────────────────────────────────────────

async def _run_stream_ingestion(
    queries: List[Tuple[str, int, str]],
    existing_ids: Set[str],
) -> Dict[str, int]:
    """
    Opens a single Camoufox browser session and dispatches page tasks
    for each (query, num_pages) pair. Each page commits jobs inline.

    Returns aggregated stats dict.
    """
    stats = {"scraped": 0, "committed": 0, "failed_pages": 0, "skipped_existing": 0}
    stats_lock = asyncio.Lock()

    # Build the complete task manifest: list of (query_string, page_index, fallback_query)
    task_manifest: List[Tuple[str, int, Optional[str]]] = []
    for query, num_pages, fallback in queries:
        for page_idx in range(num_pages):
            task_manifest.append((query, page_idx, fallback))

    total_tasks = len(task_manifest)
    print(f"🕵️‍♂️ [Camoufox] Launching stealth browser | "
          f"{total_tasks} page tasks across {len(queries)} queries "
          f"(concurrency limit = {_MAX_CONCURRENT_PAGES})")
    print(f"📋 [Queries] {[(q, p, f) for q, p, f in queries]}")

    try:
        async with AsyncCamoufox(headless=True) as browser:
            sem = asyncio.Semaphore(_MAX_CONCURRENT_PAGES)

            async def process_page(query: str, page_index: int, fallback_query: Optional[str]):
                """Self-contained page task: scrape → extract → commit."""
                async with sem:
                    start_offset = page_index * _WUZZUF_PAGE_SIZE
                    encoded_query = urllib.parse.quote(query)
                    url = f"https://wuzzuf.net/search/jobs?q={encoded_query}&start={start_offset}"
                    page = None
                    try:
                        page = await browser.new_page()
                        await page.set_viewport_size({"width": 1280, "height": 800})
                        await page.goto(url, wait_until="domcontentloaded", timeout=_GOTO_TIMEOUT_MS)

                        # Wait for job cards to render
                        try:
                            await page.wait_for_selector(
                                "div.css-1gatmva, [class*='css-1gatmva'], "
                                "div.css-la3ug8, [class*='css-la3ug8']",
                                timeout=10000
                            )
                        except Exception:
                            await asyncio.sleep(2)

                        # Extract job card text content
                        card_locators = await page.locator(
                            "div.css-1gatmva, [class*='css-1gatmva'], "
                            "div.css-la3ug8, [class*='css-la3ug8']"
                        ).all()

                        if card_locators:
                            print(f"    [Camoufox] '{query}' page {page_index}: "
                                  f"{len(card_locators)} job cards found")
                            text_content = "\n---\n".join(
                                [await card.inner_text() for card in card_locators[:10]]
                            )
                        else:
                            # ── Fallback: try broader career field query ──
                            if fallback_query and fallback_query.lower() != query.lower():
                                print(f"    [Camoufox] '{query}' page {page_index}: "
                                      f"0 cards found — falling back to broad query '{fallback_query}'")
                                await page.close()
                                page = await browser.new_page()
                                await page.set_viewport_size({"width": 1280, "height": 800})
                                fallback_url = (
                                    f"https://wuzzuf.net/search/jobs?"
                                    f"q={urllib.parse.quote(fallback_query)}&start={start_offset}"
                                )
                                await page.goto(fallback_url, wait_until="domcontentloaded",
                                                timeout=_GOTO_TIMEOUT_MS)
                                try:
                                    await page.wait_for_selector(
                                        "div.css-1gatmva, [class*='css-1gatmva'], "
                                        "div.css-la3ug8, [class*='css-la3ug8']",
                                        timeout=10000
                                    )
                                except Exception:
                                    await asyncio.sleep(2)

                                card_locators = await page.locator(
                                    "div.css-1gatmva, [class*='css-1gatmva'], "
                                    "div.css-la3ug8, [class*='css-la3ug8']"
                                ).all()

                                if card_locators:
                                    print(f"    [Camoufox] Fallback '{fallback_query}' page {page_index}: "
                                          f"{len(card_locators)} job cards found")
                                    text_content = "\n---\n".join(
                                        [await card.inner_text() for card in card_locators[:10]]
                                    )
                                else:
                                    print(f"    [Camoufox] Fallback '{fallback_query}' page {page_index}: "
                                          f"Selector not found — extracting body fallback")
                                    text_content = await page.locator(
                                        ".css-96695u, .css-la3ug8, body"
                                    ).first.inner_text()
                                    text_content = text_content[:15000]
                            else:
                                print(f"    [Camoufox] '{query}' page {page_index}: "
                                      f"Selector not found — extracting body fallback")
                                text_content = await page.locator(
                                    ".css-96695u, .css-la3ug8, body"
                                ).first.inner_text()
                                text_content = text_content[:15000]

                        # ── Groq LLM extraction ──
                        extracted_jobs = await extract_jobs_from_text(text_content, query)
                        print(f"    ✓ '{query}' page {page_index} (start={start_offset}): "
                              f"{len(extracted_jobs)} jobs extracted")

                        # ── Immediate commit to ChromaDB ──
                        if extracted_jobs:
                            committed = _commit_jobs_immediately(
                                extracted_jobs, existing_ids, stats_lock, stats
                            )
                            async with stats_lock:
                                stats["scraped"] += len(extracted_jobs)
                                stats["committed"] += committed
                                stats["skipped_existing"] += len(extracted_jobs) - committed
                            print(f"    💾 [Commit] '{query}' page {page_index}: "
                                  f"{committed} new jobs saved to ChromaDB "
                                  f"({len(extracted_jobs) - committed} duplicates skipped)")

                    except Exception as e:
                        print(f"⚠️ [Page] Error on '{query}' page {page_index}: {e}")
                        async with stats_lock:
                            stats["failed_pages"] += 1
                    finally:
                        if page is not None:
                            try:
                                await page.close()
                            except Exception:
                                pass  # Page may already be closed from fallback

            # ── Launch all tasks with semaphore-bounded concurrency ──
            print(f"⚡ [Camoufox] Dispatching {total_tasks} page tasks "
                  f"(concurrency limit = {_MAX_CONCURRENT_PAGES})...")

            tasks = [
                process_page(query, page_idx, fallback)
                for query, page_idx, fallback in task_manifest
            ]
            await asyncio.gather(*tasks)

    except Exception as e:
        print(f"❌ [Camoufox] Browser session failed: {e}")
        traceback.print_exc()

    return stats


# ──────────────────────────────────────────────────────────────────────
# Main ingestion pipeline
# ──────────────────────────────────────────────────────────────────────

async def run_ingestion_pipeline(profile=None) -> dict:
    """
    Full pipeline (v3.0 — Stream Ingestion):
      1. Build Role-First query matrix from user profile
      2. Snapshot existing ChromaDB IDs for dedup
      3. Launch Camoufox with stream ingestion (each page commits inline)
      4. Purge stale jobs (> 14 days)

    Each page task is self-contained: scrape → extract → commit.
    If any page hangs or times out, previously committed jobs are safe.
    """
    global _is_running, _last_run, _last_known_profile

    if profile is not None:
        _last_known_profile = profile
    active_profile = profile or _last_known_profile

    if _is_running:
        return {"status": "already_running", "message": "Pipeline is already running."}

    _is_running = True
    final_stats = {"scraped": 0, "committed": 0, "failed_pages": 0,
                   "skipped_existing": 0, "purged": 0, "job_count": 0}

    try:
        print(f"\n{'='*60}")
        print(f"🚀 Wuzzuf 60-Job Stream Ingestion starting at {datetime.now().strftime('%H:%M:%S')}")
        print(f"   Target: {_TARGET_JOB_POOL} jobs via {_TARGET_GROQ_CALLS} Groq calls")
        print(f"{'='*60}")

        # ── Step 1: Build Role-First query matrix ──────────────────────
        queries = _build_search_queries(active_profile)

        total_pages = sum(p for _, p, _ in queries)
        print(f"  📋 Query matrix ({total_pages} pages total):")
        for query, pages, fallback in queries:
            print(f"      → '{query}' (fallback: '{fallback}'): {pages} pages ({pages * _JOBS_PER_GROQ_CALL} job target)")

        # ── Step 2: Snapshot existing IDs for dedup ────────────────────
        existing_ids = get_existing_job_ids()
        print(f"  📦 ChromaDB has {len(existing_ids)} existing jobs (dedup snapshot taken)")

        # ── Step 3: Stream ingestion — each page commits inline ────────
        stats = await _run_stream_ingestion(queries, existing_ids)
        final_stats.update(stats)

        # ── Step 4: Purge stale jobs (> 14 days) ──────────────────────
        purged = delete_old_jobs(older_than_days=14)
        final_stats["purged"] = purged
        final_stats["job_count"] = get_job_count()
        _last_run = datetime.now()

        print(f"\n✅ Stream Ingestion complete:")
        print(f"   Scraped: {final_stats['scraped']} | "
              f"Committed: {final_stats['committed']} | "
              f"Duplicates: {final_stats['skipped_existing']} | "
              f"Failed pages: {final_stats['failed_pages']} | "
              f"Purged: {final_stats['purged']}")
        print(f"   Total jobs in DB: {final_stats['job_count']}")

    except Exception as e:
        print(f"❌ Fatal pipeline error: {e}")
        traceback.print_exc()
    finally:
        _is_running = False

    return final_stats


async def start_background_worker():
    """
    Recurring background worker.
    Starts with a check to see if an immediate initial run is needed.
    """
    if get_job_count() == 0:
        print("⚡ Database is empty. Starting immediate 60-job stream ingestion...")
        asyncio.create_task(run_ingestion_pipeline())

    print(f"⏳ Background worker scheduled — next 60-job refresh in {_INTERVAL_MINUTES} min...")
    await asyncio.sleep(_INTERVAL_MINUTES * 60)
    while True:
        try:
            await run_ingestion_pipeline()
        except Exception as e:
            print(f"❌ Background worker error: {e}")
        print(f"⏳ Next 60-job ingestion in {_INTERVAL_MINUTES} minutes...\n")
        await asyncio.sleep(_INTERVAL_MINUTES * 60)


def get_worker_status() -> dict:
    return {
        "is_running": _is_running,
        "last_run":   _last_run.isoformat() if _last_run else None,
        "interval_minutes": _INTERVAL_MINUTES,
        "job_count":  get_job_count(),
        "ingestion_target": {
            "total_jobs": _TARGET_JOB_POOL,
            "groq_calls": _TARGET_GROQ_CALLS,
            "jobs_per_call": _JOBS_PER_GROQ_CALL,
        },
    }
