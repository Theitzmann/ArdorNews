# database.py — Supabase client and all database queries
# One function per query. Plain dicts in and out — no ORM, no models.
# The cleanup function also removes audio files from storage so nothing orphaned.

# ─── SQL to run ONCE in Supabase SQL Editor ──────────────────────────────────
#
# -- Articles table
# CREATE TABLE IF NOT EXISTS articles (
#   id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
#   title            TEXT NOT NULL,
#   source           TEXT NOT NULL,
#   original_url     TEXT,
#   summary          TEXT,
#   learning_points  JSONB,
#   conversation_tip TEXT,
#   tags             TEXT[],
#   audio_url        TEXT,
#   published_at     DATE NOT NULL DEFAULT CURRENT_DATE,
#   created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
# );
#
# -- Allow anyone to read articles (no login needed in the app)
# ALTER TABLE articles ENABLE ROW LEVEL SECURITY;
# CREATE POLICY "Public read" ON articles FOR SELECT USING (true);
# CREATE POLICY "Service insert" ON articles FOR INSERT WITH CHECK (true);
# CREATE POLICY "Service delete" ON articles FOR DELETE USING (true);
#
# -- Fast lookup by date
# CREATE INDEX IF NOT EXISTS idx_articles_published_at ON articles(published_at);
#
# -- Create the public audio storage bucket
# -- Run this in Supabase Dashboard → Storage → New bucket → name: "audio", Public: ON
# ─────────────────────────────────────────────────────────────────────────────

import os
import logging
from datetime import date, timedelta
from supabase import create_client, Client
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

_client: Client | None = None


def get_client() -> Client:
    global _client
    if _client is None:
        _client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])
        logger.info("Supabase client initialized")
    return _client


def save_article(data: dict) -> dict:
    """Insert one article. Returns the saved row with its generated id."""
    response = get_client().table("articles").insert(data).execute()
    return response.data[0] if response.data else {}


def get_todays_articles() -> list:
    """Return all articles published today, ordered by source then creation time."""
    today = str(date.today())
    response = (
        get_client().table("articles")
        .select("*")
        .eq("published_at", today)
        .order("source")
        .order("created_at")
        .execute()
    )
    return response.data or []


def get_articles_by_date(target_date: str) -> list:
    """Return articles for a specific date string (YYYY-MM-DD)."""
    response = (
        get_client().table("articles")
        .select("*")
        .eq("published_at", target_date)
        .order("source")
        .order("created_at")
        .execute()
    )
    return response.data or []


def get_article(article_id: str) -> dict | None:
    """Return a single article by id."""
    response = get_client().table("articles").select("*").eq("id", article_id).single().execute()
    return response.data


def delete_old_articles(days: int = 7):
    """
    Delete articles (and their audio files) older than `days` days.
    Called at the end of each daily pipeline run to enforce the 7-day retention policy.
    """
    cutoff = str(date.today() - timedelta(days=days))
    logger.info(f"Deleting articles older than {cutoff}")

    # Fetch old articles first so we can delete their audio files from storage
    old = (
        get_client().table("articles")
        .select("id, audio_url")
        .lt("published_at", cutoff)
        .execute()
    )

    for row in old.data or []:
        audio_url = row.get("audio_url")
        if audio_url:
            _delete_audio_file(audio_url)

    # Now delete the rows
    result = get_client().table("articles").delete().lt("published_at", cutoff).execute()
    deleted_count = len(result.data or [])
    logger.info(f"Deleted {deleted_count} old articles")


def _delete_audio_file(audio_url: str):
    """Extract the filename from the URL and remove it from Supabase Storage."""
    try:
        # URL format: .../storage/v1/object/public/audio/FILENAME.mp3
        filename = audio_url.split("/audio/")[-1]
        get_client().storage.from_("audio").remove([filename])
        logger.info(f"Deleted audio file: {filename}")
    except Exception as e:
        logger.warning(f"Could not delete audio file {audio_url}: {e}")
