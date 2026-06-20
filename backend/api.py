import asyncio
import hmac
import json
import os
import re
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import RedirectResponse
from datetime import datetime
import storage
import revenuecat_client
from storage import (
    listar_audios, url_audio, buscar_titulo, buscar_transcricao,
    buscar_bullets, buscar_destaques, buscar_emoji, http_client,
)

# Segredo configurado no painel da RevenueCat; comparado com o header
# Authorization de cada webhook para confirmar que veio mesmo deles.
# (Phase B preenche o valor real no .env.)
REVENUECAT_WEBHOOK_SECRET = os.getenv("REVENUECAT_WEBHOOK_SECRET")

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

# Webhook da RevenueCat: dispara quando a assinatura de alguém muda de estado.
# Não interpretamos cada tipo de evento — usamos como gatilho para buscar o
# estado canônico do assinante na API da RevenueCat e salvá-lo.
@app.post("/webhooks/revenuecat")
async def webhook_revenuecat(request: Request):
    # Confirma que a requisição veio mesmo da RevenueCat.
    # compare_digest evita timing attacks na comparação do segredo.
    auth_header = request.headers.get("Authorization", "")
    esperado = f"Bearer {REVENUECAT_WEBHOOK_SECRET}"
    if not hmac.compare_digest(auth_header, esperado):
        raise HTTPException(status_code=401, detail="Não autorizado")

    body = await request.json()
    event = body.get("event", {})
    app_user_id = event.get("app_user_id")
    event_type = event.get("type")
    event_id = event.get("id")

    print(f"📩 Webhook RevenueCat recebido: {event_type} ({event_id}) para {app_user_id}")

    if not app_user_id:
        # Sem saber de quem é o evento, não há o que fazer
        return {"status": "ignored"}

    try:
        estado = await revenuecat_client.buscar_estado_assinante(app_user_id)
        storage.atualizar_assinante(
            user_id=app_user_id,
            status=estado["status"],
            expires_at=estado["expires_at"],
            revenuecat_id=app_user_id,
        )
    except Exception as e:
        print(f"❌ Erro ao processar webhook: {e}")
        # Ainda devolvemos 200 para a RevenueCat não reenviar infinitamente um
        # erro transitório que já registramos — investigamos manualmente depois.
        return {"status": "error_logged"}

    return {"status": "ok"}
