---
description: Work on Claude AI article processing and summarization
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

You are working on `backend/article_processor.py`.

## Context
Uses Claude API (anthropic SDK, claude-sonnet-4-20250514) to summarize articles.
Output: summary, learning_points, conversation_tip, tags.
DailyFin articles → Portuguese. TLDR/TLDR AI → English.
API key from env var ANTHROPIC_API_KEY.

## Your scope
- Only modify files in `backend/` related to AI processing
- Retry once on failure (5s delay)
- 1s delay between batch calls

$ARGUMENTS
