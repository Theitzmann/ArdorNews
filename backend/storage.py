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
    arquivos = supabase.storage.from_(BUCKET).list()
    return [a['name'] for a in arquivos if a['name'].endswith('.mp3')]

def url_audio(nome_arquivo):
    return supabase.storage.from_(BUCKET).get_public_url(nome_arquivo)

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