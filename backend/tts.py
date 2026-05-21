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
    # Uniformizar "por cento" para "%"
    texto = texto.replace(' por cento', ' %')

    # Substituições específicas
    substituicoes = {
        'S e P quinhentos': 'S&P 500',
        'Se P quinhentos': 'S&P 500',
        'S&P quinhentos': 'S&P 500',
        'G um': 'G1',
        'U S I M cinco': 'USIM5',
        'USIM cinco': 'USIM5',
        'S A F': 'SAF',
        'vinte e cinco de abril': '25 de abril',
        'primeiro de janeiro': '1º de janeiro',
    }
    for original, novo in sorted(substituicoes.items(), key=lambda x: len(x[0]), reverse=True):
        texto = texto.replace(original, novo)

    # Siglas com espaços entre letras maiúsculas (ex: O T O F → OTOF)
    texto = re.sub(r'\b([A-Z])(?: ([A-Z]))+\b', lambda m: m.group(0).replace(' ', ''), texto)

    # Construir dicionário abrangente de números por extenso
    numeros_base = {
        'zero': 0, 'um': 1, 'dois': 2, 'três': 3, 'quatro': 4, 'cinco': 5,
        'seis': 6, 'sete': 7, 'oito': 8, 'nove': 9, 'dez': 10,
        'onze': 11, 'doze': 12, 'treze': 13, 'catorze': 14, 'quatorze': 14,
        'quinze': 15, 'dezesseis': 16, 'dezessete': 17, 'dezoito': 18, 'dezenove': 19,
        'vinte': 20, 'trinta': 30, 'quarenta': 40, 'cinquenta': 50,
        'sessenta': 60, 'setenta': 70, 'oitenta': 80, 'noventa': 90,
        'cem': 100
    }
    
    mapa_numeros = {k: str(v) for k, v in numeros_base.items()}
    
    dezenas = ['vinte', 'trinta', 'quarenta', 'cinquenta', 'sessenta', 'setenta', 'oitenta', 'noventa']
    unidades = ['um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove']
    for i, d in enumerate(dezenas):
        d_val = (i + 2) * 10
        for j, u in enumerate(unidades):
            u_val = j + 1
            mapa_numeros[f"{d} e {u}"] = str(d_val + u_val)
            
    mapa_numeros.update({
        'duzentos': '200', 'trezentos': '300', 'quatrocentos': '400',
        'quinhentos': '500', 'seiscentos': '600', 'setecentos': '700',
        'oitocentos': '800', 'novecentos': '900', 'mil': '1000'
    })

    # Construir mapa de anos (1900 a 2030)
    mapa_anos = {'mil novecentos': '1900', 'dois mil': '2000'}
    for k, v in mapa_numeros.items():
        if v.isdigit() and 1 <= int(v) <= 99:
            mapa_anos[f"mil novecentos e {k}"] = str(1900 + int(v))
        if v.isdigit() and 1 <= int(v) <= 30:
            mapa_anos[f"dois mil e {k}"] = str(2000 + int(v))

    # Converter anos por extenso para algarismos
    for extenso, algarismo in sorted(mapa_anos.items(), key=lambda x: len(x[0]), reverse=True):
        texto = re.sub(rf'\b{extenso}\b', algarismo, texto)

    # Converter decimais ("X, extenso %") e números inteiros ("extenso %")
    for extenso, algarismo in sorted(mapa_numeros.items(), key=lambda x: len(x[0]), reverse=True):
        # Para decimais: adiciona zero à esquerda se < 10
        dec_val = algarismo.zfill(2) if int(algarismo) < 100 else algarismo
        texto = re.sub(rf'(\d+),\s*{extenso}\s*%', rf'\1,{dec_val}%', texto)
        
        # Para inteiros com %
        texto = re.sub(rf'\b{extenso}\s*%', rf'{algarismo}%', texto)

    # Remover espaço antes do símbolo de % para manter formatação (ex: "37 %" -> "37%")
    texto = re.sub(r'(\d)\s+%', r'\1%', texto)

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
    # resumir_newsletters returns (titulo, resumo_text); gerar_audio takes only the text
    titulo, resumo = resumir_newsletters(textos)
    gerar_audio(resumo)