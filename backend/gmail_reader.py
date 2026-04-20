import os
import base64
import re
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

SCOPES = ['https://www.googleapis.com/auth/gmail.readonly']
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TOKEN_PATH = os.path.join(BASE_DIR, 'secrets', 'token.json')

def conectar_gmail():
    creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)
    return build('gmail', 'v1', credentials=creds)

def limpar_texto(texto):
    # Remove caracteres invisíveis e espaços extras
    texto = re.sub(r'[\u200c\u200b\xa0]', ' ', texto)
    texto = re.sub(r' +', ' ', texto)
    texto = re.sub(r'\n{3,}', '\n\n', texto)
    return texto.strip()

def ler_newsletters():
    service = conectar_gmail()

    result = service.users().messages().list(
        userId='me',
        q='newer_than:1d',
        maxResults=20
    ).execute()

    mensagens = result.get('messages', [])
    textos = []

    for msg in mensagens:
        dados = service.users().messages().get(
            userId='me',
            id=msg['id'],
            format='full'
        ).execute()

        payload = dados['payload']
        if 'parts' in payload:
            parte = payload['parts'][0]['body'].get('data', '')
        else:
            parte = payload['body'].get('data', '')

        texto = base64.urlsafe_b64decode(parte).decode('utf-8', errors='ignore')
        texto = limpar_texto(texto)
        textos.append(texto)

    print(f"✅ {len(textos)} newsletters lidas!")
    return textos

if __name__ == "__main__":
    ler_newsletters()