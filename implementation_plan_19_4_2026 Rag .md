# Kindred Careers — Stabilization & RAG Revamp Plan

Fix critical bugs in auth, UI, and backend connectivity, then design a next-gen RAG pipeline.

---

## Phase 1: Firebase Auth & Logout Fix

### Root Cause Analysis

The **logout button** in `profile_screen.dart` calls `AuthService.signOut()` but does **not** navigate the user back to the sign-in screen. The `_AuthGate` in `main.dart` uses a `StreamBuilder` on `authStateChanges()`, which *should* auto-route — but the `MainShell` is inside an `IndexedStack`, not inside the `StreamBuilder` subtree. After sign-out, the stream fires `null`, but the user is left on a stale screen because `ProfileScreen` doesn't react to the auth state change.

**Auth persistence** is actually working correctly via Firebase's default behavior (persists tokens to disk). The *symptom* of "forgetting accounts" is caused by:
1. `UserProfileService` initializes with `FirebaseAuth.instance.currentUser?.uid` at provider creation time (line 14), which can be `null` during the brief Firebase SDK boot window.
2. On app restart, if the profile loads before `authStateChanges` emits the user, a `guest` profile is loaded instead of the real one.

### Proposed Changes

#### [MODIFY] [profile_screen.dart](file:///e:/Graduation%20Project/kindred_careers/lib/screens/profile_screen.dart)

- **Logout button**: After `AuthService.signOut()`, navigate to root and clear the navigation stack so the `_AuthGate` `StreamBuilder` takes over:
  ```dart
  onTap: () async {
    await AuthService.signOut();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  },
  ```

#### [MODIFY] [main.dart](file:///e:/Graduation%20Project/kindred_careers/lib/main.dart)

- Add a named route `'/'` pointing to `_AuthGate` so `pushNamedAndRemoveUntil('/')` works.
- Ensure `_PostAuthRouter` re-runs `loadProfile()` every time it is built (handles re-login with a different account cleanly).

#### [MODIFY] [user_profile_service.dart](file:///e:/Graduation%20Project/kindred_careers/lib/services/user_profile_service.dart)

- Remove the eager UID read on line 14. Initialize with a truly empty default profile. The actual profile load happens in `_PostAuthRouter._check()` via `loadProfile()`, which already correctly reads the UID.

---

## Phase 2: UI / UX Bug Fixes

### 2A — Job Cards Disappearing

**Root Cause**: In `home_screen.dart` line 107-111, after a swipe, a `Future.microtask` removes the swiped job from `_jobs`. But `CardSwiper` internally tracks its own index — removing the item mid-animation causes the *next* card to also vanish because the list length changes under the swiper.

**Fix**: Stop manually removing jobs from `_jobs` after swipe. Let `CardSwiper` manage its own internal index. The swipe history (`_seenIds`) already prevents the same job from reappearing on refetch.

#### [MODIFY] [home_screen.dart](file:///e:/Graduation%20Project/kindred_careers/lib/screens/home_screen.dart)

- Remove the `Future.microtask(() { setState(() => _jobs.removeAt(previousIndex)); })` block (lines 107-111).
- Update the `_jobs.length` display to account for already-swiped cards by subtracting the count from `_swipeHistory`.

### 2B — Check (✓) and X (✗) Buttons Not Working Correctly

**Root Cause**: The `Pass` and `Apply` buttons inside `JobCard._buildDecideBanner()` call `widget.onSwipeLeft` / `widget.onSwipeRight`, which trigger `_swiperController.swipe()` in `HomeScreen`. This *does* work, but:
1. The buttons are wrapped in `AnimatedOpacity` with `_atBottom ? 1.0 : 0.45` — users may not scroll to the bottom, so the buttons appear dimmed and feel unresponsive.
2. The `GestureDetector` on the buttons has no visual tap feedback.

**Fix**:
- Always make the buttons fully opaque and tappable (remove the scroll-gated opacity).
- Add `InkWell`-style ripple feedback or a scale animation on tap.

#### [MODIFY] [job_card.dart](file:///e:/Graduation%20Project/kindred_careers/lib/widgets/job_card.dart)

- Change `AnimatedOpacity` opacity from `_atBottom ? 1.0 : 0.45` to always `1.0`.
- Optionally add a brief scale animation on tap for better feedback.

### 2C — CV Generation API Call Failing Silently

