import os
from anthropic import Anthropic
from dotenv import load_dotenv

load_dotenv()

client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

def resumir_newsletters(textos):
    conteudo = "\n\n---\n\n".join(textos)

    resposta = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=1024,
        messages=[
            {
                "role": "user",
                "content": f"""Você é um assistente que resume newsletters de tecnologia.
                
Abaixo estão os emails de hoje. Faça um resumo em português de todas as notícias mais importantes.
O resumo deve:
- Ter entre 10 e 15 minutos de leitura em voz alta
- Ser fluido, como se fosse um locutor de rádio
- Cobrir as notícias mais relevantes de cada email
- Ignorar propagandas e patrocinadores

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