import os
import re
import json
from datetime import datetime
from google.cloud import texttospeech
from google.oauth2 import service_account
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

LIMITE = 4500

def criar_cliente_tts():
    credenciais_json = os.getenv("GOOGLE_TTS_CREDENTIALS")
    if credenciais_json:
        info = json.loads(credenciais_json)
        credenciais = service_account.Credentials.from_service_account_info(
            info,
            scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
        return texttospeech.TextToSpeechClient(credentials=credenciais)
    return texttospeech.TextToSpeechClient.from_service_account_file(
        os.path.join(BASE_DIR, 'secrets', 'tts-service-account.json')
    )

client = criar_cliente_tts()

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

def limpar_para_legenda(texto):
    # Siglas com espaços entre letras maiúsculas (ex: O T O F → OTOF)
    texto = re.sub(r'\b([A-Z]) ([A-Z]) ([A-Z]) ([A-Z])\b', r'\1\2\3\4', texto)
    texto = re.sub(r'\b([A-Z]) ([A-Z]) ([A-Z])\b', r'\1\2\3', texto)
    texto = re.sub(r'\b([A-Z]) ([A-Z])\b', r'\1\2', texto)

    # Expressões numéricas comuns
    substituicoes = {
        'S&P quinhentos': 'S&P 500',
        'Se P quinhentos': 'S&P 500',
        'G um': 'G1',
        'dois mil e vinte e seis': '2026',
        'dois mil e vinte e cinco': '2025',
        'dois mil e dezoito': '2018',
        'dois mil e vinte e quatro': '2024',
        'dois mil e vinte e três': '2023',
        'mil novecentos e noventa': '1990',
        'mil novecentos e oitenta': '1980',
        'mil novecentos e setenta': '1970',
        'mil novecentos e sessenta': '1960',
        'mil novecentos e cinquenta e três': '1953',
        'mil novecentos e cinquenta e quatro': '1954',
        'vinte e cinco de abril': '25 de abril',
        'primeiro de janeiro': '1º de janeiro',
    }
    for original, novo in substituicoes.items():
        texto = texto.replace(original, novo)

    # Números decimais por extenso → algarismos
    # Padrão: "X, por extenso" onde X já é número
    decimais = {
        'trinta e três': '33',
        'sessenta e três': '63',
        'sessenta e quatro': '64',
        'cinquenta e cinco': '55',
        'cinquenta e seis': '56',
        'oitenta': '80',
        'cinquenta': '50',
        'vinte e cinco': '25',
        'vinte': '20',
        'dez': '10',
        'cinco': '05',
        'um': '01',
    }
    for extenso, numero in decimais.items():
        texto = re.sub(rf'(\d+), {extenso}', rf'\1,{numero}', texto)

    # Remove "por cento" e substitui por %
    texto = texto.replace(' por cento', '%')

    return texto

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