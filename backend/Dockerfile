FROM python:3.11-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    HF_HOME=/root/.cache/huggingface

# Install system dependencies for headless browsers (Firefox/Camoufox)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnss3 \
    libgbm1 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libasound2 \
    libpangocairo-1.0-0 \
    libpango-1.0-0 \
    libcairo2 \
    libdbus-glib-1-2 \
    libdbus-1-3 \
    libgtk-3-0 \
    libxrender1 \
    libxt6 \
    libxtst6 \
    libxshmfence1 \
    libx11-xcb1 \
    libegl1 \
    libgl1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

# Automated fallback to ensure all required browser dependencies are installed
# RUN python -m playwright install-deps

# Pre-download the embedding model for offline availability
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# Fetch Camoufox browser binaries and bake them into the container image layer
RUN python -m camoufox fetch

# Copy the rest of the application code
COPY . .

# Expose the API port
EXPOSE 8000

# Command to run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
