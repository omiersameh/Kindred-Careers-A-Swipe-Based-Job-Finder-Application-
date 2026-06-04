# Handover Guide — Kindred Careers Setup & Architecture

Welcome to **Kindred Careers**, an AI-powered, swipe-based job matching application built using a **Flutter** mobile client and a **FastAPI / ChromaDB RAG** backend.

This document serves as a guide for setting up and running the application, outlining our recent backend containerization and browser scraper migration.

---

## 1. System Architecture

The project consists of two core components:
1. **Frontend (Flutter)**: A mobile client that displays a card-swipe job feed, interactive questionnaire wizard, profile management, and customized AI CV previews.
2. **Backend (FastAPI)**: A Python service that serves job recommendation feeds, runs tailorable PDF resume builders, manages a RAG pipeline (ChromaDB + sentence-transformers), and hosts a recurring background scraping worker.

```
+------------------+                   +--------------------+
|  Flutter Mobile  | <=== (REST) ====> |  FastAPI Backend   |
|     Frontend     |                   |  (Uvicorn Server)  |
+------------------+                   +--------------------+
                                                 || (Embed / Store)
                                                 \/
                                       +--------------------+
                                       | Chroma Vector DB   |
                                       |  (Persistent Vol)  |
                                       +--------------------+
                                                 /\
                                                 || (Background Task)
                                       +--------------------+
                                       | Camoufox Scraper   |
                                       |  & Groq Ingestor   |
                                       +--------------------+
                                                 || (Stealth HTTP)
                                                 \/
                                       +--------------------+
                                       |     Wuzzuf.net     |
                                       +--------------------+
```

---

## 2. Backend Setup & Run Guide

The backend requires python 3.11+. Follow either the local virtual environment guide or the Docker Compose guide.

### Prerequisites (Configuration)
Create a `.env` file in the `backend/` directory based on the following template (do NOT commit this file to git):
```env
# Groq API Key — used for Wuzzuf extraction and summarization
GROQ_API_KEY=gsk_your_key_here

# OpenRouter API Key — used for tailoring CVs
CV_OPENROUTER_API_KEY=sk-or-your_key_here

# Models
SUMMARIZER_MODEL=llama-3.1-8b-instant
CV_MODEL=llama-3.3-70b-versatile

# Chroma Database path
CHROMA_PATH=./chroma_db
EMBED_MODEL=sentence-transformers/all-MiniLM-L6-v2
```

### Option A: Running with Docker Compose (Recommended)
We have containerized the backend using Docker and mapped database files persistently. Docker Desktop must be running.

```bash
# 1. Build the backend image (automatically bakes in embedding models & headless browser files)
docker compose build

# 2. Run the container in the background
docker compose up -d

# 3. View running logs
docker compose logs -f
```
- **Volume Mount**: The database is stored persistently in `./backend/chroma_db/` on your host machine and mounted to `/app/chroma_db/` inside the container. Restarts and rebuilds will NOT wipe your ingested jobs.
- **Shared Memory (SHM)**: The docker-compose utilizes `shm_size: '2gb'` to prevent headless browser subprocesses from crashing due to default Docker memory constraints.

### Option B: Running Locally (Without Docker)
Make sure you install the Playwright dependencies on your local machine:

```bash
cd backend

# 1. Initialize and activate virtual environment
python -m venv .venv
# On Windows (PowerShell):
.\.venv\Scripts\Activate.ps1
# On Linux/macOS:
source .venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Download Camoufox browser binaries
python -m camoufox fetch

# 4. Start the FastAPI server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

---

## 3. Background Ingestion & Scraper Pipeline

We migrated our old multi-source scraper to a unified, asynchronous architecture using **Camoufox** (a stealth anti-detect browser based on Firefox) and **Groq (`llama-3.1-8b-instant`)**.

### Scraper Engine Details (`worker.py`):
1. **Dynamic Parameterization**: Scrapes jobs targeting **Wuzzuf** by encoding search query terms: `https://wuzzuf.net/search/jobs?q={career_field}` based on the user's career field preferences.
2. **Token & Context Optimization**: Instead of sending heavy raw HTML to Groq, the scraper uses a Playwright CSS locator (`div.css-1gatmva` or fallbacks) to isolate job listing cards and grabs only their `inner_text()`. This removes all HTML markup overhead, reducing input tokens by **90%** and preventing LLM context limit issues.
3. **Structured Extraction**: The clean text is sent to Groq which extracts and formats the listings directly into schema-compliant job profiles (JSON objects containing titles, skills, salary, logo emojis, and AI summary bullets).
4. **Vector Store Ingestion**: Embedding models convert job descriptions into vectors which are upserted into ChromaDB using stable deterministic IDs (preventing duplicates).

### Mock Job Fallbacks & Onboarding Security:
To ensure onboarding is never blocked if ChromaDB is empty on a fresh setup:
- `/api/jobs/feed` will instantly return high-quality mock listings from `services/mock_jobs.py` scored and sorted dynamically according to the user's specific profile interests.
- If all database listings are swiped, the feed relaxes `exclude_ids` constraints to serve existing database jobs as a backup, keeping the swiping feed alive.

---

## 4. Frontend Setup (Flutter)

1. Make sure Flutter is installed and configured on your machine.
2. Setup your frontend environment variables in `.env` in the root folder:
   - **Android Emulator**: Set `API_URL=http://10.0.2.2:8000` (which is the emulator loopback alias to localhost on the host PC).
   - **Physical Device**: Set `API_URL=http://<YOUR_PC_IP>:8000`. Make sure the mobile device and PC are connected to the same Wi-Fi network.
3. Run the Flutter app:
   ```bash
   flutter run
   ```
