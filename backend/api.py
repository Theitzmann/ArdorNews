import asyncio
import json
import re
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import RedirectResponse
from datetime import datetime
from storage import (
    listar_audios, url_audio, buscar_titulo, buscar_transcricao,
    buscar_bullets, buscar_destaques, buscar_emoji, http_client,
)

@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    # Fecha as conexões com o Supabase ao desligar
    await http_client.aclose()

app = FastAPI(lifespan=lifespan)

# Comprime as respostas de texto (transcrições ficam bem menores)
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Padrão de nome dos áudios: 2026-05-18.mp3
NOME_VALIDO = re.compile(r'^\d{4}-\d{2}-\d{2}\.mp3$')

def nome_audio_hoje():
    hoje = datetime.now().strftime('%Y-%m-%d')
    return f'{hoje}.mp3'

# Diz se o áudio de hoje já está pronto
@app.get("/status")
def status():
    audios = listar_audios()
    if nome_audio_hoje() in audios:
        return {"pronto": True}
    return {"pronto": False, "mensagem": "Notícias ainda chegando... 11:00 libera!"}

# Redireciona pro áudio de hoje
@app.get("/audio")
def audio_do_dia():
    audios = listar_audios()
    nome = nome_audio_hoje()
    if nome in audios:
        return RedirectResponse(url=url_audio(nome))
    return {"erro": "Áudio de hoje ainda não está pronto"}

# Transcrição de uma edição
@app.get("/transcricao/{nome}")
async def transcricao(nome: str):
    if not NOME_VALIDO.match(nome):
        return {"erro": "Nome de áudio inválido"}
    texto = await buscar_transcricao(nome)
    if texto:
        return {"transcricao": texto}
    return {"erro": "Transcrição não encontrada"}

# Lista simples de destaques (compatibilidade)
@app.get("/bullets/{nome}")
async def bullets(nome: str):
    if not NOME_VALIDO.match(nome):
        return {"bullets": ""}
    texto = await buscar_bullets(nome)
    return {"bullets": texto}

# Destaques detalhados e clicáveis; lista vazia para edições antigas
@app.get("/destaques/{nome}")
async def destaques(nome: str):
    if not NOME_VALIDO.match(nome):
        return {"destaques": []}
    texto = await buscar_destaques(nome)
    if not texto:
        return {"destaques": []}
    try:
        return {"destaques": json.loads(texto)}
    except (ValueError, TypeError):
        return {"destaques": []}

async def buscar_info_audio(nome):
    titulo, emoji = await asyncio.gather(buscar_titulo(nome), buscar_emoji(nome))
    return {"nome": nome, "titulo": titulo, "emoji": emoji}

# Lista todas as edições disponíveis
@app.get("/lista")
async def listar():
    # listar_audios trava o event loop, então roda fora dele
    audios = await asyncio.to_thread(listar_audios)
    resultado = await asyncio.gather(*[buscar_info_audio(nome) for nome in audios])
    return {"audios": list(resultado)}
