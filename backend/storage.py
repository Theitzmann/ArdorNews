import os
from datetime import datetime, timezone

import httpx
from dateutil.relativedelta import relativedelta
from supabase import create_client
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

SUPABASE_URL = os.getenv("SUPABASE_URL")  # e.g. https://<project>.supabase.co
SUPABASE_KEY = os.getenv("SUPABASE_KEY")  # service_role or anon key from Supabase dashboard

# Fail loudly at import time so Railway surfaces a clear error instead of a
# cryptic NoneType crash deep inside the Supabase client.
if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError(
        "Missing Supabase credentials — set SUPABASE_URL and SUPABASE_KEY env vars."
    )

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

BUCKET = "audios"

# Shared async HTTP client — reuses TCP/TLS connections to Supabase instead of
# paying a full handshake on every fetch (the old per-call httpx.get did that).
http_client = httpx.AsyncClient(timeout=10.0)

# In-memory cache for the small text files (title, emoji, bullets, transcript).
# Safe because files are immutable once uploaded: each edition is written once
# by the daily pipeline and never modified. Only successful fetches are cached,
# so a file that doesn't exist yet (today's edition mid-pipeline) is retried.
_cache_textos: dict[str, str] = {}


async def _buscar_texto(nome_txt: str, padrao: str) -> str:
    """Fetches a text file from the public bucket, with caching. Returns
    `padrao` (default value) on any failure, without caching it."""
    if nome_txt in _cache_textos:
        return _cache_textos[nome_txt]
    url = supabase.storage.from_(BUCKET).get_public_url(nome_txt)
    try:
        response = await http_client.get(url)
        if response.status_code == 200:
            texto = response.text.strip()
            _cache_textos[nome_txt] = texto
            return texto
    except Exception as e:
        # Logged (not raised) so a Supabase hiccup degrades to the default
        # value instead of a 500 — but still leaves a trace in Railway logs
        print(f"⚠️ Falha ao buscar {nome_txt}: {e}")
    return padrao

def _upload_ou_atualizar(nome_arquivo, conteudo, content_type):
    """Uploads a file, falling back to update when it already exists
    (Supabase raises on duplicate upload instead of overwriting)."""
    opcoes = {"content-type": content_type}
    try:
        supabase.storage.from_(BUCKET).upload(nome_arquivo, conteudo, opcoes)
    except Exception:
        supabase.storage.from_(BUCKET).update(nome_arquivo, conteudo, opcoes)

def upload_audio(caminho_local):
    nome_arquivo = os.path.basename(caminho_local)
    with open(caminho_local, 'rb') as f:
        _upload_ou_atualizar(nome_arquivo, f.read(), "audio/mpeg")
    url = supabase.storage.from_(BUCKET).get_public_url(nome_arquivo)
    print(f"☁️ Áudio enviado para o Supabase: {url}")
    return url

def upload_titulo(nome_audio, titulo):
    _upload_ou_atualizar(
        nome_audio.replace('.mp3', '.txt'), titulo.encode('utf-8'), "text/plain"
    )
    print(f"☁️ Título salvo: {titulo}")

def listar_audios():
    # Explicit limit prevents silent truncation at 100 files (~20 editions x 5 files each)
    arquivos = supabase.storage.from_(BUCKET).list(options={"limit": 1000})
    return [a['name'] for a in arquivos if a['name'].endswith('.mp3')]

def url_audio(nome_arquivo):
    return supabase.storage.from_(BUCKET).get_public_url(nome_arquivo)

def upload_bullets(nome_audio, bullets):
    _upload_ou_atualizar(
        nome_audio.replace('.mp3', '_bullets.txt'),
        bullets.encode('utf-8'),
        "text/plain",
    )
    print("☁️ Bullets salvos!")

async def buscar_bullets(nome_audio):
    return await _buscar_texto(nome_audio.replace('.mp3', '_bullets.txt'), "")

def upload_emoji(nome_audio, emoji):
    _upload_ou_atualizar(
        nome_audio.replace('.mp3', '_emoji.txt'), emoji.encode('utf-8'), "text/plain"
    )
    print(f"☁️ Emoji salvo: {emoji}")

async def buscar_emoji(nome_audio):
    return await _buscar_texto(nome_audio.replace('.mp3', '_emoji.txt'), '📰')

def upload_transcricao(nome_audio, texto):
    _upload_ou_atualizar(
        nome_audio.replace('.mp3', '_transcricao.txt'),
        texto.encode('utf-8'),
        "text/plain",
    )
    print("☁️ Transcrição salva!")

async def buscar_transcricao(nome_audio):
    return await _buscar_texto(nome_audio.replace('.mp3', '_transcricao.txt'), "")

async def buscar_titulo(nome_audio):
    return await _buscar_texto(
        nome_audio.replace('.mp3', '.txt'), "Resumo Diário de Tecnologia"
    )

def apagar_edicoes_antigas(meses: int = 3):
    """
    Deletes all editions older than `meses` months from Supabase.
    Each daily edition has 5 files sharing the same date prefix:
      YYYY-MM-DD.mp3
      YYYY-MM-DD.txt
      YYYY-MM-DD_bullets.txt
      YYYY-MM-DD_transcricao.txt
      YYYY-MM-DD_emoji.txt
    """
    limite = datetime.now(timezone.utc) - relativedelta(months=meses)

    # Get all .mp3 files to identify editions by date
    arquivos = supabase.storage.from_(BUCKET).list(options={"limit": 1000})
    mp3s = [a['name'] for a in arquivos if a['name'].endswith('.mp3')]

    apagados = 0
    for nome_audio in mp3s:
        try:
            # Extract date from filename: 2026-05-18.mp3 → 2026-05-18
            data_str = nome_audio.replace('.mp3', '')
            data = datetime.strptime(data_str, '%Y-%m-%d').replace(
                tzinfo=timezone.utc
            )
        except ValueError:
            # Skip files that don't match the expected naming pattern
            continue

        if data < limite:
            # Delete all 5 files belonging to this edition
            ficheiros = [
                nome_audio,
                nome_audio.replace('.mp3', '.txt'),
                nome_audio.replace('.mp3', '_bullets.txt'),
                nome_audio.replace('.mp3', '_transcricao.txt'),
                nome_audio.replace('.mp3', '_emoji.txt'),
            ]
            supabase.storage.from_(BUCKET).remove(ficheiros)
            print(f"🗑️ Edição apagada: {data_str}")
            apagados += 1

    print(f"✅ Limpeza concluída: {apagados} edições apagadas.")