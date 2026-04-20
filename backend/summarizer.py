import os
from anthropic import Anthropic
from dotenv import load_dotenv

load_dotenv()

client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

def resumir_newsletters(textos):
    conteudo = "\n\n---\n\n".join(textos)

    resposta = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=8192,
        messages=[
            {
                "role": "user",
                "content": f"""Você é um locutor de podcast de tecnologia em português brasileiro.

Transforme os emails abaixo em um roteiro de áudio natural de 10 minutos.

Regras importantes:
- Escreva no mínimo 1500 palavras para garantir 10 minutos de áudio
- Comece dando bom dia ao Ardor, notícias de tecnologia e falando o dia de hoje.
- Escreva exatamente como se estivesse falando, não escrevendo
- Use frases curtas e naturais
- Nunca use markdown, asteriscos, hashtags ou símbolos
- Pronuncie siglas separadas: escreva "I A" em vez de "IA", "G P T" em vez de "GPT"
- Conecte as notícias com transições naturais como "Mudando de assunto", "Agora vamos falar sobre"
- Desenvolva cada notícia com contexto e explicação
- Termine com uma frase de encerramento natural

Emails de hoje:
{conteudo}"""
            }
        ]
    )

    return resposta.content[0].text

if __name__ == "__main__":
    from gmail_reader import ler_newsletters
    textos = ler_newsletters()
    resumo = resumir_newsletters(textos)
    print(resumo)