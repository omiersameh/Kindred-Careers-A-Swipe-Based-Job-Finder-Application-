# Kindred Careers - Project Context & Checkpoint

## 1. Project Overview
**Kindred Careers** is an AI-powered, swipe-based job matching application. It pairs users with jobs that fit their skills and preferences and can automatically generate highly tailored CVs for a specific job match using LLM/RAG pipelines.

## 2. Tech Stack Setup
### Frontend (Flutter App)
- **Framework**: Flutter / Dart
- **Architecture**: `Provider` for state management, OOP-based model structure (`Job`, `UserProfile`, `CV`, etc.).
- **Local Storage**: `shared_preferences` for caching the user's profile and questionnaire states locally on the device.
- **Auth & Analytics**: Firebase Authentication (Google Sign-in) & Firebase Analytics.
- **Key UI Packages**: `flutter_card_swiper` (for swipe mechanics), `flutter_animate`, `google_fonts`.

### Backend (Python)
- **Framework**: FastAPI (served via `uvicorn`).
- **AI/LLM (CV Generation)**: OpenRouter API (`openai/gpt-oss-120b:free`) for generating personalized CVs based on job descriptions and user profiles.
- **AI/LLM (Job Summarization)**: Groq API with `llama-3.1-8b-instant` — 14,400 RPM free tier, 10× faster than the previous 70B model.
- **RAG Pipeline**: ChromaDB (persistent vector DB) + `sentence-transformers/all-MiniLM-L6-v2` (384-dim, ~90MB, 8× lighter than the previous nomic model).

---

## 3. Current Implementation State

### Completed Features
- **Swipe-Based Job Feed**: Users can swipe right (Apply/Generate CV) or swipe left (Pass).
- **Dynamic CV Generation**: Swiping right connects to the backend to generate a tailored CV, displaying it in a modal with an option to download to the device.
- **Intelligent Questionnaire**: A comprehensive 8-step wizard for first-time sign-ins, gathering specialized career fields, name, contact info (auto-filled Google email + phone), and experience.
- **Mock Fallback System**: If the Python backend times out or is unreachable, the app falls back to local high-quality mock data so the job feed never breaks.
- **Profile Persistence**: Local caching of user profiles linked to their Firebase UID.

### UI / Aesthetic Design System
The app uses a premium "Liquid Glass & Gold" design system:
- **Global Theme**: Deep dark gray gradients (`#121212` to `#1E1E1E`).
- **Typography & Colors**: White body text, Gold headers and highlights (`kGold`, `kGoldDim`, `kGoldLight`).
- **Floating Navigation Bar**: Custom-built frosted/liquid glass bottom navigation bar using `BackdropFilter` and `ClipRRect`. Active tab highlighted in gold.
- **Job Cards**: Glassmorphism swipe cards with scroll-to-reveal full description + AI summary bullets.
- **UI Reference**: See `.agent/skills/ui-ux-pro-max/SKILL_ui.md` for design system generation commands.

### RAG Architecture (Phase 3 — Implemented 2026-04-21)
The backend now uses a two-tier fast/refresh architecture:

```
TIER 1 (FAST PATH — < 2s response):
  User opens app → ChromaDB pre-populated → Embed profile → Similarity search → Return jobs

TIER 2 (BACKGROUND REFRESH — every 60 min):
  1. Scrape all 6 sources in PARALLEL (asyncio.gather)
  2. Keyword pre-filter BEFORE LLM (drops ~85% irrelevant, ~5% relevance threshold)
  3. Batch summarize: 4 jobs per LLM call (3× throughput, ~85% fewer API calls)
  4. Embed + upsert into ChromaDB
  5. Purge stale jobs (> 14 days old)
```

**Models:**
- Summarizer: `llama-3.1-8b-instant` (Groq) — 14,400 RPM free, 10× faster than 70B
- Embeddings: `all-MiniLM-L6-v2` — 384-dim, ~90MB, loads in <2s
- CV Generation: `openai/gpt-oss-120b:free` (OpenRouter) — quality LLM for the CV task

> **⚠️ IMPORTANT**: Switching from nomic-embed-text-v1.5 (768d) to all-MiniLM-L6-v2 (384d) requires deleting `./backend/chroma_db/` and re-running the ingestion pipeline, as ChromaDB collections are dimension-specific.

---

## 4. Known Quirks & Local Environment Notes

1. **Physical Device Networking**:
   - When running on a **physical Android device**, set `API_URL=http://192.168.100.12:8000/api/generate-cv` in the frontend `.env`.
   - When running on the **Android emulator**, use `API_URL=http://10.0.2.2:8000/api/generate-cv` (10.0.2.2 is the emulator's alias for the host machine's 127.0.0.1).
   - **Crucial**: Backend must be started with `uvicorn main:app --host 0.0.0.0 --port 8000 --reload`.

2. **ChromaDB Reset Procedure** (after embedding model change):
   ```bash
   # Stop the backend server first, then:
   rm -rf backend/chroma_db/
   # Restart backend → it will auto-ingest (first background run after _INTERVAL_MINUTES)
   # Or trigger manually: POST /api/jobs/ingest
   ```

3. **iOS Icon Transparency Limitation**:
   - iOS rejects transparent background icons. `flutter_launcher_icons` iOS config is disabled (`ios: false`).

4. **SharedPreferences & Context**:
   - Questionnaire completion is stored per physical device. Switching from emulator to physical phone will re-trigger questionnaire. This is normal.

