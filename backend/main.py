import os
from gmail_reader import ler_newsletters
from summarizer import resumir_newsletters, gerar_bullets
from tts import gerar_audio, limpar_markdown, limpar_para_legenda
from storage import upload_audio, upload_titulo, upload_transcricao, upload_bullets

def gerar_audio_do_dia():
    print("📬 Lendo newsletters...")
    textos = ler_newsletters()

    print("🤖 Resumindo com IA...")
    titulo, resumo = resumir_newsletters(textos)
    print(f"📰 Título: {titulo}")

    print("📌 Gerando bullets...")
    bullets = gerar_bullets(textos)
    print(f"Bullets: {bullets}")

    print("🎙️ Gerando áudio...")
    caminho = gerar_audio(resumo)

    texto_legenda = limpar_para_legenda(limpar_markdown(resumo))

    print("☁️ Enviando para o Supabase...")
    url = upload_audio(caminho)

    nome_audio = os.path.basename(caminho)
    upload_titulo(nome_audio, titulo)
    upload_transcricao(nome_audio, texto_legenda)
    upload_bullets(nome_audio, bullets)

    print(f"✅ Pronto! Áudio disponível em: {url}")
    return url

if __name__ == "__main__":
    gerar_audio_do_dia()