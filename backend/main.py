import os
import json
from gmail_reader import ler_newsletters
from summarizer import resumir_newsletters, gerar_destaques
from tts import gerar_audio, limpar_formatacao, limpar_para_legenda
from storage import (
    upload_audio, upload_titulo, upload_transcricao,
    upload_bullets, upload_emoji, upload_destaques,
)

# Pipeline diário: lê os emails, resume, gera o áudio e envia tudo pro Supabase
def gerar_audio_do_dia():
    print("📬 Lendo newsletters...")
    textos = ler_newsletters()

    print("🤖 Resumindo com IA...")
    titulo, resumo = resumir_newsletters(textos)
    print(f"📰 Título: {titulo}")

    print("📌 Gerando destaques...")
    destaques = gerar_destaques(textos)
    # Lista curta (emoji + título) pro app; o detalhe completo fica no JSON
    bullets = "\n".join(
        f"{d['emoji']} {d['titulo']}".strip() for d in destaques
    )
    emoji = destaques[0]['emoji'] if destaques else '📰'

    print("🎙️ Gerando áudio...")
    caminho = gerar_audio(resumo)

    # Transcrição mostrada ao usuário: texto limpo, com números normalizados
    texto_legenda = limpar_para_legenda(limpar_formatacao(resumo))

    print("☁️ Enviando para o Supabase...")
    url = upload_audio(caminho)

    nome_audio = os.path.basename(caminho)
    upload_titulo(nome_audio, titulo)
    upload_transcricao(nome_audio, texto_legenda)
    upload_bullets(nome_audio, bullets)
    upload_destaques(nome_audio, json.dumps(destaques, ensure_ascii=False))
    upload_emoji(nome_audio, emoji)

    print(f"✅ Pronto! Áudio disponível em: {url}")
    return url

if __name__ == "__main__":
    gerar_audio_do_dia()
