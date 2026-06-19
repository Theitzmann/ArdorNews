import os
from datetime import datetime, timezone

import httpx
from dateutil.relativedelta import relativedelta
from supabase import create_client
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

# Para sem credencial, com erro claro
if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError(
        "Missing Supabase credentials — set SUPABASE_URL and SUPABASE_KEY env vars."
    )

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

BUCKET = "audios"

# Cliente HTTP reaproveitado entre as chamadas (evita reabrir conexão a cada vez)
http_client = httpx.AsyncClient(timeout=10.0)

# Cache em memória dos arquivos de texto (são imutáveis depois de salvos)
_cache_textos: dict[str, str] = {}


async def _buscar_texto(nome_txt: str, padrao: str) -> str:
    # Busca um arquivo de texto do bucket público; devolve o padrão se falhar
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
        print(f"⚠️ Falha ao buscar {nome_txt}: {e}")
    return padrao

def _upload_ou_atualizar(nome_arquivo, conteudo, content_type):
    # Envia o arquivo; se já existir, atualiza
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
    # Limite alto pra não cortar a lista de arquivos
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

def upload_destaques(nome_audio, conteudo_json):
    _upload_ou_atualizar(
        nome_audio.replace('.mp3', '_destaques.json'),
        conteudo_json.encode('utf-8'),
        "application/json",
    )
    print("☁️ Destaques salvos!")

async def buscar_destaques(nome_audio):
    # Vazio = edição antiga sem detalhes (o app cai na lista simples)
    return await _buscar_texto(nome_audio.replace('.mp3', '_destaques.json'), "")

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
    # Apaga todas as edições com mais de `meses` meses (cada edição tem 6 arquivos)
    limite = datetime.now(timezone.utc) - relativedelta(months=meses)

    arquivos = supabase.storage.from_(BUCKET).list(options={"limit": 1000})
    mp3s = [a['name'] for a in arquivos if a['name'].endswith('.mp3')]

    apagados = 0
    for nome_audio in mp3s:
        try:
            # Pega a data pelo nome do arquivo: 2026-05-18.mp3 → 2026-05-18
            data_str = nome_audio.replace('.mp3', '')
            data = datetime.strptime(data_str, '%Y-%m-%d').replace(
                tzinfo=timezone.utc
            )
        except ValueError:
            # Ignora arquivos fora do padrão de nome
            continue

        if data < limite:
            # Apaga os 6 arquivos da edição
            ficheiros = [
                nome_audio,
                nome_audio.replace('.mp3', '.txt'),
                nome_audio.replace('.mp3', '_bullets.txt'),
                nome_audio.replace('.mp3', '_destaques.json'),
                nome_audio.replace('.mp3', '_transcricao.txt'),
                nome_audio.replace('.mp3', '_emoji.txt'),
            ]
            supabase.storage.from_(BUCKET).remove(ficheiros)
            print(f"🗑️ Edição apagada: {data_str}")
            apagados += 1

    print(f"✅ Limpeza concluída: {apagados} edições apagadas.")
