import os
import httpx
from supabase import create_client
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

BUCKET = "audios"

def upload_audio(caminho_local):
    nome_arquivo = os.path.basename(caminho_local)
    with open(caminho_local, 'rb') as f:
        try:
            supabase.storage.from_(BUCKET).upload(
                nome_arquivo, f, {"content-type": "audio/mpeg"}
            )
        except Exception:
            f.seek(0)
            supabase.storage.from_(BUCKET).update(
                nome_arquivo, f, {"content-type": "audio/mpeg"}
            )
    url = supabase.storage.from_(BUCKET).get_public_url(nome_arquivo)
    print(f"☁️ Áudio enviado para o Supabase: {url}")
    return url

def upload_titulo(nome_audio, titulo):
    nome_arquivo = nome_audio.replace('.mp3', '.txt')
    conteudo = titulo.encode('utf-8')
    try:
        supabase.storage.from_(BUCKET).upload(
            nome_arquivo, conteudo, {"content-type": "text/plain"}
        )
    except Exception:
        supabase.storage.from_(BUCKET).update(
            nome_arquivo, conteudo, {"content-type": "text/plain"}
        )
    print(f"☁️ Título salvo: {titulo}")

def listar_audios():
    # Explicit limit prevents silent truncation at 100 files (~20 editions x 5 files each)
    arquivos = supabase.storage.from_(BUCKET).list(options={"limit": 1000})
    return [a['name'] for a in arquivos if a['name'].endswith('.mp3')]

def url_audio(nome_arquivo):
    return supabase.storage.from_(BUCKET).get_public_url(nome_arquivo)

def upload_bullets(nome_audio, bullets):
    nome_arquivo = nome_audio.replace('.mp3', '_bullets.txt')
    conteudo = bullets.encode('utf-8')
    try:
        supabase.storage.from_(BUCKET).upload(
            nome_arquivo, conteudo, {"content-type": "text/plain"}
        )
    except Exception:
        supabase.storage.from_(BUCKET).update(
            nome_arquivo, conteudo, {"content-type": "text/plain"}
        )
    print(f"☁️ Bullets salvos!")

def buscar_bullets(nome_audio):
    nome_txt = nome_audio.replace('.mp3', '_bullets.txt')
    url = supabase.storage.from_(BUCKET).get_public_url(nome_txt)
    try:
        response = httpx.get(url)
        if response.status_code == 200:
            return response.text.strip()
    except Exception:
        pass
    return ""

def upload_emoji(nome_audio, emoji):
    nome_arquivo = nome_audio.replace('.mp3', '_emoji.txt')
    conteudo = emoji.encode('utf-8')
    try:
        supabase.storage.from_(BUCKET).upload(
            nome_arquivo, conteudo, {"content-type": "text/plain"}
        )
    except Exception:
        supabase.storage.from_(BUCKET).update(
            nome_arquivo, conteudo, {"content-type": "text/plain"}
        )
    print(f"☁️ Emoji salvo: {emoji}")

def buscar_emoji(nome_audio):
    nome_txt = nome_audio.replace('.mp3', '_emoji.txt')
    url = supabase.storage.from_(BUCKET).get_public_url(nome_txt)
    try:
        response = httpx.get(url)
        if response.status_code == 200:
            return response.text.strip()
    except Exception:
        pass
    return '📰'

def upload_transcricao(nome_audio, texto):
    nome_arquivo = nome_audio.replace('.mp3', '_transcricao.txt')
    conteudo = texto.encode('utf-8')
    try:
        supabase.storage.from_(BUCKET).upload(
            nome_arquivo, conteudo, {"content-type": "text/plain"}
        )
    except Exception:
        supabase.storage.from_(BUCKET).update(
            nome_arquivo, conteudo, {"content-type": "text/plain"}
        )
    print(f"☁️ Transcrição salva!")

def buscar_transcricao(nome_audio):
    nome_txt = nome_audio.replace('.mp3', '_transcricao.txt')
    url = supabase.storage.from_(BUCKET).get_public_url(nome_txt)
    try:
        response = httpx.get(url)
        if response.status_code == 200:
            return response.text.strip()
    except Exception:
        pass
    return ""

def buscar_titulo(nome_audio):
    nome_txt = nome_audio.replace('.mp3', '.txt')
    url = supabase.storage.from_(BUCKET).get_public_url(nome_txt)
    try:
        response = httpx.get(url)
        if response.status_code == 200:
            return response.text.strip()
    except Exception:
        pass
    return "Resumo Diário de Tecnologia"

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
    from datetime import datetime, timezone
    from dateutil.relativedelta import relativedelta

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