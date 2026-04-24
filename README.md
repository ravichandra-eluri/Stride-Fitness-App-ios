# Stride — iOS App

A personal fitness and nutrition app built with SwiftUI. Combines AI-powered meal planning, daily food logging, weight tracking, and a coach that adjusts its message based on how you're doing.

## What it does

- **Onboarding** — 5-step setup that generates a personalized calorie target, macro split, and goal timeline using Claude
- **Daily dashboard** — calorie ring, macro breakdown, today's food entries, streak badge, and a daily coach message
- **Meal planning** — full week of AI-generated meals with one-tap swaps (similar calories, high protein, or quick prep)
- **Food logging** — manual entry, barcode scan (Open Food Facts), or photo-based logging where Claude estimates the calories from an image
- **Progress** — weekly summaries, weight history chart, Apple Health integration (steps, active calories, recent workouts)
- **Coach tab** — daily motivational tip and priority meal focus based on yesterday's performance
- **Settings** — edit profile (weight, goals, activity level, diet preferences), notification schedule, privacy policy, delete account

## Tech

- Swift + SwiftUI, MVVM with `@Observable`
- `async/await` throughout, no Combine
- `URLSession` actor-based API client with automatic token refresh
- Sign in with Apple + Bearer JWT
- HealthKit for activity data
- `UNUserNotificationCenter` for local reminders
- AVFoundation for barcode scanning
- Keychain for token storage, UserDefaults for notification preferences

Minimum target: **iOS 17**

## Project structure

```
Core/
  Models/Models.swift                      # All data models and API response types
  Network/APIClient.swift                  # Shared HTTP client with auth and token refresh
  Health/HealthKitManager.swift            # Steps, calories, workouts from Apple Health
  Storage/Keychain.swift                   # Secure token storage

Features/
  Auth/                                    # Sign in with Apple flow
  Onboarding/                              # 5-step setup with AI plan generation
  Dashboard/DashboardView.swift            # Home tab
  Meals/MealPlanView.swift                 # Meal plan + swap UI
  Log/LogCoachProgressViews.swift          # Food log, coach, and progress tabs
  Settings/SettingsNotificationsViews.swift  # Edit profile and notifications

Shared/
  Components/Components.swift              # WCard, WButton, WChip, WCalorieRing, etc.
  Theme/Theme.swift                        # Colors, typography, spacing, radius tokens
```

## Getting started

You need Xcode 15+, an Apple Developer account (for Sign in with Apple), and access to a running backend instance.

```bash
git clone https://github.com/ravichandra-eluri/Stride-Fitness-App-ios
open Stride/Stride.xcodeproj
```

The backend URL is configured in `Core/Network/APIClient.swift`. It falls back to the production Cloud Run URL if no `STRIDE_API_BASE_URL` key is set in Info.plist, so it works out of the box against prod.

For Sign in with Apple, make sure the bundle ID and team ID in Signing & Capabilities match your Apple Developer account.

## Backend

The REST API lives at [Stride-Fitness-App-backend](https://github.com/ravichandra-eluri/Stride-Fitness-App-backend) — Go + Postgres on GCP Cloud Run.

## Design system

Centralized in `Shared/Theme/Theme.swift`. Brand green `#1D9E75`, brand purple `#7F77DD`. Six text styles, spacing scale from 4pt to 48pt, two corner radius values. Dark mode only for v1.
