#!/usr/bin/env python3
"""
migrate_embeddings.py — Re-embed Existing ChromaDB Jobs with Fine-Tuned Model
==============================================================================

After fine-tuning the embedding model, run this script to re-compute
embeddings for all existing jobs in ChromaDB using the new model weights.

This preserves all job data (titles, descriptions, metadata) and only
updates the embedding vectors. No jobs are deleted.

Usage:
    cd backend
    python scripts/migrate_embeddings.py

This script is standalone — it does NOT import from services/embeddings.py
or any other application module. It connects to ChromaDB directly and
uses sentence-transformers directly.
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path
from datetime import datetime

# ──────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────

_SCRIPT_DIR = Path(__file__).resolve().parent          # backend/scripts/
_BACKEND_DIR = _SCRIPT_DIR.parent                       # backend/

# Model path — uses the fine-tuned model by default; override via CLI arg
DEFAULT_MODEL_PATH = str(_BACKEND_DIR / "local_storage" / "custom_kindred_model")

# ChromaDB path — matches backend/.env CHROMA_PATH default
CHROMA_PATH = os.getenv("CHROMA_PATH", str(_BACKEND_DIR / "chroma_db"))
COLLECTION_NAME = "job_listings"

EXPECTED_DIMENSIONS = 384


def _reconstruct_embed_text(meta: dict, document: str) -> str:
    """
    Reconstructs the text that was originally embedded for a job listing.
    Mirrors the format used in services/embeddings.py → embed_job().

    This ensures the re-embedding uses the exact same text representation
    so that the only variable is the model weights (base vs fine-tuned).
    """
    skills_str = meta.get("requiredSkills", "")
    bullets_str = meta.get("summaryBullets", "").replace(" | ", " ")
    description = document or meta.get("description", "")

    text = (
        f"Job Title: {meta.get('title', '')}. "
        f"Company: {meta.get('company', '')}. "
        f"Industry: {meta.get('industry', '')}. "
        f"Required Skills: {skills_str}. "
        f"Work Mode: {meta.get('workMode', '')}. "
        f"Location: {meta.get('location', '')}. "
        f"Summary: {bullets_str} "
        f"Description: {description[:500]}"
    )
    return text


def main() -> None:
    """Re-embed all existing ChromaDB jobs using the specified model."""

    # Allow model path override via CLI argument
    model_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MODEL_PATH

    print("=" * 70)
    print("🔄 Kindred Careers — ChromaDB Embedding Migration")
    print(f"   Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)

    # ──────────────────────────────────────────────────────────────────
    # Step 1: Load the model
    # ──────────────────────────────────────────────────────────────────
    print(f"\n📦 [Step 1/5] Loading embedding model...")
    print(f"   Model path: {model_path}")

    from sentence_transformers import SentenceTransformer
    import chromadb

    if not Path(model_path).exists():
        print(f"❌ Model directory not found: {model_path}")
        print("   Run fine_tune_model.py first, or provide a valid model path.")
        sys.exit(1)

    start_load = time.time()
    model = SentenceTransformer(model_path)
    load_time = time.time() - start_load

    dim = model.get_embedding_dimension()
    print(f"✅ Model loaded in {load_time:.1f}s (dimensions: {dim})")
    assert dim == EXPECTED_DIMENSIONS, (
        f"❌ Dimension mismatch! Expected {EXPECTED_DIMENSIONS}, got {dim}. "
        f"This model is incompatible with the existing ChromaDB collection."
    )

    # ──────────────────────────────────────────────────────────────────
    # Step 2: Connect to ChromaDB and read all jobs
    # ──────────────────────────────────────────────────────────────────
    print(f"\n📂 [Step 2/5] Connecting to ChromaDB...")
    print(f"   Path: {CHROMA_PATH}")

    if not Path(CHROMA_PATH).exists():
        print(f"❌ ChromaDB directory not found: {CHROMA_PATH}")
        print("   There are no jobs to migrate.")
        sys.exit(1)

    client = chromadb.PersistentClient(path=CHROMA_PATH)

    try:
        collection = client.get_collection(
            name=COLLECTION_NAME,
            # Don't specify metadata here — use existing collection config
        )
    except Exception as e:
        print(f"❌ Collection '{COLLECTION_NAME}' not found: {e}")
        sys.exit(1)

    total_jobs = collection.count()
    print(f"✅ Connected. Found {total_jobs} jobs in '{COLLECTION_NAME}'.")

    if total_jobs == 0:
        print("   Nothing to migrate — collection is empty.")
        return

    # ──────────────────────────────────────────────────────────────────
    # Step 3: Fetch all jobs (IDs, metadata, documents)
    # ──────────────────────────────────────────────────────────────────
    print(f"\n📋 [Step 3/5] Fetching all job records...")

    all_data = collection.get(
        include=["metadatas", "documents"],
    )

    ids = all_data["ids"]
    metadatas = all_data["metadatas"]
    documents = all_data["documents"] or [""] * len(ids)

    print(f"✅ Fetched {len(ids)} job records (IDs, metadata, documents).")

    # ──────────────────────────────────────────────────────────────────
    # Step 4: Re-embed and upsert in batches
    # ──────────────────────────────────────────────────────────────────
    print(f"\n🔄 [Step 4/5] Re-embedding all jobs with the new model...")

    BATCH_SIZE = 32  # Process in batches for efficiency
    start_embed = time.time()

    for batch_start in range(0, len(ids), BATCH_SIZE):
        batch_end = min(batch_start + BATCH_SIZE, len(ids))
        batch_ids = ids[batch_start:batch_end]
        batch_metas = metadatas[batch_start:batch_end]
        batch_docs = documents[batch_start:batch_end]

        # Reconstruct the text for each job
        texts = [
            _reconstruct_embed_text(meta, doc)
            for meta, doc in zip(batch_metas, batch_docs)
        ]

        # Batch-encode for efficiency
        embeddings = model.encode(
            texts, normalize_embeddings=True, show_progress_bar=False
        )

        # Upsert with new embeddings (same IDs and metadata)
        collection.upsert(
            ids=batch_ids,
            embeddings=embeddings.tolist(),
            metadatas=batch_metas,
            documents=batch_docs,
        )

        progress = min(batch_end, len(ids))
        print(f"   🔄 Re-embedded {progress}/{len(ids)} jobs...")

    embed_time = time.time() - start_embed
    print(f"✅ Re-embedding complete in {embed_time:.1f}s")

    # ──────────────────────────────────────────────────────────────────
    # Step 5: Verify no jobs were lost
    # ──────────────────────────────────────────────────────────────────
    print(f"\n🔍 [Step 5/5] Verifying collection integrity...")

    final_count = collection.count()

    if final_count == total_jobs:
        print(f"✅ MIGRATION SUCCESSFUL: {total_jobs} → {final_count} jobs (0 lost)")
    else:
        print(f"⚠️  WARNING: Job count changed! {total_jobs} → {final_count}")
        print(f"   {abs(final_count - total_jobs)} jobs may have been affected.")

    # ──────────────────────────────────────────────────────────────────
    # Final Summary
    # ──────────────────────────────────────────────────────────────────
    print(f"\n{'=' * 70}")
    print(f"🎉 MIGRATION COMPLETE — Summary")
    print(f"{'=' * 70}")
    print(f"   Model used:       {model_path}")
    print(f"   Dimensions:       {dim} (verified ✅)")
    print(f"   Jobs migrated:    {total_jobs}")
    print(f"   Jobs in DB after: {final_count}")
    print(f"   Migration time:   {embed_time:.1f}s")
    print(f"   Data loss:        {'NONE ✅' if final_count == total_jobs else '⚠️ SEE ABOVE'}")
    print(f"{'=' * 70}")
    print()
    print("📋 Next steps:")
    print("   1. Update backend/.env to use the fine-tuned model:")
    print(f"      EMBED_MODEL=./local_storage/custom_kindred_model")
    print()
    print("   2. Restart the backend server:")
    print("      > python main.py")
    print()
    print("   The scraper will automatically use the fine-tuned model for new jobs.")
    print()


if __name__ == "__main__":
    main()
