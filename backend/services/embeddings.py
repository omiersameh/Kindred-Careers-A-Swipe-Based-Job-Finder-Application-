from __future__ import annotations
import os
from typing import List, Optional
from sentence_transformers import SentenceTransformer
from models.user_profile import UserProfile

# all-MiniLM-L6-v2: 384-dim, ~90MB — 8× smaller than nomic-embed-text-v1.5.
# No API key needed; runs locally via sentence-transformers.
# IMPORTANT: If changing the embedding model, delete ./chroma_db and re-run ingestion
# (ChromaDB collections are dimension-specific and can't mix 384d with 768d vectors).
_MODEL_NAME = os.getenv("EMBED_MODEL", "sentence-transformers/all-MiniLM-L6-v2")
_model: Optional[SentenceTransformer] = None


def _get_model() -> SentenceTransformer:
    """Lazy-loads the embedding model on first use."""
    global _model
    if _model is None:
        print(f"📦 Loading embedding model: {_MODEL_NAME}...")
        _model = SentenceTransformer(_MODEL_NAME)
        print("✅ Embedding model loaded.")
    return _model


def embed_text(text: str) -> List[float]:
    """Converts a string into a semantic embedding vector."""
    model = _get_model()
    embedding = model.encode(text, normalize_embeddings=True)
    return embedding.tolist()


def embed_job(job: dict) -> List[float]:
    """
    Builds a rich text representation of a job listing and embeds it.
    Combines title, company, skills, and description for best match quality.
    """
    skills_str = ", ".join(job.get("requiredSkills", []))
    bullets_str = " ".join(job.get("summaryBullets", []))
    text = (
        f"Job Title: {job.get('title', '')}. "
        f"Company: {job.get('company', '')}. "
        f"Industry: {job.get('industry', '')}. "
        f"Required Skills: {skills_str}. "
        f"Work Mode: {job.get('workMode', '')}. "
        f"Location: {job.get('location', '')}. "
        f"Summary: {bullets_str} "
        f"Description: {job.get('description', '')[:500]}"
    )
    return embed_text(text)


def embed_profile(profile: UserProfile) -> List[float]:
    """
    Builds a professional summary from the user profile and embeds it.
    This creates the "query vector" used to search ChromaDB for matching jobs.
    """
    skills_str = ", ".join(profile.skills)
    fields_str = ", ".join(profile.careerFields)
    exp_str = " ".join([f"{e.jobTitle} at {e.company}" for e in profile.experiences])

    # Using a rich prose prompt improves semantic match quality significantly
    text = (
        f"Professional candidate with expertise in {fields_str}. "
        f"Core skills include: {skills_str}. "
        f"Work history: {exp_str}. "
        f"Prefers {profile.preferredWorkMode} work in {profile.location}. "
        f"Bio: {profile.bio}"
    )
    return embed_text(text)
