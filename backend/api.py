import asyncio
import re
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import RedirectResponse
from datetime import datetime
from storage import (
    listar_audios, url_audio, buscar_titulo, buscar_transcricao,
    buscar_bullets, buscar_emoji, http_client,
)

@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    # Graceful shutdown: release the pooled connections to Supabase
    await http_client.aclose()

# NOTE: error responses use 200 + {"erro": ...} on purpose — the mobile app
# always inspects the body, which keeps the client-side handling uniform.
app = FastAPI(lifespan=lifespan)

# Compress text responses (transcripts are ~8 KB; gzip cuts them to ~3 KB)
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Audio names follow the daily pipeline pattern: 2026-05-18.mp3
NOME_VALIDO = re.compile(r'^\d{4}-\d{2}-\d{2}\.mp3$')

def nome_audio_hoje():
    hoje = datetime.now().strftime('%Y-%m-%d')
    return f'{hoje}.mp3'

@app.get("/status")
def status():
    audios = listar_audios()
    if nome_audio_hoje() in audios:
        return {"pronto": True}
    return {"pronto": False, "mensagem": "Notícias ainda chegando... 11:00 libera!"}

@app.get("/audio")
def audio_do_dia():
    audios = listar_audios()
    nome = nome_audio_hoje()
    if nome in audios:
        return RedirectResponse(url=url_audio(nome))
    return {"erro": "Áudio de hoje ainda não está pronto"}

@app.get("/transcricao/{nome}")
async def transcricao(nome: str):
    if not NOME_VALIDO.match(nome):
        return {"erro": "Nome de áudio inválido"}
    texto = await buscar_transcricao(nome)
    if texto:
        return {"transcricao": texto}
    return {"erro": "Transcrição não encontrada"}

@app.get("/bullets/{nome}")
async def bullets(nome: str):
    if not NOME_VALIDO.match(nome):
        return {"bullets": ""}
    texto = await buscar_bullets(nome)
    return {"bullets": texto}

async def buscar_info_audio(nome):
    titulo, emoji = await asyncio.gather(buscar_titulo(nome), buscar_emoji(nome))
    return {"nome": nome, "titulo": titulo, "emoji": emoji}

@app.get("/lista")
async def listar():
    # listar_audios is a blocking Supabase call — run it off the event loop
    audios = await asyncio.to_thread(listar_audios)
    resultado = await asyncio.gather(*[buscar_info_audio(nome) for nome in audios])
    return {"audios": list(resultado)}
