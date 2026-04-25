import os
from anthropic import Anthropic
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

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

    resposta = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=8192,
        messages=[
            {
                "role": "user",
                "content": f"""Você é um apresentador de podcast de tecnologia e negócios em português brasileiro. Seu estilo é claro, direto e profissional, mas acessível. Sem exageros, sem expressões de euforia.

Transforme os emails abaixo em um roteiro de áudio de 5 a 8 minutos.

Regras importantes:
- Escreva entre 800 e 1200 palavras
- Comece com uma saudação simples e o dia de hoje
- Tom: profissional e informativo, como um bom podcast de negócios
- Evite expressões como "olha só", "e não para por aí", "impressionante", "incrível", "que bacana"
- Escreva exatamente como se estivesse falando, não escrevendo
- Use frases curtas e diretas
- Nunca use markdown, asteriscos, hashtags ou símbolos
- Pronuncie siglas separadas: escreva "I A" em vez de "IA", "G P T" em vez de "GPT"
- Conecte as notícias com transições simples como "Mudando de assunto", "Outro destaque do dia"
- Cubra as notícias mais relevantes com contexto suficiente para o ouvinte entender
- Termine com uma frase de encerramento discreta

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
                "content": f"""Com base nos emails abaixo, gere exatamente 3 bullets das notícias mais importantes do dia.

Formato obrigatório (uma por linha, sem numeração):
- [notícia em uma frase curta e direta, máximo 10 palavras]
- [notícia em uma frase curta e direta, máximo 10 palavras]
- [notícia em uma frase curta e direta, máximo 10 palavras]

Responda apenas com os 3 bullets, nada mais.

Emails:
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