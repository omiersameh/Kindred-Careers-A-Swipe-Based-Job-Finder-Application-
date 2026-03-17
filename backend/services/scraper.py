"""
scraper.py — Dynamic, profile-driven multi-source job scraper.

Reliable Sources (no auth, no JS rendering required):
  • Remotive       → category-mapped JSON API (best for remote tech jobs)
  • RemoteOK       → public JSON API with tag search
  • We Work Remotely → RSS with keyword search
  • Arbeitnow      → open tech job board with paged API
  • Jobicy         → free remote jobs API with category/tag filter
  • The Muse       → free jobs API with category/page filter

How it works:
  1. Receive optional UserProfile
  2. Build keyword + category pool from profile fields and skills
  3. Each source uses a different subset each run → different results every time
  4. Return deduplicated list ready for AI summarization
"""

import asyncio
import random
import uuid
import re
import httpx
from bs4 import BeautifulSoup
from datetime import datetime
from typing import List, Optional

# ──────────────────────────────────────────────────────────────────
# Defaults and Remotive category map
# ──────────────────────────────────────────────────────────────────

_DEFAULT_KEYWORDS = [
    "software engineer", "product manager", "data scientist",
    "machine learning", "ui ux designer", "devops engineer",
    "backend developer", "frontend developer", "mobile developer",
    "cloud engineer", "business analyst", "full stack developer",
    "python developer", "flutter developer", "data analyst",
]

# Map common career field keywords to Remotive categories
_REMOTIVE_CATEGORY_MAP = {
    "software": "software-dev",
    "developer": "software-dev",
    "engineer": "software-dev",
    "programming": "software-dev",
    "flutter": "software-dev",
    "mobile": "software-dev",
    "frontend": "software-dev",
    "backend": "software-dev",
    "fullstack": "software-dev",
    "full stack": "software-dev",
    "data": "data",
    "machine learning": "data",
    "ai": "data",
    "ml": "data",
    "analyst": "data",
    "devops": "devops-sysadmin",
    "cloud": "devops-sysadmin",
    "infrastructure": "devops-sysadmin",
    "design": "design",
    "ux": "design",
    "ui": "design",
    "product": "product",
    "marketing": "marketing",
    "finance": "finance-legal",
    "legal": "finance-legal",
    "qa": "quality-assurance",
    "testing": "quality-assurance",
    "support": "customer-support",
    "project": "project-mgmt",
    "manager": "project-mgmt",
    "sales": "sales-business",
    "business": "sales-business",
    "writing": "writing",
}

_JOBICY_INDUSTRY_MAP = {
    "software": "programming",
    "developer": "programming",
    "engineer": "programming",
    "flutter": "programming",
    "data": "data-science",
    "machine learning": "data-science",
    "design": "design",
    "ux": "design",
    "marketing": "marketing",
    "product": "product-management",
    "finance": "finance",
    "sales": "sales",
    "devops": "devops-sysadmin",
}

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "en-US,en;q=0.9",
    "Accept": "application/json, text/html, */*",
}


# ──────────────────────────────────────────────────────────────────
# Keyword / Category Builder
# ──────────────────────────────────────────────────────────────────

def _build_keyword_pool(profile=None) -> List[str]:
    """Builds a shuffled pool of search terms from user profile."""
    if profile is None:
        keywords = _DEFAULT_KEYWORDS.copy()
        random.shuffle(keywords)
        return keywords[:8]

    pool = []
    for field in getattr(profile, "careerFields", []):
        pool.append(field)
        clean = field.lower().strip()
        if not any(x in clean for x in ["engineer", "manager", "analyst"]):
            pool.append(f"{clean} developer")

    skills = list(getattr(profile, "skills", []))
    if skills:
        sampled = random.sample(skills, min(6, len(skills)))
        pool.extend(sampled)
        if getattr(profile, "careerFields", []):
            pool.append(f"{sampled[0]} {profile.careerFields[0].lower()}")

    for exp in list(getattr(profile, "experiences", []))[:2]:
        title = getattr(exp, "jobTitle", "")
        if title:
            pool.append(title)

    if len(pool) < 4:
        pool.extend(random.sample(_DEFAULT_KEYWORDS, 4))

    random.shuffle(pool)
    return list(dict.fromkeys(pool))  # deduplicate, preserve order


def _map_to_remotive_category(profile=None) -> List[str]:
    """Maps profile fields to Remotive API category IDs."""
    cats = set()
    texts = []
    if profile:
        texts.extend(getattr(profile, "careerFields", []))
        texts.extend(list(getattr(profile, "skills", []))[:5])
    for text in texts:
        lower = text.lower()
        for kw, cat in _REMOTIVE_CATEGORY_MAP.items():
            if kw in lower:
                cats.add(cat)
    if not cats:
        cats = {"software-dev", "data"}
    return list(cats)[:3]  # max 3 categories


