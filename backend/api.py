import os
from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from datetime import datetime
print("🚀 API iniciando...")
from storage import listar_audios, url_audio

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

@app.get("/lista")
def listar():
    return {"audios": listar_audios()}