**Root Cause**: The `CVGenerationService._apiUrl` reads from the **frontend** `.env` which has `API_URL=http://127.0.0.1:8000/api/generate-cv`. But the `JobRecommendationService` uses `http://192.168.100.12:8000` (the PC's LAN IP). The emulator cannot reach `127.0.0.1` — that points to the emulator itself, not the host PC.

**Fix**: Change the frontend `.env` `API_URL` to use the same LAN IP (`192.168.100.12`) or `10.0.2.2` (Android emulator's alias for host loopback). Also add a timeout and proper error snackbar.

#### [MODIFY] [.env (frontend)](file:///e:/Graduation%20Project/kindred_careers/.env)

```
API_URL=http://192.168.100.12:8000/api/generate-cv
```

#### [MODIFY] [cv_generation_service.dart](file:///e:/Graduation%20Project/kindred_careers/lib/services/cv_generation_service.dart)

- Add a `.timeout(Duration(seconds: 30))` to the HTTP call.
- Show a user-friendly error snackbar on failure instead of rethrowing silently.

---

## Phase 3: RAG System Revamp Plan (Design Only — Execute Later)

> [!IMPORTANT]  
> This phase is a **design document only**. No code changes will be made until you explicitly approve execution.

### Current Architecture Problems

| Problem | Impact |
|---|---|
| **Synchronous scrape+summarize on startup** | Server blocks for 10+ minutes processing 60-100 jobs at 4.5s each |
| **Every scraped job goes through LLM** | Wastes Groq tokens on irrelevant listings |
| **No pre-stored job cache** | Users see an empty screen until the pipeline finishes |
| **`nomic-embed-text-v1.5` loads into RAM** | ~800MB model load delays first response |
| **6 sources scraped sequentially** | Network-bound; could be 3× faster with parallelization |

### Proposed New Architecture

```
┌──────────────────────────────────────────────────────┐
│                  TIER 1: FAST PATH                    │
│  (User opens app → sees jobs in < 2 seconds)          │
│                                                       │
│  ChromaDB (pre-populated) → Embed profile → Search    │
│  ↓                                                    │
│  Return top-N stored jobs immediately                 │
└──────────────────────────────────────────────────────┘
         ↓ (background, non-blocking)
┌──────────────────────────────────────────────────────┐
│           TIER 2: SMART BACKGROUND REFRESH            │
│                                                       │
│  1. Scrape all 6 sources in parallel (asyncio.gather) │
│  2. Keyword-filter BEFORE LLM (drop irrelevant jobs)  │
│  3. Batch summarize: group 5 jobs per LLM call        │
│  4. Embed + upsert into ChromaDB                      │
│  5. Purge stale jobs (>14 days old)                    │
└──────────────────────────────────────────────────────┘
```

### Key Design Decisions

#### 1. Pre-filter Before LLM (85% cost reduction)
Instead of summarizing every scraped job, apply a **keyword relevance score** first:
- Extract title + tags + first 200 chars of description
- Score against user's `skills + careerFields`
- Only send jobs with score > threshold to the LLM
- This cuts LLM calls from ~80 to ~12 per run

#### 2. Batch Summarization (3× throughput)
Group 3-5 job descriptions into a single LLM prompt:
```
Summarize these 5 job listings. Return a JSON array of 5 objects...
```
This uses Groq's 128K context window efficiently and reduces rate-limit pressure.

#### 3. Lighter Embedding Model
Replace `nomic-embed-text-v1.5` (768d, ~800MB) with `all-MiniLM-L6-v2` (384d, ~90MB):
- 8× smaller model, loads in <2s
- Comparable retrieval quality for short-text job matching
- ChromaDB supports dimension change on collection recreation

#### 4. Scheduled Refresh + Event-Driven Ingest
- **Background cron**: Every 60 min (not 30) — reduces API load
- **On-demand**: When user completes questionnaire or updates profile → trigger targeted scrape
- **Startup**: Skip scrape entirely; serve from existing ChromaDB data

#### 5. Cost-Effective Summarizer
Switch from `llama-3.3-70b-versatile` to `llama-3.1-8b-instant` for summarization:
- 10× faster inference on Groq
- Adequate quality for structured JSON extraction
- 14,400 RPM free tier (vs 30 RPM for 70B)
- Fall back to 70B only for CV generation (where quality matters more)

### Migration Path

1. Seed ChromaDB with current jobs (already done — DB has existing jobs)
2. Update `worker.py` to implement Tier 2 (pre-filter + batch)
3. Swap embedding model + recreate collection
4. Update `main.py` startup to skip blocking scrape
5. Test end-to-end with emulator

---

## Verification Plan

### Automated Tests
1. `flutter build apk --debug` — ensure no compile errors
2. Launch on emulator → verify sign-in, logout, re-login cycle
3. Verify job cards persist through swipes (no disappearing)
4. Verify ✓/✗ buttons trigger swipe programmatically
5. Verify CV generation succeeds (check backend logs)

### Manual Verification
1. Cold-start app → confirm jobs load from ChromaDB (no empty screen)
2. Tap logout → confirm navigation to sign-in screen
3. Re-login with same account → confirm profile data persisted
4. Swipe right on a job → confirm CV preview dialog opens with AI-generated content
5. Swipe through 5+ jobs → confirm no cards vanish or duplicate
