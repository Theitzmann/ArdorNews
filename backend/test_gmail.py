# test_gmail.py — Quick script to verify Gmail OAuth works and newsletters are visible
# Run: python test_gmail.py
# Expected output: count of unread TLDR, TLDR AI, and DailyFin emails

from gmail_fetcher import authenticate, fetch_newsletters, parse_email
import logging
logging.basicConfig(level=logging.INFO)

service = authenticate()
emails = fetch_newsletters(service)
print(f"\nFound {len(emails)} unread newsletter emails\n")

for email in emails:
    source = email.get("_source", "unknown")
    subject = next(
        (h["value"] for h in email["payload"]["headers"] if h["name"] == "Subject"),
        "No subject",
    )
    print(f"  [{source}] {subject}")
    articles = parse_email(email)
    print(f"    → parsed {len(articles)} articles")
    for a in articles[:2]:
        print(f"       • {a['title'][:80]}")
    print()
