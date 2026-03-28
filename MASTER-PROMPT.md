# ARDOR — Final Build Prompt for Claude Code

Read the CLAUDE.md file first. Then build this app step by step.

## WHAT YOU ALREADY HAVE
- Supabase project is ready. URL: `https://boinfoshcrxqixluhazd.supabase.co`. Key: `sb_publishable_y97e58z8VuVOhuYXF9e97g_t4pcjUmO`
- Gmail OAuth credentials are in `backend/credentials.json` (already in the project folder)
- Google Cloud TTS service account key is in `backend/tts-service-account.json` (already in the project folder)
- Anthropic API key will be in the `.env` file
- The app logo is in the `logo/` folder — use its colors for the app theme (extract the main colors from the logo and use them for background, text, and accents)

## CRITICAL RULES

1. **SIMPLE ABOVE ALL.** Every file should be under 150 lines. If it's longer, split it. No design patterns, no abstract classes, no over-engineering.
2. **One file = one job.** The filename tells you what it does.
3. **Comment the WHY.** Add a comment block at the top of every file explaining what it does and why. Comment anything non-obvious inside the code.
4. **Flat structure.** No deeply nested folders. Maximum 2 levels deep.
5. **Working code first.** Get each piece working before making it pretty.
6. **Add `credentials.json` and `tts-service-account.json` to .gitignore IMMEDIATELY.** Never commit secrets.

## THE APP IS DEAD SIMPLE

The mobile app has ONE screen with TWO buttons:
- 🎧 **LISTEN** — Plays today's news as audio. All articles one after another. Simple audio player with play/pause and skip.
- 📰 **READ** — Opens a scrollable list of today's articles. Each article shows: source badge, title, summary, learning points, and a "how to use in conversation" tip.

No tabs. No settings. No bookmarks. No search. Just open the app → pick listen or read → done. The home screen should show the ARDOR logo, today's date, the count of today's articles (e.g. "12 articles today"), and the two big buttons.

## DATA RETENTION
- The home screen only shows TODAY's articles
- The READ screen shows articles grouped by source (TLDR, TLDR AI, DailyFin)
- Articles are kept in the database for 7 days maximum
- A daily cleanup job deletes articles older than 7 days
- Audio files older than 7 days are also deleted from Supabase Storage

## BUILD ORDER

Build in this exact order. After each step, verify it runs without errors.

### Step 1: Project skeleton
- Initialize the monorepo: `backend/` and `mobile/`
- Backend: Create `requirements.txt` with: fastapi, uvicorn, anthropic, google-api-python-client, google-auth-httplib2, google-auth-oauthlib, supabase, apscheduler, python-dotenv, google-cloud-texttospeech
- Mobile: Run `npx create-expo-app@latest mobile --template blank-typescript`, then set up Expo Router
- Create `.env.example` in backend with all needed env vars (with placeholder values and comments):
  ```
  ANTHROPIC_API_KEY=sk-ant-your-key-here
  SUPABASE_URL=https://boinfoshcrxqixluhazd.supabase.co
  SUPABASE_KEY=sb_publishable_y97e58z8VuVOhuYXF9e97g_t4pcjUmO
  GOOGLE_APPLICATION_CREDENTIALS=tts-service-account.json
  ```
- Create `.gitignore` that includes: credentials.json, tts-service-account.json, .env, __pycache__/, node_modules/, .expo/
- Create `main.py` with a health check: `GET /health` returns `{"status": "ok"}`
- Test: `cd backend && uvicorn main:app --reload` → health check works

### Step 2: Database setup
- Create `backend/database.py` with Supabase client
- At the top of the file, include the FULL SQL as comments that I need to run in Supabase SQL Editor to create the tables:
  - `articles` table: id (uuid default gen_random_uuid()), title (text), source (text), original_url (text), summary (text), learning_points (jsonb), conversation_tip (text), tags (text[]), audio_url (text nullable), published_at (date), created_at (timestamptz default now())
  - Enable Row Level Security on articles with a policy that allows public read access
  - Create the "audio" storage bucket (public)
- Write functions: `save_article(data)`, `get_todays_articles()`, `get_articles_by_date(date)`, `delete_old_articles(days=7)`
- The `delete_old_articles` function also deletes audio files from the storage bucket for those articles
- Test: Verify the Supabase client connects successfully

### Step 3: Gmail fetcher
- Create `backend/gmail_fetcher.py`
- Uses OAuth2 with `credentials.json` (the file is already in the backend folder)
- On first run, it will open a browser for the user to authorize. After that, it saves a `token.json` for future use. Add `token.json` to .gitignore too.
- Functions:
  - `authenticate()` — OAuth2 flow, returns Gmail service
  - `fetch_newsletters()` — Search for unread emails from TLDR, TLDR AI, DailyFin senders
  - `parse_email(raw_email)` — Extract individual articles (title + snippet) from the HTML body. Each newsletter source has a different HTML format, handle each one separately.
  - `mark_as_read(message_id)` — Mark email as read after processing
- Return format: `[{"title": str, "snippet": str, "source": str, "url": str}]`
- Log every step with Python logging
- Test: Create `test_gmail.py` that authenticates and prints the count of unread newsletters

### Step 4: Claude AI processor
- Create `backend/article_processor.py`
- Function: `process_article(title, snippet, source) -> dict`
- Uses `anthropic` SDK with `claude-sonnet-4-20250514` model
- The prompt should:
  - Use XML tags for structure
  - Ask Claude to return valid JSON
  - For TLDR and TLDR AI: process in English
  - For DailyFin: process in Portuguese
