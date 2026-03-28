# tts_generator.py — Converts article text to audio using Google Cloud TTS
# Audio is stored in Supabase Storage (bucket: "audio") and the public URL is returned.
# Only the summary + conversation_tip are read aloud — learning points are text-only
# because they're meant for reading, not listening.

import os
import logging
import uuid
from google.cloud import texttospeech
from supabase import create_client
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

# Voice config per language
VOICE_CONFIG = {
    "en": {"language_code": "en-US", "name": "en-US-Neural2-D", "gender": texttospeech.SsmlVoiceGender.MALE},
    "pt": {"language_code": "pt-BR", "name": "pt-BR-Neural2-B", "gender": texttospeech.SsmlVoiceGender.MALE},
}


def generate_audio(text: str, language: str = "en", article_id: str = None) -> str | None:
    """
    Synthesize speech for the given text and upload to Supabase Storage.
    Returns the public URL of the audio file, or None on failure.
    language: "en" for English, "pt" for Portuguese (DailyFin articles)
    """
    try:
        audio_bytes = _synthesize(text, language)
        url = _upload_to_supabase(audio_bytes, article_id or str(uuid.uuid4()))
        logger.info(f"Audio generated and uploaded: {url}")
        return url
    except Exception as e:
        logger.error(f"TTS generation failed: {e}")
        return None


# ─── Synthesis ────────────────────────────────────────────────────────────────

def _synthesize(text: str, language: str) -> bytes:
    """Call Google Cloud TTS and return raw MP3 bytes."""
    tts_client = texttospeech.TextToSpeechClient()
    voice_cfg = VOICE_CONFIG.get(language, VOICE_CONFIG["en"])

    synthesis_input = texttospeech.SynthesisInput(text=text)
    voice = texttospeech.VoiceSelectionParams(
        language_code=voice_cfg["language_code"],
        name=voice_cfg["name"],
        ssml_gender=voice_cfg["gender"],
    )
    audio_config = texttospeech.AudioConfig(audio_encoding=texttospeech.AudioEncoding.MP3)

    response = tts_client.synthesize_speech(
        input=synthesis_input, voice=voice, audio_config=audio_config
    )
    return response.audio_content


# ─── Upload ───────────────────────────────────────────────────────────────────

def _upload_to_supabase(audio_bytes: bytes, file_id: str) -> str:
    """Upload MP3 bytes to Supabase Storage and return the public URL."""
    url = os.environ["SUPABASE_URL"]
    key = os.environ["SUPABASE_KEY"]
    storage_client = create_client(url, key).storage

    file_path = f"{file_id}.mp3"
    # upsert=True so re-running the pipeline overwrites rather than errors
    storage_client.from_("audio").upload(
        path=file_path,
        file=audio_bytes,
        file_options={"content-type": "audio/mpeg", "upsert": "true"},
    )

    # Build the public URL — Supabase storage public URL format
    public_url = f"{url}/storage/v1/object/public/audio/{file_path}"
    return public_url


# ─── Helper ───────────────────────────────────────────────────────────────────

def build_audio_text(article: dict) -> str:
    """Combine summary and conversation_tip into the text to be spoken."""
    summary = article.get("summary", "")
    tip = article.get("conversation_tip", "")
    if tip:
        # Add a brief intro so the listener knows what's coming
        label = "Como mencionar isso profissionalmente:" if article.get("source") == "dailyfin" else "How to bring this up professionally:"
        return f"{summary}\n\n{label} {tip}"
    return summary
