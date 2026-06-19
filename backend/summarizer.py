import os
import re
import json
from datetime import datetime
from anthropic import Anthropic
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

DIAS_SEMANA = ['segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado', 'domingo']
MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro']

# Data de hoje por extenso (ex: "quinta-feira, 19 de junho de 2026")
def data_hoje_por_extenso():
    hoje = datetime.now()
    dia_semana = DIAS_SEMANA[hoje.weekday()]
    mes = MESES[hoje.month - 1]
    return f"{dia_semana}, {hoje.day} de {mes} de {hoje.year}"

# Gera um título curto a partir dos emails
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

# Transforma os emails no roteiro de áudio do dia; devolve (título, roteiro)
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
- Seja didático: na primeira vez que usar um termo técnico ou de negócios (ex.: IPO, stablecoin, kernel, comércio agêntico), explique em poucas palavras, de forma simples, dentro da própria frase. Ex.: "vai fazer um IPO, ou seja, vender ações ao público pela primeira vez".
- Dê contexto suficiente para o ouvinte entender por que aquilo importa.

Regras de estilo (texto falado):
- Escreva como se estivesse falando, não escrevendo. Frases curtas e diretas.
- Tom profissional e tranquilo. Evite "olha só", "e não para por aí", "que bacana".
- Escreva as siglas e palavras em inglês de forma CORRETA e natural: "IA", "GPT", "IPO", "CEO", "API", "software", "hardware", "startup", "token". NÃO invente grafias fonéticas (nada de "sóftwear" ou "stártap") — a pronúncia do áudio é tratada depois, à parte.
- Nunca use markdown, asteriscos, hashtags ou símbolos.
- Termine com uma frase de encerramento curta e discreta.

IMPORTANTE: escreva APENAS o roteiro, sem títulos, sem listas, sem qualquer formatação.

Emails de hoje:
{conteudo}"""
            }
        ]
    )
    return titulo, resposta.content[0].text

# Lê a resposta do modelo como lista, tolerando ```json e texto em volta
def _extrair_json(texto):
    texto = texto.strip()
    if texto.startswith("```"):
        texto = re.sub(r"^```(?:json)?", "", texto).strip()
        texto = re.sub(r"```$", "", texto).strip()
    if not texto.startswith("["):
        inicio, fim = texto.find("["), texto.rfind("]")
        if inicio != -1 and fim != -1:
            texto = texto[inicio : fim + 1]
    return json.loads(texto)


# Gera um destaque por notícia (emoji, título, resumo e "o que aprender").
# Devolve [] se o JSON vier inválido, pra não travar o pipeline.
def gerar_destaques(textos):
    conteudo = "\n\n---\n\n".join(textos)

    resposta = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=4096,
        messages=[
            {
                "role": "user",
                "content": f"""Com base nos emails de newsletters abaixo, identifique TODAS as notícias relevantes do dia e gere um destaque para cada uma.

Responda APENAS com um array JSON válido (sem texto antes ou depois, sem markdown), no formato exato:
[
  {{
    "emoji": "<um emoji que represente o tema da notícia>",
    "titulo": "<frase curta e direta, no máximo 10 palavras>",
    "resumo": "<a notícia explicada do começo ao fim, em 2 a 4 frases curtas, de forma simples e didática>",
    "aprender": "<a lição ou conceito principal para o leitor lembrar, em 1 frase>"
  }}
]

Regras:
- Crie um item para CADA notícia distinta do dia (normalmente entre 4 e 10 itens).
- Mesmo que o conteúdo não seja notícia tradicional (opinião, tutorial, newsletter de gestão), extraia os pontos ou ideias mais importantes no mesmo formato. Nunca peça desculpa nem diga que não é possível.
- Escreva em português brasileiro claro e simples. Explique termos técnicos em poucas palavras.
- O "resumo" deve dar contexto suficiente para entender o que aconteceu e por que importa — direto, sem enrolação e sem hype.
- O "aprender" é o conceito que fica: o que a pessoa de fato aprende com essa notícia.
- Escreva siglas e palavras em inglês corretamente (IA, GPT, IPO, software, startup). Não use grafias fonéticas.
- Não use markdown, asteriscos nem aspas dentro dos textos.
- Responda SOMENTE com o array JSON.

Emails:
{conteudo[:8000]}"""
            }
        ]
    )
    try:
        destaques = _extrair_json(resposta.content[0].text)
        # Mantém só os itens bem formados, pra nunca exibir vazio no app
        return [
            {
                "emoji": str(d.get("emoji", "📰")),
                "titulo": str(d.get("titulo", "")).strip(),
                "resumo": str(d.get("resumo", "")).strip(),
                "aprender": str(d.get("aprender", "")).strip(),
            }
            for d in destaques
            if isinstance(d, dict) and d.get("titulo")
        ]
    except Exception as e:
        print(f"⚠️ Falha ao gerar destaques (JSON inválido): {e}")
        return []


if __name__ == "__main__":
    from gmail_reader import ler_newsletters
    textos = ler_newsletters()
    titulo, resumo = resumir_newsletters(textos)
    print(f"Título: {titulo}")
    print(resumo[:500])
    print("\nDestaques:")
    for d in gerar_destaques(textos):
        print(f"  {d['emoji']} {d['titulo']}")
