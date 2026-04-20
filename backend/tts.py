import os
import re
from datetime import datetime
from google.cloud import texttospeech
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

SERVICE_ACCOUNT_PATH = os.path.join(BASE_DIR, 'secrets', 'tts-service-account.json')
LIMITE = 4500

client = texttospeech.TextToSpeechClient.from_service_account_file(SERVICE_ACCOUNT_PATH)

def get_output_path():
    hoje = datetime.now().strftime('%Y-%m-%d')
    return os.path.join(BASE_DIR, 'audio', f'{hoje}.mp3')

def limpar_markdown(texto):
    texto = re.sub(r'#{1,6}\s*', '', texto)
    texto = re.sub(r'\*\*(.*?)\*\*', r'\1', texto)
    texto = re.sub(r'\*(.*?)\*', r'\1', texto)
    texto = re.sub(r'---+', '', texto)
    texto = re.sub(r'\[.*?\]\(.*?\)', '', texto)

    substituicoes = {
        'AI': 'Inteligência Artificial',
        'API': 'A P I',
        'GPT': 'G P T',
        'CEO': 'C E O',
        'IPO': 'I P O',
        'ML': 'Machine Learning',
        'startup': 'startap',
        'startups': 'startaps',
        'software': 'softuér',
        'hardware': 'hárdwér',
        'open source': 'ópen sôrs',
    }
    for termo, pronuncia in substituicoes.items():
        texto = re.sub(rf'\b{termo}\b', pronuncia, texto, flags=re.IGNORECASE)

    return texto.strip()

def dividir_texto(texto):
    partes = []
    while len(texto) > LIMITE:
        corte = texto[:LIMITE].rfind('. ')
        partes.append(texto[:corte + 1])
        texto = texto[corte + 1:]
    partes.append(texto)
    return partes

def limpar_audios_antigos():
    pasta = os.path.join(BASE_DIR, 'audio')
    arquivos = sorted(os.listdir(pasta))
    while len(arquivos) > 7:
        os.remove(os.path.join(pasta, arquivos[0]))
        arquivos.pop(0)
        print(f"🗑️ Áudio antigo removido")

def gerar_audio(texto):
    os.makedirs(os.path.join(BASE_DIR, 'audio'), exist_ok=True)
    output_path = get_output_path()

    texto = limpar_markdown(texto)
    partes = dividir_texto(texto)
    print(f"📝 Texto dividido em {len(partes)} partes")

    bytes_final = b""
    for i, parte in enumerate(partes):
        print(f"🎙️ Gerando parte {i + 1}/{len(partes)}...")
        input_texto = texttospeech.SynthesisInput(text=parte)
        voz = texttospeech.VoiceSelectionParams(
            language_code='pt-BR',
            name='pt-BR-Neural2-C'
        )
        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3,
            speaking_rate=1.05
        )
        resposta = client.synthesize_speech(
            input=input_texto,
            voice=voz,
            audio_config=audio_config
        )
        bytes_final += resposta.audio_content

    with open(output_path, 'wb') as f:
        f.write(bytes_final)

    limpar_audios_antigos()
    print(f"✅ Áudio gerado em: {output_path}")
    return output_path

if __name__ == "__main__":
    from summarizer import resumir_newsletters
    from gmail_reader import ler_newsletters
    textos = ler_newsletters()
    resumo = resumir_newsletters(textos)
    gerar_audio(resumo)