def _map_to_jobicy_industry(profile=None) -> str:
    """Maps profile fields to Jobicy industry string."""
    if not profile:
        return "programming"
    texts = list(getattr(profile, "careerFields", [])) + list(getattr(profile, "skills", []))[:3]
    for text in texts:
        lower = text.lower()
        for kw, ind in _JOBICY_INDUSTRY_MAP.items():
            if kw in lower:
                return ind
    return "programming"


def _pick(pool: List[str], n: int = 3) -> List[str]:
    return pool[:n]


# ──────────────────────────────────────────────────────────────────
# Main Entry
# ──────────────────────────────────────────────────────────────────

async def scrape_all_sources(profile=None) -> List[dict]:
    """
    Fetches job listings from 6 reliable sources, dynamically keyed
    to the user's profile. Returns a deduplicated, shuffled list.
    """
    keyword_pool = _build_keyword_pool(profile)
    location = getattr(profile, "location", "") or ""
    work_mode = getattr(profile, "preferredWorkMode", "Any") or "Any"

    print(f"\n🔎 Scraping with keywords: {keyword_pool[:6]}")
    print(f"   Location: '{location or 'Any'}' | Work mode: {work_mode}")

    all_jobs: List[dict] = []
    seen: set = set()

    async with httpx.AsyncClient(
        timeout=20.0,
        follow_redirects=True,
        headers=_HEADERS,
    ) as client:
        results = await asyncio.gather(
            _fetch_remotive(client, profile),
            _fetch_remoteok(client, keyword_pool),
            _fetch_wwr(client, keyword_pool),
            _fetch_arbeitnow(client),
            _fetch_jobicy(client, profile, keyword_pool),
            _fetch_the_muse(client, profile),
            return_exceptions=True,
        )

        for result in results:
            if isinstance(result, Exception):
                print(f"  ⚠️  Source error: {result}")
                continue
            for job in result:
                key = (
                    f"{job.get('title','').lower().strip()}"
                    f"|{job.get('company','').lower().strip()}"
                )
                if key not in seen and key != "|":
                    seen.add(key)
                    all_jobs.append(job)

    random.shuffle(all_jobs)
    print(f"🔍 Scraped {len(all_jobs)} unique job listings from all sources\n")
    return all_jobs


# ──────────────────────────────────────────────────────────────────
# Source 1: Remotive — category-based JSON API
# Far more reliable than keyword search
# ──────────────────────────────────────────────────────────────────

async def _fetch_remotive(client: httpx.AsyncClient, profile=None) -> List[dict]:
    """Uses Remotive's /api/remote-jobs?category= for reliable results."""
    jobs = []
    categories = _map_to_remotive_category(profile)
    random.shuffle(categories)

    for cat in categories[:2]:
        try:
            url = f"https://remotive.com/api/remote-jobs?category={cat}&limit=15"
            resp = await client.get(url)
            if resp.status_code != 200:
                continue
            data = resp.json()
            for item in data.get("jobs", []):
                soup = BeautifulSoup(item.get("description", ""), "lxml")
                clean_desc = soup.get_text(separator=" ", strip=True)[:2000]
                jobs.append({
                    "id":          str(uuid.uuid4()),
                    "raw_text":    (
                        f"{item.get('title', '')} at {item.get('company_name', '')}. "
                        f"Category: {item.get('category', '')}. "
                        f"Tags: {', '.join(item.get('tags', []))}. "
                        f"{clean_desc}"
                    ),
                    "source":      "remotive",
                    "posted_date": item.get("publication_date", datetime.now().isoformat()),
                    "company":     item.get("company_name", ""),
                    "title":       item.get("title", ""),
                    "image_url":   item.get("company_logo", ""),
                })
            await asyncio.sleep(0.4)
        except Exception as e:
            print(f"  ⚠️  Remotive ({cat}): {e}")

    print(f"  ✓ Remotive: {len(jobs)} jobs")
    return jobs


# ──────────────────────────────────────────────────────────────────
# Source 2: RemoteOK — public JSON API
# ──────────────────────────────────────────────────────────────────

