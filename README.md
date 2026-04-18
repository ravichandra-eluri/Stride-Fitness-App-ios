# Stride Fitness — iOS App

A personalized fitness and nutrition iOS app that combines AI-powered weight management, weekly meal planning, daily food logging, and coaching into a single streamlined experience.

---

## Features

- **AI Weight Loss Planning** — Onboarding generates a personalized calorie target, macro split, and goal timeline
- **Weekly Meal Plans** — Browse a full week of meals with one-tap swaps (similar calories, high protein, quick prep)
- **Food Logging** — Manual entry, barcode scan, and photo-based logging (Claude Vision API)
- **Daily Dashboard** — Calorie ring, macro breakdown, today's meals, and streak badge
- **AI Coach** — Daily motivational tips and priority meal focus
- **Progress Tracking** — Weekly summaries, weight history chart, and weight logging
- **Sign in with Apple** — Secure, private authentication with token refresh

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift |
| UI | SwiftUI |
| Architecture | MVVM + async/await |
| Auth | Sign in with Apple + Bearer tokens |
| Storage | Keychain (tokens), UserDefaults (flags) |
| Networking | URLSession with automatic token refresh |
| Backend | REST API on Google Cloud Run |

**Minimum iOS target:** iOS 15+

---

## Project Structure

```
Stride-Fitness-ios/
├── Core/
│   ├── Models/Models.swift        # All data models and API response types
│   ├── Network/APIClient.swift    # Actor-based HTTP client with auth and token refresh
│   └── Storage/Keychain.swift    # Secure token storage
├── Features/
│   ├── Auth/                      # Sign in with Apple flow
│   ├── Onboarding/               # 5-step user setup → AI plan generation
│   ├── Dashboard/                 # Home tab: daily summary, streak, profile
│   ├── Meals/                     # Weekly meal plan + meal swap UI
│   └── Log/                       # Food logging, coach messages, progress
├── Shared/
│   ├── Components/Components.swift  # Reusable WCard, WButton, WChip, WCalorieRing, etc.
│   └── Theme/Theme.swift           # Design tokens: colors, typography, spacing, radius
└── StrideApp.swift               # App entry point, root navigation, AppState
```

---

## Getting Started

### Prerequisites

- Xcode 15+
- iOS 15+ simulator or physical device
- Apple Developer account (for Sign in with Apple)

### Setup

1. Clone the repository:
   ```bash
   git clone <repo-url>
   cd Stride-Fitness-ios
   ```

2. Open the project in Xcode:
   ```bash
   open Stride-Fitness-ios.xcodeproj
   ```

3. Configure the backend URL in `Core/Network/APIClient.swift`:
   ```swift
   private let baseURL = "https://your-cloudrun-url.run.app"
   ```

4. Configure Sign in with Apple in your Xcode project's **Signing & Capabilities** tab.

5. Build and run on your target device or simulator.

---

## API Overview

The app communicates with a REST backend(Stride-Fitness-App) deployed on Google Cloud Run:

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/api/auth/apple` | Sign in with Apple |
| POST | `/api/auth/refresh` | Refresh access token |
| POST | `/api/onboarding/complete` | Submit onboarding → get AI plan |
| GET/PATCH | `/api/profile` | Fetch or update user profile |
| GET | `/api/meals/plan` | Fetch weekly meal plan |
| POST | `/api/meals/swap` | Swap a meal with an AI alternative |
| POST | `/api/log/food` | Log a food entry |
| GET | `/api/log/today` | Fetch today's food log |
| POST | `/api/log/weight` | Log a weight entry |
| GET | `/api/progress/weekly` | Weekly summary stats |
| GET | `/api/progress/weights` | Weight history |
| GET | `/api/coach/today` | Daily coach message |

---

## Design System

The app uses centralized design tokens defined in `Shared/Theme/Theme.swift`:

- **Brand colors:** Green `#1D9E75`, Purple `#7F77DD`
- **Typography:** 6 text styles from `titleLg` to `bodySm`
- **Spacing scale:** `xs` (4pt) → `xxl` (48pt)
- **Corner radius:** `sm` (8pt) → `lg` (16pt)

The app is locked to **light mode** for v1.

---

## Roadmap

- [ ] Wire barcode scanning (AVFoundation)
- [ ] Enable photo-based food logging (Claude Vision API)
- [ ] Replace placeholder weight chart with Swift Charts (iOS 16+)
- [ ] Push notification permissions and content
- [ ] Connect production Cloud Run backend URL

---

## Related

- [stride-backend](../stride-backend) — Cloud Run backend powering this app