5. **Dart/Flutter Path**:
   - The user's PowerShell environment occasionally has issues recognizing `flutter`/`dart` globally. Use Android Studio terminal as fallback.

---

## 5. Bug Fixes Applied (2026-04-21)

### Phase 1 — Auth & Logout
- **`user_profile_service.dart`**: Removed eager UID read at provider construction (was null during Firebase SDK boot). Profile now initializes empty; `loadProfile()` in `_PostAuthRouter` handles the real load.
- **`main.dart`**: Added `'/'` named route pointing to `_AuthGate` for `pushNamedAndRemoveUntil` to work.
- **`profile_screen.dart`**: Logout button now calls `Navigator.pushNamedAndRemoveUntil('/')` after `AuthService.signOut()` so `_AuthGate`'s StreamBuilder takes control.

### Phase 2 — UI Fixes
- **`home_screen.dart`**: Removed `Future.microtask` that mutated `_jobs` during swipe animation (was causing the next card to vanish). Also added proper error snackbar for CV generation failures.
- **`job_card.dart`**: Pass/Apply buttons are now always fully opaque (removed scroll-gated `AnimatedOpacity`). Added `_AnimatedDecideButton` with 120ms scale-bounce animation for premium tactile feedback.
- **`.env` (frontend)**: Fixed `API_URL` from `127.0.0.1` (emulator loopback — wrong host) to `10.0.2.2` (correct Android emulator host alias).
- **`cv_generation_service.dart`**: Added 30-second timeout to HTTP call to prevent hanging.

### Phase 3 — RAG System Revamp
- **`worker.py`**: Complete rewrite with parallel scraping, keyword pre-filter, batch LLM summarization, stale job purging, and delayed first-run (startup now serves from ChromaDB instantly).
- **`main.py`**: Startup skips blocking scrape; serves from existing ChromaDB if populated.
- **`backend/.env`**: Switched to `llama-3.1-8b-instant` (summarizer) and `all-MiniLM-L6-v2` (embeddings).
- **`embeddings.py`**: Removed `trust_remote_code=True` (nomic-specific flag, not needed for MiniLM).

### Phase 4 — Persistence & ATS PDFs (2026-04-30)
- **Firebase Firestore Integration**: 
  - Provisioned Cloud Firestore with custom security rules restricted to authenticated users.
  - Implemented `DatabaseService` (`database_service.dart`) to persist matched jobs and generated CVs under `/users/{uid}/matches`.
  - Refactored `AppState` to dynamically load data on initialization instead of starting from scratch every session.
  - Added JSON serialization to `Job` and `CV` models.
- **ATS-Optimized PDF CVs**:
  - Created `cv_pdf_generator.py` in the backend using `reportlab` for clean, professional PDF generation without watermarks.
  - Provided a POST endpoint `/api/generate-cv-pdf`.
  - Upgraded frontend `cv_preview_dialog.dart` to save the PDF file locally and sync its path via `localPdfPath` field to Firestore.
- **UI/UX Stabilization**:
  - Solved `RenderFlex` overflow issues in `matched_jobs_screen.dart` via `Flexible` wrapping.
  - Cleaned up obsolete overlays and stack errors in `home_screen.dart`.
- **RAG Cost Optimization**:
  - Integrated ChromaDB deduplication filter into `worker.py` to prevent repeated scraping and LLM summarization of jobs already ingested.
- **Security Check**:
  - Fortified `.gitignore` to prevent leakage of `.env`, `chroma_db`, keystores, and generated local PDF files.

---

## 6. Next Steps & How to Run the Project

### 1. Starting the Backend (FastAPI)
The backend requires a Python virtual environment to manage its dependencies (`FastAPI`, `uvicorn`, `ChromaDB`, `reportlab`, etc.).

```bash
cd backend

# 1. Create a virtual environment (only needed once)
python -m venv .venv

# 2. Activate the virtual environment
# On Windows (PowerShell):
.\.venv\Scripts\Activate.ps1
# On Mac/Linux:
source .venv/bin/activate

# 3. Install dependencies (only needed once)
pip install -r requirements.txt

# 4. Start the backend server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### 2. Setting Up the Database (Manual Ingest)
If the ChromaDB database is empty (e.g. `backend/chroma_db` was deleted), the backend will automatically start an initial ingest in the background when you start it. 

However, you can **manually trigger the ingest** at any time. This forces the server to scrape jobs, summarize them, and add them to ChromaDB.
You can trigger it in two ways:
1. **Via Swagger UI (Easiest)**: Open your browser to http://localhost:8000/docs, find the `POST /api/jobs/ingest` endpoint, click "Try it out", and click "Execute".
2. **Via cURL (Terminal)**:
   ```bash
   curl -X POST "http://localhost:8000/api/jobs/ingest" -H "Content-Type: application/json" -d "{}"
   ```
*(Note: The ingest runs in the background. You can check the server terminal logs to see its progress).*

### 3. Starting the Frontend (Flutter)
If you encountered errors running on the Android Emulator, they were likely due to the frontend not being able to connect to the backend (causing network runtime errors) or missing assets.

```bash
# 1. Ensure your backend is running first!
# 2. Check backend/.env and make sure you have your API keys.
# 3. Start the Android Emulator from Android Studio.
# 4. Run the Flutter app:
flutter run
```
*Note: The frontend `.env` is configured to `API_URL=http://10.0.2.2:8000/api/generate-cv`, which is the correct alias for the Android Emulator to connect to `localhost` on your PC.*

- Monitor Groq rate limits — if batching at 4 jobs/call hits limits, reduce `BATCH_SIZE` in `worker.py`.
