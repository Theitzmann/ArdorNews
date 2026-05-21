# Ardor News

App mobile de podcast diário gerado por IA. Todo dia de manhã, ele lê as newsletters de tecnologia (as que eu mais gostava) que chegam no e-mail, resume com o API do Claude, converte em áudio e disponibiliza no app.

A ideia surgiu de um problema simples: assino várias newsletters, muitas vezes nem leio ou abro o email para vê-las. O meu aplicativo resolve isso transformando o conteúdo em algo que dá para ouvir no caminho do trabalho/faculdade.

---

## Como funciona

Um cron job no Railway roda todo dia às 11h e executa o seguinte pipeline:

1. Lê os e-mails do dia via IMAP (Gmail)
2. Resume o conteúdo com a API do Claude (Anthropic)
3. Gera um título, bullets e transcrição de cada edição
4. Converte o resumo em áudio com o Google Cloud TTS
5. Faz upload de tudo no Supabase Storage
6. O app Flutter consome via API FastAPI

---

## Stack

**Backend**
- Python + FastAPI
- Gmail IMAP para leitura de e-mails
- Claude API (Anthropic) para resumo e geração de conteúdo
- Google Cloud Text-to-Speech para o áudio
- Supabase Storage para armazenar os ficheiros
- Railway para hosting e cron jobs

**App**
- Flutter (Android/iOS)
- `just_audio` + `audio_service` para reprodução em background
- `flutter_local_notifications` para notificações diárias
- Google Fonts (Inter)

---

## Estrutura do projeto

```
ArdorNews/
├── backend/
│   ├── main.py               # Orquestra o pipeline diário
│   ├── gmail_reader.py       # Lê newsletters via IMAP
│   ├── summarizer.py         # Resume com Claude API
│   ├── tts.py                # Gera áudio com Google TTS
│   ├── storage.py            # Upload/download no Supabase
│   ├── api.py                # API FastAPI consumida pelo app
│   └── cleanup.py            # Limpeza mensal de edições antigas
└── app/
    └── lib/
        ├── main.dart                  # Ecrã principal e player
        ├── audio_handler.dart         # Serviço de áudio em background
        └── notification_service.dart  # Notificações diárias
```

---

## Variáveis de ambiente

O backend precisa das seguintes variáveis no Railway (ou num `.env` local):

```
GMAIL_EMAIL=
GMAIL_APP_PASSWORD=
ANTHROPIC_API_KEY=
GOOGLE_TTS_CREDENTIALS=   # JSON da service account (conteúdo, não o path)
SUPABASE_URL=
SUPABASE_KEY=             # service_role key
```

---

## Rodar localmente

```bash
cd backend
pip install -r requirements.txt
python main.py
```

Para o app:

```bash
cd app
flutter pub get
flutter run
```

---

Construído por Tiago Heitzmann · 2026