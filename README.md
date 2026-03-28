# ARDOR

Fetches tech newsletters from Gmail every morning, processes them with Claude AI, and presents audio + structured learning content in a mobile app.

## What it does

1. Pulls unread TLDR, TLDR AI, and DailyFin newsletters from Gmail
2. Sends each article to Claude for summary, learning points, and a conversation tip
3. Generates audio with Google Cloud TTS
4. Stores everything in Supabase (7-day retention, auto-deleted)
5. Serves it to the mobile app — home screen with LISTEN and READ buttons

## Run locally

```bash
# Backend
cd backend
cp .env.example .env      # fill in your keys
source venv/bin/activate
pip install -r requirements.txt
python test_gmail.py      # first-time OAuth — opens a browser window
uvicorn main:app --reload # starts on http://localhost:8000

# Mobile (separate terminal)
cd mobile
cp .env.example .env      # fill in API URL + Supabase keys
npm install
npx expo start            # scan QR with Expo Go
```

## Trigger pipeline manually

```bash
curl -X POST http://localhost:8000/api/fetch-now
```

## Environment variables

### backend/.env
| Variable | What it is |
|---|---|
| `ANTHROPIC_API_KEY` | From console.anthropic.com |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_KEY` | Supabase anon/publishable key |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to TTS service account JSON |
| `GMAIL_CREDENTIALS_FILE` | Path to Gmail OAuth client JSON |
| `PIPELINE_HOUR` / `PIPELINE_MINUTE` | UTC time for daily run (10:00 UTC = 7am Brasília) |

### mobile/.env
| Variable | What it is |
|---|---|
| `EXPO_PUBLIC_API_URL` | Backend URL (localhost:8000 or Render URL) |
| `EXPO_PUBLIC_SUPABASE_URL` | Supabase project URL |
| `EXPO_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon key |

## Deploy

**Backend → Render:**
- Build: `pip install -r requirements.txt`
- Start: `uvicorn main:app --host 0.0.0.0 --port $PORT`
- Set all env vars in Render dashboard
- Upload `credentials.json` and `tts-service-account.json` as Render Secret Files

**Mobile → Play Store:**
```bash
cd mobile
npx eas build --platform android --profile production
```

## Tech Stack
Python + FastAPI · Expo + TypeScript · Supabase · Claude API · Google Cloud TTS
