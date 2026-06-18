# 🚨 STRICT CONSTRAINTS: Quota-Safe Docker Architecture

**CONTEXT FOR THE AGENT:** 
The user is developing in an environment with strict, limited internet quotas (cellular/metered connection). Blindly rewriting configurations, breaking caches, or pulling heavy frameworks costs real money and massive bandwidth. You must optimize for zero-network-overhead and maximum layer caching.

---

## 🚫 1. Absolute Red Lines (Do NOT Touch)
* **No Dependency Modifications:** Under no circumstances are you allowed to modify `requirements.txt` or change package versions unless the user explicitly types: *"You have permission to change dependencies."*
* **No GPU/CUDA Packages:** Never introduce standard GPU-enabled machine learning frameworks. If `torch` or any model runtime is mentioned, it **must** strictly point to the lightweight CPU wheels.

---

## 📦 2. Strict Layer Caching Rules
When writing or updating the `Dockerfile`, you must preserve the layer execution order exactly to protect the local cache:
1. **System Libraries (`apt-get`)** must stay grouped at the very top.
2. **Dependency Installation (`pip install`)** must happen immediately after, using the local pip cache directory.
3. **Application Code (`COPY . .`)** must happen at the very end.
*Reasoning: Changing a line above the code COPY breaks the cache and forces a full network re-download. Keep code separate from environment building.*

---

## 🛑 3. Exclusion Architecture (`.dockerignore`)
Ensure that the build never attempts to copy heavy, locally generated assets. The `.dockerignore` file must always actively block:
* `.venv/` and `venv/` (Local virtual environments)
* `__pycache__/` (Python compiled bytecode)
* `chroma_db/` (Local vector database states)
* Local log files, cached `.whl` files, or temporary testing scripts.

---

## 🛠️ How to Respond to Requests
When asked to modify the backend infrastructure, Docker setup, or worker processes:
1. **Verify compliance:** Double-check that your proposed solution changes *only* the specific application layer required.
2. **Acknowledge the budget:** Explicitly confirm in your response: *"This modification uses 0B of external network quota and relies entirely on your local Docker cache."*