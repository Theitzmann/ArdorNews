from gmail_reader import ler_newsletters
from summarizer import resumir_newsletters
from tts import gerar_audio

def gerar_audio_do_dia():
    print("📬 Lendo newsletters...")
    textos = ler_newsletters()

    print("🤖 Resumindo com IA...")
    resumo = resumir_newsletters(textos)

    print("🎙️ Gerando áudio...")
    caminho = gerar_audio(resumo)

    print(f"✅ Pronto! Áudio do dia gerado em: {caminho}")
    return caminho

if __name__ == "__main__":
    gerar_audio_do_dia()