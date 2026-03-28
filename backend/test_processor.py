# test_processor.py — Sends a sample article to Claude and prints the structured output
# Run: python test_processor.py

from article_processor import process_article
import json, logging
logging.basicConfig(level=logging.INFO)

# English test
result = process_article(
    title="OpenAI releases GPT-5 with 10x better reasoning",
    snippet="OpenAI announced GPT-5, which scores significantly higher on reasoning benchmarks. "
            "The model uses a new chain-of-thought architecture and is available via API.",
    source="tldr_ai",
)
print("=== English article ===")
print(json.dumps(result, indent=2, ensure_ascii=False))

print("\n=== Portuguese article (DailyFin) ===")
result_pt = process_article(
    title="Banco Central eleva Selic para 12%",
    snippet="O Copom decidiu aumentar a taxa Selic em 0,5 ponto percentual, "
            "levando a taxa básica de juros para 12% ao ano, em resposta à inflação persistente.",
    source="dailyfin",
)
print(json.dumps(result_pt, indent=2, ensure_ascii=False))
