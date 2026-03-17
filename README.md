# 💼 Kindred Careers

> **AI-Powered Swipe-Based Job Matching App**  
> A Flutter mobile application that reimagines job hunting through personalized matching, swipe gestures, and automated CV generation.

---

## 📋 Table of Contents
1. [Overview](#overview)
2. [Features](#features)
3. [Architecture](#architecture)
4. [OOP Design](#oop-design)
5. [AI & ML Simulation](#ai--ml-simulation)
6. [Project Structure](#project-structure)
7. [Getting Started](#getting-started)
8. [Dependencies](#dependencies)
9. [Screens](#screens)
10. [Connecting the Real Backend](#connecting-the-real-backend)

---

## Overview

**Kindred Careers** addresses the core pain points of traditional job search platforms:

| Problem | Our Solution |
|---------|-------------|
| One-size-fits-all profiles | Multi-path career field management |
| Endless scrolling through irrelevant jobs | Swipe interface — one card at a time |
| Generic CVs sent to every employer | AI generates a unique CV per job |
| High cognitive load applications | One-tap apply with tailored documents |

The app is structured around three screens connected via a bottom navigation bar.

---

## Features

### 🃏 Swipe-Based Job Discovery (Home Screen)
- Job cards are ranked by **AI match score** (highest first)
- **Swipe Right** → triggers CV generation → shows tailored CV → confirm to apply
- **Swipe Left** → dismisses job, LSTM engine records the signal
- Manual **Pass / Like** buttons also available
- Real-time **APPLY / PASS** stamp overlays during swipe

### 👤 Profile Management (Profile Screen)
- Edit name, email, phone, bio, location
- Add/remove **Skills** (chip-based)
- Add/remove **Career Fields** (e.g. Software Engineering + Digital Marketing)
- Work preference selector: Remote / Hybrid / Onsite
- Add full **Work Experience** and **Education** entries
- Changes instantly feed the recommendation engine

### ❤️ Matched Jobs (Matches Screen)
- Lists all jobs the user swiped right on
- Shows **match score** per job
- **View CV** → opens the tailored CV with edit/feedback option
- **Apply** → confirm application submission
- **Remove** → remove from matched list
- Live **badge count** on the Matches tab icon

### 🤖 CV Generation & Feedback Loop
- After each swipe right, a tailored CV is **automatically generated**
- CV sections: Summary, Skills, Relevant Experience, Education, Achievements
- User can type feedback → request **regeneration** (simulates LLM prompt chaining)
- CV version history tracked (`v1`, `v2`, …)

---

## Architecture

```
kindred_careers/
└── lib/
    ├── main.dart              # App entry point, providers, theme, nav shell
    ├── models/                # OOP data models (pure Dart classes)
    │   ├── user_profile.dart  # UserProfile, Experience, Education
    │   ├── job.dart           # Job (with computed match color/percent)
    │   ├── swipe_action.dart  # SwipeAction (LSTM behavioral data)
    │   └── cv.dart            # CV, CVContent, CVExperience, CVFeedback
    ├── services/              # Business logic + state management
    │   ├── user_profile_service.dart    # ChangeNotifier: profile CRUD
    │   ├── job_recommendation_service.dart  # RAG/LSTM matching engine
    │   └── cv_generation_service.dart   # LLM CV generation + AppState
    ├── screens/               # The 3 main pages
    │   ├── profile_screen.dart
    │   ├── home_screen.dart
    │   └── matched_jobs_screen.dart
    └── widgets/               # Reusable UI components
        ├── job_card.dart          # Swipeable card UI
        └── cv_preview_dialog.dart # CV bottom sheet with feedback
```

### State Management
- **Provider** (ChangeNotifier pattern)
- `UserProfileService` → user profile data
- `AppState` → matched jobs and generated CVs
- `IndexedStack` in `MainShell` → preserves screen state across tab switches

---

## OOP Design

All core data types are implemented as **Dart classes** following OOP principles:

### Inheritance Hierarchy
```
UserProfile
  ├── List<Experience>      (composition)
  └── List<Education>       (composition)

CV
  ├── CVContent             (composition)
  │   └── List<CVExperience>
  └── List<CVFeedback>      (composition)

SwipeAction
  └── SwipeDirection (enum)
```

### Key OOP Concepts Used
| Concept | Where Used |
|---------|-----------|
| **Encapsulation** | Private `_profile`, `_jobs`, `_swipeHistory` in services |
| **Abstraction** | Services hide LLM/LSTM logic behind simple method calls |
| **Composition** | `UserProfile` contains `Experience[]`, `Education[]` |
| **Computed Properties** | `Job.matchPercent`, `Job.salaryRange`, `Job.matchColorValue` |
| **ChangeNotifier** | `UserProfileService`, `AppState` notify UI on state change |
| **copyWith pattern** | `UserProfile.copyWith()` for immutable updates |

---

## AI & ML Simulation

The app simulates the full AI pipeline so you can run and demo without a backend:

### Job Recommendation Engine (`JobRecommendationService`)
Simulates the **RAG + LSTM** pipeline:
1. **Keyword extraction** from user profile (`allKeywords` property)
2. **Score computation** — counts overlapping keywords between job and profile
3. **LSTM boost** — industries from the last 5 right-swipes get a +15% boost
4. **Work mode boost** — +5% if job work mode matches user preference
5. Jobs returned **sorted by score descending** (highest match first)

```dart
// Real backend endpoint this replaces:
// POST /api/recommendations
// Body: { user_profile, swipe_history }
```

### CV Generation Engine (`CVGenerationService`)
Simulates the **LLM pipeline**:
1. **Keyword extraction** from job description and required skills
2. **Experience filtration** — only includes experiences that overlap with job keywords
3. **Skill ranking** — matched skills listed first, then remaining breadth skills
4. **Summary generation** — auto-writes personalized professional summary
5. **Regeneration loop** — incorporates user text feedback and appends an updated summary

```dart
// Real backend endpoint this replaces:
// POST /api/generate-cv
// Body: { user_profile, job_description }
```

---

## Getting Started

### Prerequisites
- Flutter SDK ≥ 3.0.0 (install from https://flutter.dev)
- Android Studio or VS Code with Flutter extension
- A connected device or emulator

### 1. Install Dependencies
```bash
cd "e:\Graduation Project\kindred_careers"
flutter pub get
```

### 2. Run the App
```bash
flutter run
```

### 3. Build for Android
```bash
flutter build apk --release
```

### 4. Build for iOS
```bash
flutter build ipa --release
```

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `provider` | ^6.1.2 | State management (ChangeNotifier) |
| `flutter_card_swiper` | ^7.0.0 | Tinder-style swipe cards |
| `google_fonts` | ^6.2.1 | Inter font family |
| `flutter_animate` | ^4.5.0 | Micro-animations |
| `shared_preferences` | ^2.2.3 | Local storage |
| `uuid` | ^4.4.0 | Unique ID generation |
| `cupertino_icons` | ^1.0.6 | iOS icons |

### Install All Dependencies
```bash
flutter pub get
```

---

## Screens

### Tab 1 — Profile (`/profile`)
- Avatar with initials, editable basic info
- Chip-based skills and career field management
- Work mode preference (Remote / Hybrid / Onsite)
- Add/remove work experience and education entries

### Tab 2 — Discover (`/home`) — ***Default***
- Ranked job card stack (highest match first)
- Drag or tap buttons to swipe
- APPLY / PASS overlays appear during drag
- Triggers CV generation on right swipe

### Tab 3 — Matches (`/matches`)
- Card list of all liked jobs
- Match score badge per job
- View / edit generated CV
- Confirm and submit application

---

## Connecting the Real Backend

This Flutter app is designed to swap the mock services for real Python API calls. Here's the mapping:

| Mock Service | Real API Endpoint | Method |
|-------------|------------------|--------|
| `JobRecommendationService.getRecommendedJobs()` | `/api/recommendations` | `POST` |
| `CVGenerationService.generateCV()` | `/api/generate-cv` | `POST` |
| `CVGenerationService.regenerateWithFeedback()` | `/api/regenerate-cv` | `POST` |
| `AppState.addMatch()` | `/api/matches` | `POST` |

### Example: Replace mock CV generation with real API call
```dart
Future<CV> generateCV({required Job job, required UserProfile profile}) async {
  final response = await http.post(
    Uri.parse('https://your-backend.com/api/generate-cv'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'job_description': job.description,
      'job_skills': job.requiredSkills,
      'user_profile': {
        'skills': profile.skills,
        'career_fields': profile.careerFields,
        'experiences': profile.experiences.map((e) => e.toString()).toList(),
      }
    }),
  );
  // Parse response and build CV object
}
```

---

## Team

Kindred Careers — Graduation Project  
Built with Flutter + Dart • Powered by AI/LLM • Designed for Egypt's ICT market

---

*"Reimagining job hunting — one swipe at a time."*
