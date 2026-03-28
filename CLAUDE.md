# ARDOR — AI-Powered Tech News Digest

## What is this?
A mobile app (Android/Play Store) that fetches tech newsletters from Gmail, summarizes them with Claude AI, and lets you either LISTEN or READ today's news. Dead simple.

## Tech Stack
- **Backend:** Python 3.12+ with FastAPI (in `backend/`)
- **Mobile App:** Expo (React Native) with TypeScript (in `mobile/`)
- **Database:** Supabase (PostgreSQL)
- **APIs:** Gmail API, Claude API (Anthropic), Google Cloud TTS
- **Hosting:** Backend on Render, Mobile via Expo EAS Build

## Project Structure
```
ardor/
├── backend/
│   ├── main.py              # FastAPI entry point + routes
│   ├── gmail_fetcher.py     # Fetch emails from Gmail API
│   ├── article_processor.py # Process articles with Claude API
│   ├── tts_generator.py     # Generate audio with Google Cloud TTS
│   ├── database.py          # Supabase client + queries
│   ├── scheduler.py         # APScheduler for daily fetch + cleanup
│   ├── requirements.txt
│   ├── credentials.json     # Gmail OAuth (DO NOT commit to git)
│   ├── tts-service-account.json  # TTS auth (DO NOT commit to git)
│   └── .env.example
├── mobile/
│   ├── app/                 # Expo Router screens
│   ├── components/          # Reusable UI components
│   ├── lib/                 # Supabase client, API helpers
│   ├── package.json
│   └── app.json
├── logo/                    # App logo files (use for colors + splash)
├── CLAUDE.md
└── README.md
```

## Coding Rules
1. **SIMPLE over clever.** Flat file structure, no unnecessary abstractions.
2. **One file = one job.** Each file does ONE thing. Name says what it does.
3. **Comments explain WHY, not WHAT.** The code should be readable on its own.
4. **No over-engineering.** No design patterns, no factory classes, no dependency injection. Just functions that do things.
5. **Environment variables** for all secrets. Never hardcode API keys.
6. **Add credentials.json and tts-service-account.json to .gitignore immediately.**

## Key Commands
- **Backend:** `cd backend && uvicorn main:app --reload`
- **Mobile:** `cd mobile && npx expo start`
- **Install backend deps:** `cd backend && pip install -r requirements.txt`
- **Install mobile deps:** `cd mobile && npm install`

## Data Flow
```
Gmail → backend (fetch) → Claude API (summarize) → Supabase (store) → mobile app (display)
                                                                    → TTS audio (listen)
```

## Newsletter Sources
- TLDR (tech/startups) — English
- TLDR AI (AI/ML) — English
- DailyFin (finance) — Portuguese

## App Design
The app has TWO main actions on the home screen:
1. 🎧 LISTEN — Plays all of today's news as audio (one after another)
2. 📰 READ — Opens a scrollable list of today's article summaries

That's it. No tabs, no settings screens, no bookmarks. Just open → listen or read → done.

## Data Retention
- Only show TODAY's articles on the home screen
- Keep articles for 7 days in the database
- Auto-delete articles older than 7 days (daily cleanup job)

## Database Tables (Supabase)
- `articles`: id, title, source, summary, learning_points (jsonb), conversation_tip, audio_url, tags (text[]), published_at (date), created_at (timestamptz)

## Supabase Config
- URL: https://boinfoshcrxqixluhazd.supabase.co
- Storage bucket: "audio" (public)