async def _fetch_remoteok(client: httpx.AsyncClient, keywords: List[str]) -> List[dict]:
    """RemoteOK /api?tag= returns tech-focused remote jobs."""
    jobs = []
    for kw in _pick(keywords, 2):
        try:
            tag = re.sub(r"[^a-z0-9\-]", "-", kw.lower().strip())
            url = f"https://remoteok.io/api?tag={tag}"
            resp = await client.get(
                url,
                headers={**_HEADERS, "Referer": "https://remoteok.io"},
            )
            if resp.status_code != 200:
                continue
            items = resp.json()
            for item in items[1:12]:  # Skip first meta element
                if not isinstance(item, dict):
                    continue
                position = item.get("position") or item.get("title") or ""
                if not position:
                    continue
                tags = item.get("tags", []) or []
                desc = BeautifulSoup(item.get("description", "") or "", "lxml") \
                           .get_text(strip=True)[:2000]
                jobs.append({
                    "id":          str(uuid.uuid4()),
                    "raw_text":    (
                        f"{position} at {item.get('company', '')}. "
                        f"Location: {item.get('location', 'Remote')}. "
                        f"Tags: {', '.join(str(t) for t in tags)}. {desc}"
                    ),
                    "source":      "remoteok",
                    "posted_date": item.get("date", datetime.now().isoformat()),
                    "company":     str(item.get("company", "")),
                    "title":       str(position),
                    "image_url":   str(item.get("company_logo", "") or ""),
                })
            await asyncio.sleep(1.5)  # RemoteOK rate-limits aggressively
        except Exception as e:
            print(f"  ⚠️  RemoteOK '{kw}': {e}")

    print(f"  ✓ RemoteOK: {len(jobs)} jobs")
    return jobs


# ──────────────────────────────────────────────────────────────────
# Source 3: We Work Remotely — RSS with keyword search
# ──────────────────────────────────────────────────────────────────

async def _fetch_wwr(client: httpx.AsyncClient, keywords: List[str]) -> List[dict]:
    """We Work Remotely RSS with keyword term."""
    jobs = []
    for kw in _pick(keywords, 2):
        try:
            url = f"https://weworkremotely.com/remote-jobs.rss?term={kw.replace(' ', '+')}"
            resp = await client.get(url, headers={**_HEADERS, "Accept": "application/rss+xml"})
            if resp.status_code != 200:
                continue
            soup = BeautifulSoup(resp.text, "lxml-xml")
            for item in soup.find_all("item")[:8]:
                title_el   = item.find("title")
                desc_el    = item.find("description")
                raw_title  = title_el.text.strip() if title_el else ""
                parts      = raw_title.split(":", 1)
                company    = parts[0].strip() if len(parts) > 1 else ""
                job_title  = parts[1].strip() if len(parts) > 1 else raw_title
                clean_desc = BeautifulSoup(
                    desc_el.text if desc_el else "", "lxml"
                ).get_text(strip=True)[:2000]
                if not job_title:
                    continue
                jobs.append({
                    "id":          str(uuid.uuid4()),
                    "raw_text":    f"{job_title} at {company}. {clean_desc}",
                    "source":      "weworkremotely",
                    "posted_date": datetime.now().isoformat(),
                    "company":     company,
                    "title":       job_title,
                    "image_url":   "",
                })
            await asyncio.sleep(0.4)
        except Exception as e:
            print(f"  ⚠️  WWR '{kw}': {e}")

    print(f"  ✓ We Work Remotely: {len(jobs)} jobs")
    return jobs


# ──────────────────────────────────────────────────────────────────
# Source 4: Arbeitnow — free paged tech job board
# ──────────────────────────────────────────────────────────────────

async def _fetch_arbeitnow(client: httpx.AsyncClient) -> List[dict]:
    """Random page from Arbeitnow's open API gives variety every run."""
    try:
        page = random.randint(1, 8)
        url = f"https://www.arbeitnow.com/api/job-board-api?page={page}"
        resp = await client.get(url)
        if resp.status_code != 200:
            return []
        data = resp.json()
        jobs = []
        for item in data.get("data", [])[:14]:
            desc_html  = item.get("description", "") or ""
            clean_desc = BeautifulSoup(desc_html, "lxml").get_text(strip=True)[:2000]
            tags       = item.get("tags", []) or []
            jobs.append({
                "id":          str(uuid.uuid4()),
                "raw_text":    (
                    f"{item.get('title', '')} at {item.get('company_name', '')}. "
                    f"Location: {item.get('location', '')}. "
                    f"Remote: {'Yes' if item.get('remote') else 'No'}. "
                    f"Tags: {', '.join(str(t) for t in tags)}. {clean_desc}"
                ),
                "source":      "arbeitnow",
                "posted_date": str(item.get("created_at", datetime.now().isoformat())),
                "company":     str(item.get("company_name", "")),
                "title":       str(item.get("title", "")),
                "image_url":   "",
            })
        print(f"  ✓ Arbeitnow (page {page}): {len(jobs)} jobs")
        return jobs
    except Exception as e:
        print(f"  ⚠️  Arbeitnow: {e}")
        return []


# ──────────────────────────────────────────────────────────────────
# Source 5: Jobicy — free remote jobs REST API
# Docs: https://jobicy.com/jobs-rss-feed
# ──────────────────────────────────────────────────────────────────

