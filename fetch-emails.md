---
description: Work on the Gmail email fetching pipeline
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

You are working on the **email fetching pipeline** in `backend/gmail_fetcher.py`.

## Context
ARDOR fetches newsletters from `ardor.news@gmail.com` using OAuth2.
Sources: TLDR, TLDR AI, DailyFin. Credentials file: `backend/credentials.json`.
Token is saved as `backend/token.json` after first auth.

## Your scope
- Only modify files in `backend/` related to email fetching
- Return format: `[{"title": str, "snippet": str, "source": str, "url": str}]`
- Handle each newsletter's HTML format separately
- Log every step with Python logging

$ARGUMENTS
