# main.py — FastAPI entry point
# Thin routes only — all logic lives in the module files.
# CORS is wide open for development; tighten to your Render/Expo domain in production.

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
import logging

load_dotenv()
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

app = FastAPI(title="ARDOR API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup():
    try:
        from scheduler import start_scheduler
        start_scheduler()
    except Exception as e:
        logger.warning(f"Scheduler failed to start: {e}")


# ─── Health ───────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok"}


# ─── Articles ─────────────────────────────────────────────────────────────────

@app.get("/api/articles/today")
def get_today():
    """Return all articles published today."""
    from database import get_todays_articles
    articles = get_todays_articles()
    return {"articles": articles, "count": len(articles)}


@app.get("/api/articles/{article_id}")
def get_article(article_id: str):
    from database import get_article as db_get
    article = db_get(article_id)
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")
    return article


# ─── Audio playlist ───────────────────────────────────────────────────────────

@app.get("/api/audio/playlist")
def get_playlist():
    """
    Return today's articles that have audio, in source order.
    The LISTEN screen plays these sequentially like a podcast.
    """
    from database import get_todays_articles
    articles = get_todays_articles()
    playlist = [
        {"id": a["id"], "title": a["title"], "source": a["source"], "audio_url": a["audio_url"]}
        for a in articles
        if a.get("audio_url")
    ]
    return {"playlist": playlist, "count": len(playlist)}


# ─── Manual pipeline trigger ──────────────────────────────────────────────────

@app.post("/api/fetch-now")
async def fetch_now():
    """Trigger the full pipeline immediately. Useful for testing without waiting for the scheduler."""
    import asyncio
    from scheduler import run_daily_pipeline
    asyncio.create_task(asyncio.to_thread(run_daily_pipeline))
    return {"status": "started", "message": "Pipeline running in background — check server logs"}
