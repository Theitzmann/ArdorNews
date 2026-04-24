import os
from gmail_reader import ler_newsletters
from summarizer import resumir_newsletters
from tts import gerar_audio
from storage import upload_audio, upload_titulo

def gerar_audio_do_dia():
    print("📬 Lendo newsletters...")
    textos = ler_newsletters()

    print("🤖 Resumindo com IA...")
    titulo, resumo = resumir_newsletters(textos)
    print(f"📰 Título: {titulo}")

    print("🎙️ Gerando áudio...")
    caminho = gerar_audio(resumo)

    print("☁️ Enviando para o Supabase...")
    url = upload_audio(caminho)

    nome_audio = os.path.basename(caminho)
    upload_titulo(nome_audio, titulo)

    print(f"✅ Pronto! Áudio disponível em: {url}")
    return url

if __name__ == "__main__":
    gerar_audio_do_dia()