async def _fetch_jobicy(
    client: httpx.AsyncClient,
    profile=None,
    keywords: Optional[List[str]] = None,
) -> List[dict]:
    """
    Jobicy provides a free JSON API for remote jobs.
    API: https://jobicy.com/api/v2/remote-jobs?count=N&industry=X&tag=Y
    """
    jobs = []
    industry = _map_to_jobicy_industry(profile)
    tags     = _pick(keywords or [], 2)

    combos = [(industry, t) for t in tags] if tags else [(industry, "")]
    random.shuffle(combos)

    for ind, tag in combos[:2]:
        try:
            params = {"count": "15", "industry": ind}
            if tag:
                params["tag"] = tag.replace(" ", "+")
            url = "https://jobicy.com/api/v2/remote-jobs"
            resp = await client.get(url, params=params)
            if resp.status_code != 200:
                continue
            data = resp.json()
            for item in data.get("jobs", []):
                desc_html  = item.get("jobDescription", "") or ""
                clean_desc = BeautifulSoup(desc_html, "lxml").get_text(strip=True)[:2000]
                skills     = item.get("jobIndustry", []) or []
                type_str   = item.get("jobType", [])
                if isinstance(type_str, list):
                    type_str = ", ".join(str(x) for x in type_str)
                jobs.append({
                    "id":          str(uuid.uuid4()),
                    "raw_text":    (
                        f"{item.get('jobTitle', '')} at {item.get('companyName', '')}. "
                        f"Location: {item.get('jobLocation', 'Remote')}. "
                        f"Type: {type_str}. "
                        f"Skills: {', '.join(str(s) for s in skills)}. "
                        f"{clean_desc}"
                    ),
                    "source":      "jobicy",
                    "posted_date": str(item.get("pubDate", datetime.now().isoformat())),
                    "company":     str(item.get("companyName", "")),
                    "title":       str(item.get("jobTitle", "")),
                    "image_url":   str(item.get("companyLogo", "") or ""),
                })
            await asyncio.sleep(0.5)
        except Exception as e:
            print(f"  ⚠️  Jobicy ({ind}+{tag}): {e}")

    print(f"  ✓ Jobicy: {len(jobs)} jobs")
    return jobs


# ──────────────────────────────────────────────────────────────────
# Source 6: The Muse — free public jobs API
# Docs: https://www.themuse.com/developers/api/v2
# ──────────────────────────────────────────────────────────────────

async def _fetch_the_muse(
    client: httpx.AsyncClient,
    profile=None,
) -> List[dict]:
    """
    The Muse has a fully public, free REST API.
    Paging randomly ensures variety across scrape runs.
    """
    try:
        # Category mapping
        category = "Engineering"
        if profile:
            fields = [f.lower() for f in getattr(profile, "careerFields", [])]
            if any("design" in f or "ux" in f or "ui" in f for f in fields):
                category = "Design & UX"
            elif any("data" in f or "analyst" in f or "ml" in f for f in fields):
                category = "Data Science"
            elif any("product" in f for f in fields):
                category = "Product Management"
            elif any("market" in f for f in fields):
                category = "Marketing & PR"

        page = random.randint(0, 5)
        url = "https://www.themuse.com/api/public/jobs"
        params = {"category": category, "page": str(page), "level": "Senior Level"}
        resp   = await client.get(url, params=params)
        if resp.status_code != 200:
            # Try without level filter
            params.pop("level", None)
            resp = await client.get(url, params=params)
        if resp.status_code != 200:
            return []

        data  = resp.json()
        jobs  = []
        for item in data.get("results", [])[:12]:
            # Description is a list of sections
            sections = item.get("contents", "") or ""
            clean_desc = BeautifulSoup(sections, "lxml").get_text(strip=True)[:2000]
            company_obj = item.get("company", {}) or {}
            locs        = item.get("locations", []) or []
            location    = ", ".join(loc.get("name", "") for loc in locs[:2]) if locs else "Remote"
            levels      = item.get("levels", []) or []
            level_str   = ", ".join(lv.get("name", "") for lv in levels) if levels else ""
            jobs.append({
                "id":          str(uuid.uuid4()),
                "raw_text":    (
                    f"{item.get('name', '')} at {company_obj.get('name', '')}. "
                    f"Location: {location}. Level: {level_str}. "
                    f"Category: {category}. {clean_desc}"
                ),
                "source":      "themuse",
                "posted_date": str(item.get("publication_date", datetime.now().isoformat())),
                "company":     str(company_obj.get("name", "")),
                "title":       str(item.get("name", "")),
                "image_url":   "",
            })
        print(f"  ✓ The Muse ({category}, p{page}): {len(jobs)} jobs")
        return jobs
    except Exception as e:
        print(f"  ⚠️  The Muse: {e}")
        return []
