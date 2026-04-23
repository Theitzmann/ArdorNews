import os
from fastapi import FastAPI
from fastapi.responses import FileResponse
from datetime import datetime

app = FastAPI()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
AUDIO_DIR = os.path.join(BASE_DIR, 'audio')

def get_audio_hoje():
    hoje = datetime.now().strftime('%Y-%m-%d')
    caminho = os.path.join(AUDIO_DIR, f'{hoje}.mp3')
    if os.path.exists(caminho):
        return caminho
    return None

@app.get("/status")
def status():
    audio = get_audio_hoje()
    if audio:
        return {"pronto": True}
    return {"pronto": False, "mensagem": "Notícias ainda chegando... 11:00 libera!"}

@app.get("/audio")
def audio_do_dia():
    audio = get_audio_hoje()
    if audio:
        return FileResponse(audio, media_type="audio/mpeg")
    return {"erro": "Áudio de hoje ainda não está pronto"}

@app.get("/lista")
def listar_audios():
    arquivos = sorted(os.listdir(AUDIO_DIR), reverse=True)
    return {"audios": arquivos}
