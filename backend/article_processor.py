# article_processor.py — Calls Claude API to turn raw article snippets into structured learning content
# DailyFin articles (Portuguese) get a Portuguese-language prompt so the output is also in Portuguese.
# Uses XML tags in the prompt because Claude responds more reliably to structured inputs.
# Retries once after 5 seconds on any API failure to handle transient errors.

import os
import json
import time
import logging
import anthropic
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

MODEL = "claude-sonnet-4-20250514"

client = anthropic.Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))


# ─── Single article ───────────────────────────────────────────────────────────

def process_article(title: str, snippet: str, source: str) -> dict:
    """
    Send one article to Claude and return structured JSON.
    Returns an empty dict if both attempts fail.
    """
    prompt = _build_prompt(title, snippet, source)
    for attempt in range(2):
        try:
            response = client.messages.create(
                model=MODEL,
                max_tokens=1024,
                messages=[{"role": "user", "content": prompt}],
            )
            text = response.content[0].text.strip()
            return _parse_response(text)
        except Exception as e:
            logger.error(f"Claude API error (attempt {attempt + 1}): {e}")
            if attempt == 0:
                time.sleep(5)  # wait before retry
    return {}


# ─── Batch ────────────────────────────────────────────────────────────────────

def process_batch(articles: list) -> list:
    """
    Process a list of article dicts. Adds Claude output fields to each dict.
    Waits 1 second between calls to stay within rate limits.
    """
    results = []
    for i, article in enumerate(articles):
        logger.info(f"Processing article {i + 1}/{len(articles)}: {article.get('title', '')[:60]}")
        enriched = process_article(
            title=article.get("title", ""),
            snippet=article.get("snippet", ""),
            source=article.get("source", ""),
        )
        results.append({**article, **enriched})
        if i < len(articles) - 1:
            time.sleep(1)
    return results


# ─── Prompt builder ───────────────────────────────────────────────────────────

def _build_prompt(title: str, snippet: str, source: str) -> str:
    is_portuguese = source == "dailyfin"

    if is_portuguese:
        return f"""Você é um assistente que transforma notícias de tecnologia e finanças em material de aprendizado estruturado.

<artigo>
<titulo>{title}</titulo>
<trecho>{snippet}</trecho>
</artigo>

Retorne SOMENTE um objeto JSON válido (sem markdown, sem texto adicional) com esta estrutura:
{{
  "summary": "Resumo em 1-2 parágrafos do que é importante nesta notícia",
  "learning_points": [
    {{
      "concept": "Nome do conceito",
      "why_it_matters": "Por que isso é relevante",
      "practical_use": "Como aplicar esse conhecimento"
    }}
  ],
  "conversation_tip": "Como mencionar naturalmente este assunto em uma entrevista de emprego ou conversa profissional",
  "tags": ["tag1", "tag2"]
}}"""
    else:
        return f"""You are an assistant that turns tech news snippets into structured learning material for developers and tech professionals.

<article>
<title>{title}</title>
<snippet>{snippet}</snippet>
</article>

Return ONLY a valid JSON object (no markdown, no extra text) with this structure:
{{
  "summary": "1-2 paragraph summary of what matters about this news",
  "learning_points": [
    {{
      "concept": "Concept name",
      "why_it_matters": "Why this is relevant to a tech professional",
      "practical_use": "How to apply this knowledge"
    }}
  ],
  "conversation_tip": "How to naturally bring up this topic in a job interview or professional conversation",
  "tags": ["AI", "LLM"]
}}"""


# ─── Response parser ──────────────────────────────────────────────────────────

def _parse_response(text: str) -> dict:
    """Parse Claude's JSON response. If it's wrapped in markdown code fences, strip them."""
    # Claude sometimes wraps JSON in ```json ... ``` even when asked not to
    if text.startswith("```"):
        lines = text.split("\n")
        text = "\n".join(lines[1:-1])  # strip first and last line
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse Claude response as JSON: {e}\nResponse was: {text[:200]}")
        return {}
