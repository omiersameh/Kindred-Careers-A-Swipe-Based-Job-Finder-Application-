from __future__ import annotations
import os
import re
import json
from openai import AsyncOpenAI
from dotenv import load_dotenv
from typing import Optional

# Load .env from the backend/ directory
load_dotenv()

# Groq client — extremely fast, high free tier rate limits
_client = AsyncOpenAI(
    base_url="https://api.groq.com/openai/v1",
    api_key=os.getenv("GROQ_API_KEY", ""),
)
_MODEL = os.getenv("SUMMARIZER_MODEL", "llama-3.3-70b-versatile")

_SYSTEM_PROMPT = """You are a job listing analyst for a mobile swipe-based job app.
Analyze the job listing and return ONLY a valid JSON object with this exact schema:
{
  "title": "Clean job title",
  "company": "Company name",
  "location": "City, Country or Remote",
  "workMode": "Remote or Hybrid or Onsite",
  "industry": "Industry type",
  "requiredSkills": ["skill1", "skill2", "skill3"],
  "summaryBullets": ["Key point 1", "Key point 2", "Key point 3"],
  "vibeTag": "Short phrase like: Fast-paced Startup or Global Tech Giant",
  "minSalary": 0,
  "maxSalary": 0,
  "description": "One paragraph description",
  "jobType": "Full-Time or Part-Time or Contract or Internship"
}
Rules:
- Return ONLY the JSON object. No markdown, no explanation, no code fences.
- Use double quotes for all strings.
- Do not add trailing commas.
- All fields are required. Use empty string or 0 if unknown."""


def _clean_json(raw: str) -> str:
    """
    Attempts to fix common JSON issues produced by LLMs:
    - Extracts the outermost { } block
    - Removes trailing commas before ] or }
    - Replaces single-quoted strings with double-quoted strings
    """
    # Extract outermost { } block
    start = raw.find("{")
    end = raw.rfind("}")
    if start != -1 and end != -1 and end > start:
        raw = raw[start:end + 1]

    # Remove trailing commas before closing braces/brackets
    raw = re.sub(r",\s*([\]}])", r"\1", raw)

    return raw


async def summarize_job(raw_text: str) -> dict:
    """
    Uses Llama 3.3 70B (free via OpenRouter) to convert raw job text
    into a structured JSON object for the app swipe cards.
    """
    try:
        response = await _client.chat.completions.create(
            model=_MODEL,
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": f"Job listing to analyze:\n{raw_text[:3000]}"},
            ],
            temperature=0.3,
            max_tokens=800, # Large text models don't need thinking tokens
        )

        message = response.choices[0].message
        raw = message.content or ""

        # Strip </think> reasoning wrappers some models use
        if "</think>" in raw:
            raw = raw.split("</think>")[-1]

        # Strip markdown code fences
        if "```" in raw:
            parts = raw.split("```")
            for part in parts:
                part = part.strip()
                if part.startswith("json"):
                    part = part[4:]
                if part.startswith("{"):
                    raw = part
                    break

        raw = raw.strip()

        if not raw:
            print(f"⚠️  Model returned empty content.")
            return {}

        # Clean and parse JSON
        data = json.loads(_clean_json(raw))
        data["imageUrl"] = "" # Intentionally ignore images for now
        data["logoEmoji"] = _get_logo_emoji(data.get("industry", ""))
        return data

    except json.JSONDecodeError as e:
        print(f"⚠️  JSON parse error from model: {e}")
        return {}
    except Exception as e:
        print(f"⚠️  Summarization failed: {e}")
        return {}


def _get_logo_emoji(industry: str) -> str:
    """Returns a relevant emoji based on the job industry."""
    industry = industry.lower()
    mapping = {
        "tech": "💻",  "software": "💻", "engineering": "⚙️",
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
