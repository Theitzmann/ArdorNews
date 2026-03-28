# gmail_fetcher.py — Gmail API client for fetching newsletter emails
# OAuth2 credentials are in credentials.json (already in backend/).
# On first run, opens a browser to authorize. Saves token to token.json after that.
# Each newsletter has a different HTML structure, so each has its own parser.

import os
import base64
import logging
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from bs4 import BeautifulSoup
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

SCOPES = ["https://www.googleapis.com/auth/gmail.modify"]


# ─── Auth ─────────────────────────────────────────────────────────────────────

def authenticate():
    """OAuth2 flow. Opens browser on first run; uses cached token.json after that."""
    creds_file = os.environ.get("GMAIL_CREDENTIALS_FILE", "credentials.json")
    token_file = os.environ.get("GMAIL_TOKEN_FILE", "token.json")
    creds = None

    if os.path.exists(token_file):
        creds = Credentials.from_authorized_user_file(token_file, SCOPES)

    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
        _save_token(creds, token_file)
    elif not creds or not creds.valid:
        flow = InstalledAppFlow.from_client_secrets_file(creds_file, SCOPES)
        creds = flow.run_local_server(port=0)
        _save_token(creds, token_file)

    logger.info("Gmail authenticated")
    return build("gmail", "v1", credentials=creds)


def _save_token(creds, token_file: str):
    with open(token_file, "w") as f:
        f.write(creds.to_json())


# ─── Fetch ────────────────────────────────────────────────────────────────────

def fetch_newsletters(service) -> list[dict]:
    """Search Gmail for unread newsletters. Returns raw message dicts with _source added."""
    queries = [
        ("tldr",    'from:dan@tldrnewsletter.com subject:TLDR is:unread -subject:"TLDR AI"'),
        ("tldr_ai", 'from:dan@tldrnewsletter.com subject:"TLDR AI" is:unread'),
        ("dailyfin", "from:dailyfin is:unread"),
    ]
    messages = []
    for source, query in queries:
        try:
            result = service.users().messages().list(userId="me", q=query, maxResults=5).execute()
            for ref in result.get("messages", []):
                msg = service.users().messages().get(userId="me", id=ref["id"], format="full").execute()
                msg["_source"] = source
                messages.append(msg)
            logger.info(f"Found {len(result.get('messages', []))} {source} emails")
        except Exception as e:
            logger.error(f"Failed to fetch {source}: {e}")
    return messages


# ─── Parse ────────────────────────────────────────────────────────────────────

def parse_email(email_data: dict) -> list[dict]:
    """Extract article entries from a raw Gmail message."""
    source = email_data.get("_source", "unknown")
    html = _extract_html(email_data)
    if not html:
        logger.warning(f"No HTML found in {source} email")
        return []
    if source in ("tldr", "tldr_ai"):
        return _parse_tldr(html, source)
    elif source == "dailyfin":
        return _parse_dailyfin(html)
    return []


def _extract_html(email_data: dict) -> str | None:
    """Recursively walk MIME parts to find text/html body."""
    def walk(part):
        if part.get("mimeType") == "text/html":
            data = part.get("body", {}).get("data", "")
            if data:
                return base64.urlsafe_b64decode(data).decode("utf-8", errors="replace")
        for sub in part.get("parts", []):
            result = walk(sub)
            if result:
                return result
        return None
    return walk(email_data.get("payload", {}))


def _parse_tldr(html: str, source: str) -> list[dict]:
    """TLDR uses h3 headings for article titles, followed by a paragraph snippet."""
    soup = BeautifulSoup(html, "lxml")
    articles = []
    for tag in soup.find_all(["h3", "h2"]):
        title = tag.get_text(strip=True)
        if len(title) < 10:
            continue
        snippet_tag = tag.find_next("p")
        snippet = snippet_tag.get_text(strip=True)[:500] if snippet_tag else ""
        link = tag.find("a") or tag.find_next("a")
        url = link.get("href", "") if link else ""
        if title and snippet:
            articles.append({"title": title, "snippet": snippet, "source": source, "url": url})
    logger.info(f"Parsed {len(articles)} articles from {source}")
    return articles


def _parse_dailyfin(html: str) -> list[dict]:
    """DailyFin uses bold/strong tags for Portuguese finance article titles."""
    soup = BeautifulSoup(html, "lxml")
    articles, seen = [], set()
    for tag in soup.find_all(["strong", "b", "h3", "h2"]):
        title = tag.get_text(strip=True)
        if len(title) < 10 or title in seen:
            continue
        seen.add(title)
        snippet_tag = tag.find_next("p")
        snippet = snippet_tag.get_text(strip=True)[:500] if snippet_tag else ""
        link = tag.find("a") or tag.find_next("a")
        url = link.get("href", "") if link else ""
        if title and snippet:
            articles.append({"title": title, "snippet": snippet, "source": "dailyfin", "url": url})
    logger.info(f"Parsed {len(articles)} articles from dailyfin")
    return articles


# ─── Mark as read ─────────────────────────────────────────────────────────────

def mark_as_read(service, message_id: str):
    """Remove UNREAD label so this email won't be fetched again."""
    try:
        service.users().messages().modify(
            userId="me", id=message_id, body={"removeLabelIds": ["UNREAD"]}
        ).execute()
        logger.info(f"Marked {message_id} as read")
    except Exception as e:
        logger.error(f"Failed to mark {message_id} as read: {e}")
