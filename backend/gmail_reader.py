import imaplib
import email
from email.header import decode_header
from datetime import datetime, timedelta
import os
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

EMAIL = os.getenv("GMAIL_EMAIL")
PASSWORD = os.getenv("GMAIL_APP_PASSWORD")

def ler_newsletters():
    mail = imaplib.IMAP4_SSL("imap.gmail.com")
    mail.login(EMAIL, PASSWORD)
    mail.select("inbox")

    data_hoje = datetime.now().strftime("%d-%b-%Y")
    _, mensagens = mail.search(None, f'(ON "{data_hoje}")')

    # Se não encontrar emails de hoje, tenta desde ontem como fallback
    if not mensagens[0].split():
        data_ontem = (datetime.now() - timedelta(days=1)).strftime("%d-%b-%Y")
        _, mensagens = mail.search(None, f'(SINCE "{data_ontem}")')
        print("⚠️ Nenhum email de hoje, buscando desde ontem...")

    textos = []
    for num in mensagens[0].split():
        _, dados = mail.fetch(num, "(RFC822)")
        msg = email.message_from_bytes(dados[0][1])

        corpo = ""
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == "text/plain":
                    corpo = part.get_payload(decode=True).decode("utf-8", errors="ignore")
                    break
        else:
            corpo = msg.get_payload(decode=True).decode("utf-8", errors="ignore")

        if corpo.strip():
            textos.append(corpo.strip())

    mail.logout()
    print(f"✅ {len(textos)} newsletters lidas!")
    return textos

if __name__ == "__main__":
    textos = ler_newsletters()
    print(textos[0][:500] if textos else "Nenhum email encontrado")