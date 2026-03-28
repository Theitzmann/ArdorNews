# scheduler.py — APScheduler daily pipeline + cleanup
# Default run time: 10:00 UTC = 7:00 AM Brasília (UTC-3).
# Cleanup at the END of each run: deletes articles and audio older than 7 days.
# All steps are logged so you can trace exactly what happened.

import os
import logging
from apscheduler.schedulers.background import BackgroundScheduler
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)


def run_daily_pipeline():
    """Full pipeline: Gmail → Claude → TTS → Supabase → cleanup."""
    logger.info("=== ARDOR daily pipeline started ===")
    try:
        # 1. Authenticate and fetch unread newsletters
        from gmail_fetcher import authenticate, fetch_newsletters, parse_email, mark_as_read
        service = authenticate()
        raw_emails = fetch_newsletters(service)
        logger.info(f"Fetched {len(raw_emails)} emails")

        if not raw_emails:
            logger.info("No new emails. Pipeline done.")
            _cleanup()
            return

        # 2. Parse articles from each email
        raw_articles = []
        for email in raw_emails:
            parsed = parse_email(email)
            for a in parsed:
                a["_email_id"] = email["id"]
            raw_articles.extend(parsed)
        logger.info(f"Parsed {len(raw_articles)} articles")

        if not raw_articles:
            logger.warning("Emails found but no articles parsed")
            _cleanup()
            return

        # 3. Enrich with Claude
        from article_processor import process_batch
        enriched = process_batch(raw_articles)
        logger.info(f"Processed {len(enriched)} articles with Claude")

        # 4. Generate audio + save to DB
        from tts_generator import generate_audio, build_audio_text
        from database import save_article
        from datetime import date

        email_ids = set()
        saved = 0

        for article in enriched:
            if not article.get("summary"):
                logger.warning(f"Skipping (no summary): {article.get('title', '')[:60]}")
                continue

            language = "pt" if article.get("source") == "dailyfin" else "en"
            audio_url = generate_audio(build_audio_text(article), article_id=article.get("title", "")[:40], language=language)

            save_article({
                "title": article.get("title", ""),
                "source": article.get("source", ""),
                "original_url": article.get("url", ""),
                "summary": article.get("summary", ""),
                "learning_points": article.get("learning_points", []),
                "conversation_tip": article.get("conversation_tip", ""),
                "tags": article.get("tags", []),
                "audio_url": audio_url,
                "published_at": str(date.today()),
            })
            saved += 1
            email_ids.add(article.get("_email_id"))

        logger.info(f"Saved {saved} articles")

        # 5. Mark emails as read
        for eid in email_ids:
            if eid:
                mark_as_read(service, eid)

        # 6. Cleanup articles older than 7 days
        _cleanup()

        logger.info(f"=== Pipeline complete. {saved} articles saved. ===")

    except Exception as e:
        logger.exception(f"Pipeline failed: {e}")


def _cleanup():
    """Delete articles and audio files older than 7 days."""
    try:
        from database import delete_old_articles
        delete_old_articles(days=7)
    except Exception as e:
        logger.error(f"Cleanup failed: {e}")


def start_scheduler():
    """Start background scheduler. Called once from main.py at startup."""
    hour = int(os.environ.get("PIPELINE_HOUR", 10))    # 10 UTC = 7am Brasília
    minute = int(os.environ.get("PIPELINE_MINUTE", 0))

    scheduler = BackgroundScheduler(timezone="UTC")
    scheduler.add_job(run_daily_pipeline, "cron", hour=hour, minute=minute,
                      id="daily_pipeline", replace_existing=True)
    scheduler.start()
    logger.info(f"Scheduler running — pipeline fires daily at {hour:02d}:{minute:02d} UTC")
    return scheduler
