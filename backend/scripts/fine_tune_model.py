#!/usr/bin/env python3
"""
fine_tune_model.py — Standalone Fine-Tuning Script for Kindred Careers
======================================================================

Fine-tunes the all-MiniLM-L6-v2 sentence-transformer model on Egyptian
tech/creative job-market domain data. This script is completely standalone
and does NOT import any application modules (embeddings.py, vector_store.py,
main.py, worker.py).

Output: A custom fine-tuned model saved to:
    backend/local_storage/custom_kindred_model/

The fine-tuned model preserves the original 384-dimensional output space,
ensuring compatibility with the existing ChromaDB schema.

Usage:
    cd backend
    python scripts/fine_tune_model.py

Requirements (already in requirements.txt):
    - sentence-transformers>=3.0.0
    - torch
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

BASE_MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
EXPECTED_DIMENSIONS = 384

# Output path — relative to the backend/ directory
_SCRIPT_DIR = Path(__file__).resolve().parent          # backend/scripts/
_BACKEND_DIR = _SCRIPT_DIR.parent                       # backend/
OUTPUT_DIR = _BACKEND_DIR / "local_storage" / "custom_kindred_model"

# Training hyperparameters
EPOCHS = 4
BATCH_SIZE = 4
WARMUP_RATIO = 0.1  # 10% of training steps


def main() -> None:
    """Full fine-tuning pipeline: load → train → save → verify."""

    print("=" * 70)
    print("🚀 Kindred Careers — Embedding Model Fine-Tuning Script")
    print(f"   Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)

    # ──────────────────────────────────────────────────────────────────
    # Step 1: Load the base pre-trained model
    # ──────────────────────────────────────────────────────────────────
    print(f"\n📦 [Step 1/6] Loading base model: {BASE_MODEL_NAME}...")
    start_load = time.time()

    from sentence_transformers import SentenceTransformer, InputExample
    from sentence_transformers.sentence_transformer.losses import CosineSimilarityLoss
    from torch.utils.data import DataLoader

    model = SentenceTransformer(BASE_MODEL_NAME)
    load_time = time.time() - start_load

    base_dim = model.get_embedding_dimension()
    print(f"✅ Base model loaded in {load_time:.1f}s")
    print(f"   Architecture: {BASE_MODEL_NAME}")
    print(f"   Embedding dimensions: {base_dim}")
    print(f"   Expected dimensions: {EXPECTED_DIMENSIONS}")
    assert base_dim == EXPECTED_DIMENSIONS, (
        f"❌ Dimension mismatch! Expected {EXPECTED_DIMENSIONS}, got {base_dim}"
    )

    # ──────────────────────────────────────────────────────────────────
    # Step 2: Define domain-specific training dataset
    #
    # Each InputExample pairs a PROFILE description with a JOB description
    # using the exact text formatting from our production embeddings:
    #   Profile: "Professional candidate with expertise in {fields}..."
    #   Job:     "Job Title: {title}. Company: {company}..."
    #
    # Positive pairs (label 0.85–0.95): profile matches the job
    # Negative pairs (label 0.10–0.20): profile does NOT match the job
    # ──────────────────────────────────────────────────────────────────
    print("\n📊 [Step 2/6] Building domain-specific training dataset...")

    train_examples = [
        # ── Positive Pairs: Software Engineering ───────────────────────
        InputExample(
            texts=[
                "Professional candidate with expertise in Software Engineering. "
                "Core skills include: Python, Django, PostgreSQL, REST APIs. "
                "Work history: Backend Developer at Instabug. "
                "Prefers Remote work in Cairo, Egypt.",

                "Job Title: Senior Python Developer. "
                "Company: Instabug. Industry: Technology. "
                "Required Skills: Python, Django, REST APIs, PostgreSQL. "
                "Work Mode: Remote. Location: Cairo, Egypt. "
                "Description: Build scalable backend services for a leading "
                "Egyptian SaaS company serving millions of mobile developers.",
            ],
            label=0.92,
        ),
        InputExample(
            texts=[
                "Professional candidate with expertise in Software Engineering. "
                "Core skills include: Java, Spring Boot, Microservices, AWS. "
                "Work history: Software Engineer at Vodafone Egypt. "
                "Prefers Hybrid work in Cairo, Egypt.",

                "Job Title: Java Backend Engineer. "
                "Company: Vodafone Egypt. Industry: Telecommunications. "
                "Required Skills: Java, Spring Boot, Microservices, Docker. "
                "Work Mode: Hybrid. Location: Smart Village, Egypt. "
                "Description: Design and maintain high-throughput telecom "
                "backend systems processing millions of daily transactions.",
            ],
            label=0.90,
        ),
        InputExample(
            texts=[
                "Professional candidate with expertise in Software Engineering. "
                "Core skills include: Node.js, TypeScript, Express, MongoDB. "
                "Work history: Full Stack Developer at Breadfast. "
                "Prefers Onsite work in Cairo, Egypt.",

                "Job Title: Full Stack JavaScript Developer. "
                "Company: Breadfast. Industry: E-Commerce. "
                "Required Skills: Node.js, TypeScript, React, MongoDB. "
                "Work Mode: Onsite. Location: Cairo, Egypt. "
                "Description: Build and scale the grocery delivery platform "
                "serving hundreds of thousands of Egyptian households daily.",
            ],
            label=0.91,
        ),

        # ── Positive Pairs: Mobile Development ────────────────────────
        InputExample(
            texts=[
                "Professional candidate with expertise in Mobile Development. "
                "Core skills include: Flutter, Dart, Firebase, REST APIs. "
                "Work history: Mobile Developer at Swvl. "
                "Prefers Remote work in Cairo, Egypt.",

                "Job Title: Flutter Developer. "
                "Company: Swvl. Industry: Transportation Technology. "
                "Required Skills: Flutter, Dart, Firebase, REST APIs, Git. "
                "Work Mode: Remote. Location: Cairo, Egypt. "
                "Description: Develop cross-platform mobile applications for "
                "a mass transit technology company operating across MENA.",
            ],
            label=0.93,
        ),
        InputExample(
            texts=[
                "Professional candidate with expertise in Mobile Development. "
                "Core skills include: React Native, JavaScript, Redux, Firebase. "
                "Work history: Mobile Engineer at Halan. "
                "Prefers Hybrid work in Cairo, Egypt.",

                "Job Title: React Native Developer. "
                "Company: Halan. Industry: FinTech. "
                "Required Skills: React Native, JavaScript, Redux, REST APIs. "
                "Work Mode: Hybrid. Location: Cairo, Egypt. "
                "Description: Build mobile fintech solutions reaching millions "
                "of unbanked and underbanked users across Egypt.",
            ],
            label=0.90,
        ),

        # ── Positive Pairs: AI / Machine Learning ─────────────────────
        InputExample(
            texts=[
                "Professional candidate with expertise in Artificial Intelligence. "
                "Core skills include: Python, TensorFlow, PyTorch, NLP, Computer Vision. "
                "Work history: ML Engineer at Valeo Egypt. "
                "Prefers Hybrid work in Cairo, Egypt.",

                "Job Title: Machine Learning Engineer. "
                "Company: Valeo Egypt. Industry: Automotive Technology. "
                "Required Skills: Python, TensorFlow, PyTorch, Computer Vision. "
                "Work Mode: Hybrid. Location: Cairo, Egypt. "
                "Description: Develop deep learning models for autonomous driving "
                "perception systems at a global automotive technology leader.",
            ],
            label=0.93,
        ),
        InputExample(
            texts=[
                "Professional candidate with expertise in Data Science. "
                "Core skills include: Python, pandas, scikit-learn, SQL, Tableau. "
                "Work history: Data Analyst at Fawry. "
                "Prefers Onsite work in Cairo, Egypt.",

                "Job Title: Data Scientist. "
                "Company: Fawry. Industry: FinTech. "
                "Required Skills: Python, pandas, SQL, Machine Learning, Statistics. "
                "Work Mode: Onsite. Location: Cairo, Egypt. "
                "Description: Analyze transaction data and build predictive models "
                "for Egypt's leading electronic payments company.",
            ],
            label=0.88,
        ),

        # ── Positive Pairs: UI/UX Design ──────────────────────────────
        InputExample(
            texts=[
                "Professional candidate with expertise in UI/UX Design. "
                "Core skills include: Figma, Adobe XD, User Research, Prototyping. "
                "Work history: UX Designer at Breadfast. "
                "Prefers Remote work in Cairo, Egypt.",

                "Job Title: Senior UX Designer. "
                "Company: Breadfast. Industry: E-Commerce. "
                "Required Skills: Figma, Prototyping, User Research, Design Systems. "
                "Work Mode: Remote. Location: Cairo, Egypt. "
                "Description: Lead user experience design for a fast-growing "
                "grocery delivery app used by millions in Egypt.",
            ],
            label=0.90,
        ),
        InputExample(
            texts=[
                "Professional candidate with expertise in UI/UX Design. "
                "Core skills include: Sketch, InVision, Wireframing, Interaction Design. "
                "Work history: Product Designer at Paymob. "
                "Prefers Hybrid work in Cairo, Egypt.",

                "Job Title: Product Designer. "
                "Company: Paymob. Industry: FinTech. "
                "Required Skills: Figma, Sketch, Design Thinking, Wireframing. "
                "Work Mode: Hybrid. Location: Cairo, Egypt. "
                "Description: Design intuitive payment interfaces for merchants "
                "and consumers across the MENA region.",
            ],
            label=0.88,
        ),

        # ── Positive Pairs: Video Production & Creative ───────────────
        InputExample(
            texts=[
                "Professional candidate with expertise in Video Production. "
                "Core skills include: Adobe Premiere Pro, After Effects, DaVinci Resolve. "
                "Work history: Video Editor at MO4 Network. "
                "Prefers Onsite work in Cairo, Egypt.",

                "Job Title: Senior Video Editor. "
                "Company: MO4 Network. Industry: Digital Media. "
                "Required Skills: Premiere Pro, After Effects, Motion Graphics. "
                "Work Mode: Onsite. Location: Cairo, Egypt. "
                "Description: Edit and produce high-quality digital content for "
                "one of the largest Arabic-language YouTube networks.",
            ],
            label=0.91,
        ),
        InputExample(
            texts=[
                "Professional candidate with expertise in Creative Design. "
                "Core skills include: Adobe Photoshop, Illustrator, Brand Identity. "
                "Work history: Graphic Designer at Tribal DDB Cairo. "
                "Prefers Hybrid work in Cairo, Egypt.",

                "Job Title: Senior Graphic Designer. "
                "Company: Tribal DDB Cairo. Industry: Advertising. "
                "Required Skills: Photoshop, Illustrator, Brand Design, Typography. "
                "Work Mode: Hybrid. Location: Cairo, Egypt. "
                "Description: Create compelling visual campaigns for major "
                "regional and international brand accounts.",
            ],
            label=0.89,
        ),

        # ── Positive Pairs: Digital Marketing ─────────────────────────
        InputExample(
            texts=[
                "Professional candidate with expertise in Digital Marketing. "
                "Core skills include: SEO, Google Ads, Social Media Marketing, Analytics. "
                "Work history: Digital Marketing Specialist at Jumia Egypt. "
                "Prefers Remote work in Cairo, Egypt.",

                "Job Title: Digital Marketing Manager. "
                "Company: Jumia Egypt. Industry: E-Commerce. "
                "Required Skills: SEO, SEM, Google Analytics, Social Media. "
                "Work Mode: Remote. Location: Cairo, Egypt. "
                "Description: Drive user acquisition and engagement strategies "
                "for Africa's largest e-commerce marketplace.",
            ],
            label=0.90,
        ),

        # ── Positive Pairs: DevOps / Cloud ────────────────────────────
        InputExample(
            texts=[
                "Professional candidate with expertise in DevOps Engineering. "
                "Core skills include: Docker, Kubernetes, Terraform, AWS, CI/CD. "
                "Work history: DevOps Engineer at Si-Ware Systems. "
                "Prefers Remote work in Cairo, Egypt.",

                "Job Title: Senior DevOps Engineer. "
                "Company: Si-Ware Systems. Industry: Semiconductor Technology. "
                "Required Skills: Docker, Kubernetes, Terraform, AWS, Jenkins. "
                "Work Mode: Remote. Location: Cairo, Egypt. "
                "Description: Build and maintain cloud infrastructure and CI/CD "
                "pipelines for cutting-edge MEMS chip design workflows.",
            ],
            label=0.91,
        ),

        # ── Positive Pairs: Data Analysis ─────────────────────────────
        InputExample(
            texts=[
                "Professional candidate with expertise in Data Analysis. "
                "Core skills include: SQL, Excel, Power BI, Python, Statistics. "
                "Work history: Business Analyst at Orange Egypt. "
                "Prefers Onsite work in Cairo, Egypt.",

                "Job Title: Data Analyst. "
                "Company: Orange Egypt. Industry: Telecommunications. "
                "Required Skills: SQL, Power BI, Excel, Python, Data Visualization. "
                "Work Mode: Onsite. Location: Cairo, Egypt. "
                "Description: Transform raw telecom data into actionable business "
                "insights for subscriber growth and retention strategies.",
            ],
            label=0.89,
        ),

        # ── Positive Pairs: Cross-domain relevance ────────────────────
        InputExample(
            texts=[
                "Professional candidate with expertise in Software Engineering. "
                "Core skills include: Python, FastAPI, Docker, PostgreSQL. "
                "Work history: Backend Developer at MaxAB. "
                "Prefers Remote work in Cairo, Egypt.",

                "Job Title: Python Backend Developer. "
                "Company: Capiter. Industry: B2B E-Commerce. "
                "Required Skills: Python, FastAPI, Docker, PostgreSQL, Redis. "
                "Work Mode: Remote. Location: Cairo, Egypt. "
                "Description: Build supply chain management APIs for a B2B "
                "marketplace connecting retailers with FMCG distributors.",
            ],
            label=0.87,
        ),
        InputExample(
            texts=[
                "Professional candidate with expertise in Mobile Development. "
                "Core skills include: Flutter, Dart, Firebase, Provider, Bloc. "
                "Work history: Junior Mobile Developer at Robusta Studio. "
                "Prefers Onsite work in Alexandria, Egypt.",

                "Job Title: Mobile Application Developer. "
                "Company: Robusta Studio. Industry: Software Consultancy. "
                "Required Skills: Flutter, Dart, Firebase, State Management. "
                "Work Mode: Onsite. Location: Alexandria, Egypt. "
                "Description: Develop beautiful cross-platform mobile apps for "
                "diverse client projects at a leading Egyptian software house.",
            ],
            label=0.92,
        ),

        # ── Negative Pairs: Mismatches ────────────────────────────────
        InputExample(
            texts=[
                "Professional candidate with expertise in Graphic Design. "
                "Core skills include: Adobe Photoshop, Illustrator, Brand Identity. "
                "Work history: Visual Designer at Leo Burnett Cairo. "
                "Prefers Onsite work in Cairo, Egypt.",

                "Job Title: Senior DevOps Engineer. "
                "Company: Amazon Web Services. Industry: Cloud Computing. "
                "Required Skills: Kubernetes, Terraform, AWS, Linux, CI/CD. "
                "Work Mode: Remote. Location: Cairo, Egypt. "
                "Description: Design and operate large-scale cloud infrastructure.",
            ],
            label=0.12,
        ),
        InputExample(
            texts=[
                "Professional candidate with expertise in Video Production. "
                "Core skills include: Adobe Premiere Pro, After Effects, Color Grading. "
                "Work history: Video Editor at ON TV. "
                "Prefers Onsite work in Cairo, Egypt.",

                "Job Title: Senior Backend Python Developer. "
                "Company: Microsoft Egypt. Industry: Technology. "
                "Required Skills: Python, Django, PostgreSQL, Microservices. "
                "Work Mode: Hybrid. Location: Cairo, Egypt. "
                "Description: Build enterprise-grade backend services at scale.",
            ],
            label=0.10,
        ),
        InputExample(
            texts=[
                "Professional candidate with expertise in Digital Marketing. "
                "Core skills include: Social Media Marketing, Content Strategy, SEO. "
                "Work history: Marketing Manager at Careem Egypt. "
                "Prefers Remote work in Cairo, Egypt.",

                "Job Title: Machine Learning Engineer. "
                "Company: Valeo Egypt. Industry: Automotive Technology. "
                "Required Skills: Python, PyTorch, TensorFlow, Computer Vision. "
                "Work Mode: Hybrid. Location: Cairo, Egypt. "
                "Description: Build deep learning models for ADAS systems.",
            ],
            label=0.15,
        ),
        InputExample(
            texts=[
                "Professional candidate with expertise in Human Resources. "
                "Core skills include: Recruitment, Employee Relations, HR Policies. "
                "Work history: HR Specialist at Teleperformance Egypt. "
                "Prefers Onsite work in Cairo, Egypt.",

                "Job Title: Flutter Mobile Developer. "
                "Company: Swvl. Industry: Transportation Technology. "
                "Required Skills: Flutter, Dart, Firebase, REST APIs. "
                "Work Mode: Remote. Location: Cairo, Egypt. "
                "Description: Build cross-platform mobile transportation apps.",
            ],
            label=0.10,
        ),
    ]

    n_positive = sum(1 for ex in train_examples if ex.label >= 0.5)
    n_negative = len(train_examples) - n_positive
    print(f"✅ Training dataset ready: {len(train_examples)} pairs "
          f"({n_positive} positive, {n_negative} negative)")

    # ──────────────────────────────────────────────────────────────────
    # Step 3: Configure loss function and data loader
    # ──────────────────────────────────────────────────────────────────
    print(f"\n⚙️  [Step 3/6] Configuring training pipeline...")

    train_dataloader = DataLoader(
        train_examples, shuffle=True, batch_size=BATCH_SIZE
    )
    train_loss = CosineSimilarityLoss(model)

    total_steps = len(train_dataloader) * EPOCHS
    warmup_steps = int(total_steps * WARMUP_RATIO)

    print(f"   Loss function: CosineSimilarityLoss")
    print(f"   Batch size: {BATCH_SIZE}")
    print(f"   Epochs: {EPOCHS}")
    print(f"   Total training steps: {total_steps}")
    print(f"   Warmup steps: {warmup_steps} ({WARMUP_RATIO:.0%})")

    # ──────────────────────────────────────────────────────────────────
    # Step 4: Train the model
    # ──────────────────────────────────────────────────────────────────
    print(f"\n🏋️  [Step 4/6] Starting fine-tuning...")
    print(f"   {'─' * 50}")

    start_train = time.time()
    model.fit(
        train_objectives=[(train_dataloader, train_loss)],
        epochs=EPOCHS,
        warmup_steps=warmup_steps,
        show_progress_bar=True,
        output_path=str(OUTPUT_DIR),  # Checkpoint saves during training
    )
    train_time = time.time() - start_train

    print(f"   {'─' * 50}")
    print(f"✅ Fine-tuning complete in {train_time:.1f}s")

    # ──────────────────────────────────────────────────────────────────
    # Step 5: Save the fine-tuned model
    # ──────────────────────────────────────────────────────────────────
    print(f"\n💾 [Step 5/6] Saving fine-tuned model...")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    model.save(str(OUTPUT_DIR))

    abs_path = OUTPUT_DIR.resolve()
    print(f"✅ Model saved successfully!")
    print(f"   Path: {abs_path}")

    # List saved files
    saved_files = list(OUTPUT_DIR.rglob("*"))
    saved_size_mb = sum(f.stat().st_size for f in saved_files if f.is_file()) / (1024 * 1024)
    print(f"   Total files: {sum(1 for f in saved_files if f.is_file())}")
    print(f"   Total size: {saved_size_mb:.1f} MB")

    # ──────────────────────────────────────────────────────────────────
    # Step 6: Verify the fine-tuned model
    # ──────────────────────────────────────────────────────────────────
    print(f"\n🔍 [Step 6/6] Verifying fine-tuned model dimensions...")

    # Reload from disk to confirm the save was clean
    verified_model = SentenceTransformer(str(OUTPUT_DIR))

    test_sentence = (
        "Professional candidate with expertise in Software Engineering. "
        "Core skills include: Flutter, Dart, Firebase. "
        "Prefers Remote work in Cairo, Egypt."
    )
    test_embedding = verified_model.encode(test_sentence, normalize_embeddings=True)
    actual_dim = len(test_embedding)

    if actual_dim == EXPECTED_DIMENSIONS:
        print(f"✅ DIMENSION CHECK PASSED: {actual_dim} dimensions")
        print(f"   The fine-tuned model is fully compatible with ChromaDB.")
    else:
        print(f"❌ DIMENSION CHECK FAILED: expected {EXPECTED_DIMENSIONS}, got {actual_dim}")
        sys.exit(1)

    # ──────────────────────────────────────────────────────────────────
    # Final Summary
    # ──────────────────────────────────────────────────────────────────
    print(f"\n{'=' * 70}")
    print(f"🎉 FINE-TUNING COMPLETE — Summary")
    print(f"{'=' * 70}")
    print(f"   Base model:       {BASE_MODEL_NAME}")
    print(f"   Training pairs:   {len(train_examples)} ({n_positive} pos, {n_negative} neg)")
    print(f"   Epochs:           {EPOCHS}")
    print(f"   Training time:    {train_time:.1f}s")
    print(f"   Output dimensions:{actual_dim} (verified ✅)")
    print(f"   Model saved to:   {abs_path}")
    print(f"   Model size:       {saved_size_mb:.1f} MB")
    print(f"{'=' * 70}")
    print()
    print("📋 Next steps:")
    print("   1. Run the migration script to re-embed existing ChromaDB jobs:")
    print("      > python scripts/migrate_embeddings.py")
    print()
    print("   2. Update backend/.env to use the fine-tuned model:")
    print(f"      EMBED_MODEL=./local_storage/custom_kindred_model")
    print()
    print("   3. Restart the backend server:")
    print("      > python main.py")
    print()
    print("   ⚡ To roll back: revert EMBED_MODEL in .env and re-run migration.")
    print()


if __name__ == "__main__":
    main()
