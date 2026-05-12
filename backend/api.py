import os
import asyncio
from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from datetime import datetime
from storage import listar_audios, url_audio, buscar_titulo, buscar_transcricao, buscar_bullets, buscar_emoji

app = FastAPI()

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
def transcricao(nome: str):
    texto = buscar_transcricao(nome)
    if texto:
        return {"transcricao": texto}
    return {"erro": "Transcrição não encontrada"}

@app.get("/bullets/{nome}")
def bullets(nome: str):
    texto = buscar_bullets(nome)
    return {"bullets": texto}

async def buscar_info_audio(nome):
    loop = asyncio.get_event_loop()
    titulo, emoji = await asyncio.gather(
        loop.run_in_executor(None, buscar_titulo, nome),
        loop.run_in_executor(None, buscar_emoji, nome),
    )
    return {"nome": nome, "titulo": titulo, "emoji": emoji}

@app.get("/lista")
async def listar():
    audios = listar_audios()
    resultado = await asyncio.gather(*[buscar_info_audio(nome) for nome in audios])
    return {"audios": list(resultado)}