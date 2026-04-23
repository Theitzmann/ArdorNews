import os
from supabase import create_client
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

supabase = create_client(
    os.getenv("SUPABASE_URL"),
    os.getenv("SUPABASE_KEY")
)

BUCKET = "audios"

def upload_audio(caminho_local):
    nome_arquivo = os.path.basename(caminho_local)
    with open(caminho_local, 'rb') as f:
        supabase.storage.from_(BUCKET).upload(
            nome_arquivo,
            f,
            {"content-type": "audio/mpeg"}
        )
    url = supabase.storage.from_(BUCKET).get_public_url(nome_arquivo)
    print(f"☁️ Áudio enviado para o Supabase: {url}")
    return url

def listar_audios():
    arquivos = supabase.storage.from_(BUCKET).list()
    return [a['name'] for a in arquivos]

def url_audio(nome_arquivo):
    return supabase.storage.from_(BUCKET).get_public_url(nome_arquivo)