- Output per article:
```json
{
  "summary": "1-2 paragraph summary of what happened and why it matters",
  "learning_points": [
    {"concept": "Name", "why_it_matters": "One sentence", "practical_use": "One sentence"}
  ],
  "conversation_tip": "A natural sentence showing how to mention this in a conversation or interview",
  "tags": ["AI", "LLM"]
}
```
- Retry logic: if API call fails, wait 5 seconds, try once more
- Batch function: `process_batch(articles) -> list` with 1-second delay between calls
- Test: Create `test_processor.py` with a hardcoded sample article

### Step 5: Text-to-Speech
- Create `backend/tts_generator.py`
- Uses Google Cloud TTS with the service account key in `tts-service-account.json`
- Function: `generate_audio(text, article_id, language="en") -> str`
  - For English articles: use "en-US" voice
  - For Portuguese articles (DailyFin): use "pt-BR" voice
  - The text to convert: summary + conversation tip (NOT the full learning points — keep audio short)
  - Upload the audio file to Supabase Storage bucket "audio"
  - Return the public URL of the uploaded file
- Function: `generate_playlist(articles) -> list[str]`
  - Generates audio for all articles, returns list of audio URLs in order
- Test: Generate audio for a sample text, verify the file uploads to Supabase

### Step 6: Daily pipeline + scheduler
- Create `backend/scheduler.py`
- Uses APScheduler to run the pipeline daily (configurable time, default 7:00 AM UTC-3 Brasilia time)
- The pipeline function `run_daily_pipeline()`:
  1. Fetch unread newsletters from Gmail
  2. Parse articles from each email
  3. Process each article with Claude AI
  4. Generate audio for each article
  5. Save everything to Supabase (articles + audio URLs)
  6. Mark emails as read
  7. Delete articles and audio files older than 7 days
- Add scheduler startup to `main.py`
- Add manual trigger: `POST /api/fetch-now` endpoint (for testing)
- Add detailed logging for each step

### Step 7: Backend API endpoints
Add to `main.py`:
- `GET /api/articles/today` — Get today's articles
- `GET /api/articles/{id}` — Get single article
- `GET /api/audio/playlist` — Get ordered list of today's audio URLs for the LISTEN feature
- `POST /api/fetch-now` — Manually trigger the pipeline
- `GET /health` — Health check
- CORS middleware (allow all origins for development)
- Test: Use FastAPI docs at /docs to verify all endpoints

### Step 8: Mobile app — Home screen
- Look at the logo in `logo/` folder. Extract the main colors and use them as the app theme.
- Set up Expo Router (but we only need 2 screens: home and read)
- **Home screen** (`app/index.tsx`):
  - Shows ARDOR logo at the top (from `logo/` folder)
  - Today's date in a nice format (e.g. "Saturday, March 28")
  - Article count (e.g. "14 articles today" or "No articles yet today")
  - Two big buttons stacked vertically:
    - 🎧 LISTEN — big button, primary accent color
    - 📰 READ — big button, secondary style
  - Clean, minimal design. Dark background. The logo colors guide everything.
- Create `mobile/lib/api.ts` — Functions to call the backend
- Test: `npx expo start` should show the home screen

### Step 9: Mobile app — Listen screen
- **Listen screen** (`app/listen.tsx`):
  - Fetches the audio playlist from the API
  - Plays articles one after another (like a podcast playlist)
  - Shows: current article title and source, play/pause button, skip forward/back buttons, progress bar
  - Simple and clean — no album art, no fancy animations
  - Uses `expo-av` for audio playback
  - Back button to return home
- Test: Play a test audio file

### Step 10: Mobile app — Read screen
- **Read screen** (`app/read.tsx`):
  - Fetches today's articles from the API
  - Scrollable list grouped by source (TLDR section, TLDR AI section, DailyFin section)
  - Each article card shows:
    - Source badge (colored by source)
    - Title (bold)
    - Summary (full text, not truncated)
    - Learning points (collapsible/expandable section)
    - Conversation tip (italic, in a highlighted box — this is the "how to use in conversation" part)
    - Tags at the bottom
  - Pull-to-refresh
  - Back button to return home
- Test: Display mock articles, verify scrolling and layout

### Step 11: Connect everything
- Point mobile app to the real backend (use environment variable for API URL so it's easy to switch between local and production)
- Add loading spinners while fetching data
- Add error states ("Could not load articles. Pull to retry.")
- Add empty state on home screen if no articles yet ("No articles yet. Check back later!")
- Test the FULL flow: trigger fetch → see articles in READ → play audio in LISTEN

### Step 12: Prepare for deployment
- Backend for Render:
  - Start command: `uvicorn main:app --host 0.0.0.0 --port $PORT`
  - Document which env vars to set in Render dashboard
  - Health check endpoint exists at `/health`
- Mobile for Play Store:
  - Update `app.json`: name="ARDOR", proper splash screen using logo colors
  - Create `eas.json` with build profiles
  - Use the logo from `logo/` as the app icon
- Update README.md (keep it very simple):
  - What ARDOR does (2 sentences)
  - How to run locally (copy-paste commands)
  - What env vars are needed
  - How to deploy
  - That's it. No essays.

## AFTER BUILDING

Give me a summary of:
1. Every file created and what it does (one sentence each)
2. The SQL I need to run in Supabase SQL Editor
3. How to run the full pipeline locally for the first time
4. Any manual steps I still need to do
