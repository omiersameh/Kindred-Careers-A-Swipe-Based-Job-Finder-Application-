"""
worker.py — Background pipeline worker (Revamped for Phase 3 + Wuzzuf Camoufox Scraping).

New Architecture:
  - Startup: SKIP scraping. Serve jobs already in ChromaDB.
  - Scrape WUZZUF in parallel using AsyncCamoufox (stealth headless browser)
  - Parameterize URL with user's selected career fields: https://wuzzuf.net/search/jobs?q={career_field}
  - CSS Locator: Extract only the job cards text content to minimize Groq token usage
  - Groq LLM (llama-3.1-8b-instant): Extract and structure job listings from the text directly
  - Embed + store in ChromaDB with dedup and freshness factor
  - Purge stale jobs (> 14 days)
"""

import asyncio
import traceback
import json
import re
import urllib.parse
from datetime import datetime
from typing import Optional, List, Set

from camoufox.async_api import AsyncCamoufox
from services.job_summarizer import _client
from services.embeddings import embed_job
from services.vector_store import add_job, get_job_count, delete_old_jobs, get_existing_job_ids, make_stable_id

_is_running = False
_last_run: datetime | None = None
_INTERVAL_MINUTES = 60
_last_known_profile = None


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
# Step 1: Groq llama-3.1-8b-instant extractor & summarizer
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

        print(f"📊 [Groq] Extracted {len(jobs)} jobs for career field '{career_field}'")
        return jobs
    except Exception as e:
        print(f"❌ [Groq] Extraction failed for '{career_field}': {e}")
        return []


# ──────────────────────────────────────────────────────────────────────
# Step 2: Parallel Camoufox scraper targeting Wuzzuf
# ──────────────────────────────────────────────────────────────────────

async def scrape_all_fields_wuzzuf(fields: List[str]) -> List[dict]:
    all_jobs = []
    print(f"🕵️‍♂️ [Camoufox] Launching single stealth browser to scrape fields: {fields}")
    try:
        async with AsyncCamoufox(headless=True) as browser:
            async def process_field_in_page(field: str) -> List[dict]:
                encoded_field = urllib.parse.quote(field)
                url = f"https://wuzzuf.net/search/jobs?q={encoded_field}"
                page = await browser.new_page()
                try:
                    await page.set_viewport_size({"width": 1280, "height": 800})
                    await page.goto(url, wait_until="networkidle", timeout=30000)

                    # Wait for any job card container to load
                    try:
                        await page.wait_for_selector("div.css-1gatmva, [class*='css-1gatmva']", timeout=5000)
                    except Exception:
                        await asyncio.sleep(2)

                    # Use CSS Locator to extract only the job cards text content
                    card_locators = await page.locator("div.css-1gatmva, [class*='css-1gatmva'], div.css-la3ug8, [class*='css-la3ug8']").all()
                    if card_locators:
                        print(f"    [Camoufox] Found {len(card_locators)} job cards for '{field}'")
                        text_content = "\n---\n".join([await card.inner_text() for card in card_locators[:10]])
                    else:
                        print(f"    [Camoufox] Job cards selector not found for '{field}'. Extracting first layout container...")
                        text_content = await page.locator(".css-96695u, .css-la3ug8, body").first.inner_text()
                        text_content = text_content[:15000]

                    extracted_jobs = await extract_jobs_from_text(text_content, field)
                    return extracted_jobs
                except Exception as e:
                    print(f"⚠️ Error scraping '{url}': {e}")
                    return []
                finally:
                    await page.close()

            tasks = [process_field_in_page(field) for field in fields]
            results = await asyncio.gather(*tasks)
            for res in results:
                all_jobs.extend(res)
    except Exception as e:
        print(f"❌ [Camoufox] Browser failed: {e}")
    return all_jobs


# ──────────────────────────────────────────────────────────────────────
# Main ingestion pipeline
# ──────────────────────────────────────────────────────────────────────

