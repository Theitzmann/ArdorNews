import os
from datetime import datetime
from anthropic import Anthropic
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

DIAS_SEMANA = ['segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado', 'domingo']
MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro']

def data_hoje_por_extenso():
    hoje = datetime.now()
    dia_semana = DIAS_SEMANA[hoje.weekday()]
    mes = MESES[hoje.month - 1]
    return f"{dia_semana}, {hoje.day} de {mes} de {hoje.year}"

def gerar_titulo(conteudo):
    resposta = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=100,
        messages=[
            {
                "role": "user",
                "content": f"""Com base nos emails abaixo, gere um título jornalístico curto em português com no máximo 7 palavras resumindo as principais notícias do dia. Use siglas normalmente (GPT, IA, etc). Responda apenas com o título, sem pontuação no final.

Emails:
{conteudo[:3000]}"""
            }
        ]
    )
    return resposta.content[0].text.strip()

def resumir_newsletters(textos):
    conteudo = "\n\n---\n\n".join(textos)
    titulo = gerar_titulo(conteudo)
    data = data_hoje_por_extenso()

    resposta = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=8192,
        messages=[
            {
                "role": "user",
                "content": f"""Você é um apresentador de podcast de tecnologia e negócios em português brasileiro. Seu estilo é claro, direto e didático: você explica para alguém inteligente que não conhece os termos técnicos. Sem euforia, sem enrolação.

Transforme os emails abaixo em um roteiro de áudio de 5 a 8 minutos.

Regras de conteúdo:
- Escreva entre 800 e 1200 palavras.
- Comece SEMPRE com: "Olá, bom dia. Hoje é {data}. Este é o seu resumo de tecnologia e negócios."
- Vá direto ao fato. Comece cada notícia pelo que aconteceu, não por uma introdução. Bom: "A SpaceX vai abrir capital na bolsa." Ruim: "Vamos começar com uma das notícias mais aguardadas do mercado."
- NÃO use frases de preenchimento: "vamos começar com", "outro destaque do dia", "mudando de assunto", "ainda sobre", "vale destacar", "uma notícia importante". Passe de uma notícia para outra de forma natural, ou simplesmente comece a próxima.
- NÃO qualifique as notícias com hype: "importante", "aguardada", "histórica", "impressionante", "incrível".
- Seja didático: na primeira vez que usar um termo técnico ou de negócios (ex.: IPO, stablecoin, token, kernel, comércio agêntico), explique em poucas palavras, de forma simples, dentro da própria frase. Ex.: "vai fazer um IPO, ou seja, vender ações ao público pela primeira vez".
- Dê contexto suficiente para o ouvinte entender por que aquilo importa.

Regras de estilo (texto falado):
- Escreva como se estivesse falando, não escrevendo. Frases curtas e diretas.
- Tom profissional e tranquilo. Evite "olha só", "e não para por aí", "que bacana".
- Nunca use markdown, asteriscos, hashtags ou símbolos.
- Termine com uma frase de encerramento curta e discreta.

Regras de pronúncia (para o áudio):
- Toda sigla de letras deve ser escrita com as letras separadas por espaço e NUNCA colada a outra palavra: "I A" (não "IA"), "G P T", "C E O", "A P I", "S E C", "U S D C", "N A S D A Q", "G P U". Para "IPO" escreva "I P O" — nunca "OIPO".
- Palavras em inglês comuns: escreva foneticamente e SEMPRE da mesma forma — "software" como "sóftwear", "hardware" como "hárdware", "startup" como "stártap", "token" como "tôuken".

IMPORTANTE: escreva APENAS o roteiro, sem títulos, sem listas, sem qualquer formatação.

Emails de hoje:
{conteudo}"""
            }
        ]
    )
    return titulo, resposta.content[0].text

def gerar_bullets(textos):
    conteudo = "\n\n---\n\n".join(textos)

    resposta = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=300,
        messages=[
            {
                "role": "user",
                "content": f"""Com base no conteúdo abaixo, gere exatamente 3 bullets com os destaques mais relevantes do dia.

Formato obrigatório (uma por linha):
[emoji] [destaque em uma frase curta e direta, máximo 10 palavras]

Regras:
- SEMPRE gere exatamente 3 bullets, qualquer que seja o conteúdo recebido.
- Se o conteúdo não for "notícia" tradicional (ex.: artigos de opinião, tutoriais, newsletters de gestão), mesmo assim extraia os 3 pontos ou ideias mais importantes e resuma-os no mesmo formato.
- Nunca explique, justifique, peça desculpa ou diga que não é possível. Responda APENAS com os 3 bullets, nada mais.
- Escolha um emoji que represente bem o tema de cada bullet.
- Exemplos: 🤖 para IA, 📈 para mercado, 🏥 para saúde, 🚀 para tecnologia, ⚖️ para política, 💰 para finanças, 🌍 para geopolítica, 💡 para ideias, 📊 para dados, 🛠️ para ferramentas

Conteúdo:
{conteudo[:3000]}"""
            }
        ]
    )
    return resposta.content[0].text.strip()

if __name__ == "__main__":
    from gmail_reader import ler_newsletters
    textos = ler_newsletters()
    titulo, resumo = resumir_newsletters(textos)
    print(f"Título: {titulo}")
    print(resumo[:500])