async def run_ingestion_pipeline(profile=None) -> dict:
    """
    Full pipeline: Parallel Camoufox Scrape → Locator Inner Text Extract → Groq Summarize → Embed → Store → Purge.
    """
    global _is_running, _last_run, _last_known_profile

    if profile is not None:
        _last_known_profile = profile
    active_profile = profile or _last_known_profile

    if _is_running:
        return {"status": "already_running", "message": "Pipeline is already running."}

    _is_running = True
    stats = {"scraped": 0, "processed": 0, "failed": 0, "purged": 0, "job_count": 0}

    try:
        print(f"\n{'='*55}")
        print(f"🚀 Wuzzuf Camoufox Ingestion starting at {datetime.now().strftime('%H:%M:%S')}")
        print(f"{'='*55}")

        # Determine target career fields
        fields = []
        if active_profile and hasattr(active_profile, "careerFields") and active_profile.careerFields:
            fields = list(active_profile.careerFields)
        else:
            # Default fallback career fields
            fields = ["Technology", "Engineering", "Business & Finance"]

        # Step 1: Scrape in Parallel using Camoufox & Groq
        raw_jobs = await scrape_all_fields_wuzzuf(fields)
        stats["scraped"] = len(raw_jobs)
        print(f"  ✓ Scraped and extracted {len(raw_jobs)} job listings from Wuzzuf")

        if not raw_jobs:
            print("  ℹ️ No jobs scraped. Ingestion complete.")
            stats["job_count"] = get_job_count()
            return stats

        # Step 2: Dedup against existing ChromaDB
        existing_ids = get_existing_job_ids()
        new_only = []
        for job in raw_jobs:
            title = job.get("title", "")
            company = job.get("company", "")
            job_id = make_stable_id(title, company)
            if job_id not in existing_ids:
                job["id"] = job_id
                new_only.append(job)

        stats["skipped_existing"] = len(raw_jobs) - len(new_only)
        print(f"  ⏩ Skipped {stats['skipped_existing']} jobs already in DB ({len(new_only)} truly new)")

        if not new_only:
            print("  ℹ️ All scraped jobs already stored. Done.")
            stats["job_count"] = get_job_count()
            return stats

        # Step 3: Embed + Store in ChromaDB
        for i, job_data in enumerate(new_only):
            try:
                job_data.setdefault("postedDate", datetime.now().strftime("%Y-%m-%d"))
                job_data["logoEmoji"] = _get_logo_emoji(job_data.get("industry", ""))
                job_data["imageUrl"] = ""

                embedding = embed_job(job_data)
                add_job(job_data, embedding)
                stats["processed"] += 1
            except Exception as e:
                stats["failed"] += 1
                print(f"  ⚠️ Embed/store failed for job {i+1}: {e}")

        # Step 4: Purge stale jobs (> 14 days)
        purged = delete_old_jobs(older_than_days=14)
        stats["purged"] = purged

        stats["job_count"] = get_job_count()
        _last_run = datetime.now()

        print(f"\n✅ Ingestion complete:")
        print(f"   Scraped: {stats['scraped']} | Processed: {stats['processed']} | "
              f"Failed: {stats['failed']} | Purged: {stats['purged']}")
        print(f"   Total jobs in DB: {stats['job_count']}")

    except Exception as e:
        print(f"❌ Fatal pipeline error: {e}")
        traceback.print_exc()
    finally:
        _is_running = False

    return stats


async def start_background_worker():
    """
    Recurring background worker.
    Starts with a check to see if an immediate initial run is needed.
    """
    if get_job_count() == 0:
        print("⚡ Database is empty. Starting immediate initial ingestion...")
        asyncio.create_task(run_ingestion_pipeline())

    print(f"⏳ Background worker scheduled — next refresh in {_INTERVAL_MINUTES} min...")
    await asyncio.sleep(_INTERVAL_MINUTES * 60)
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

