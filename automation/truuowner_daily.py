#!/usr/bin/env python3
"""Create one reviewable TruuOwner marketing pack with Claude. Never sends outreach."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

API_URL = "https://api.anthropic.com/v1/messages"
DEFAULT_MODEL = "claude-sonnet-4-6"

SYSTEM = """You are a careful B2B marketing assistant for TruuOwner, a homeowner-data
product for legitimate business buyers. Generate clear, useful draft marketing.
Never invent verified coverage, price, sample size, deliverability, accuracy,
testimonials, customer consent, or delivery times. Use placeholders for unknowns.
Do not generate scraped prospect lists, unsolicited mass-contact instructions,
deceptive impersonation, or pressure tactics. No claims that purchasing a
homeowner dataset confers consent to contact homeowners.
Only draft outreach for existing clients or contacts with independently
documented marketing permission. State opt-out choices where appropriate.
Output Markdown, not JSON. The drafts must await human review."""

def make_prompt(day):
    return f"""Generate a daily marketing pack dated {day} for TruuOwner.
Known context: B2B homeowner-data service, targeting businesses that buy
location-specific homeowner datasets; geographic coverage and quality are
NOT verified here. No confirmed price or current inventory. Do not invent them.
Goal: produce genuinely usable materials for an operator to review, not pretend
sales happened. Include:
1. One short positioning paragraph and landing-page headline with a CTA.
2. Three distinct organic social posts that do not promise unverified results.
3. Two concise permission-based B2B email drafts to prior customers or opted-in
prospects, with a clear opt-out sentence.
4. One reply template for someone who requests a sample.
5. One opt-in callback outline for a human representative; do not automatically
dial anyone.
6. A 5-step work queue with measurable but non-fabricated metrics.
7. Questions to verify before publishing (coverage, fields, privacy, terms).
Avoid numerical discounts and fabricated deadlines. Format with headings."""

def extract_text(response):
    blocks = response.get("content", [])
    return "\n\n".join(
        block.get("text", "").strip()
        for block in blocks
        if block.get("type") == "text" and block.get("text", "").strip()
    ).strip()

def generate(key, day, model=DEFAULT_MODEL):
    payload = {
        "model": model,
        "max_tokens": 2400,
        "system": SYSTEM,
        "messages": [{"role": "user", "content": make_prompt(day)}],
    }
    request = Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2026-10-21",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=90) as response:
            result = json.load(response)
    except HTTPError as exc:
        # Never print the API key or request headers.
        raise RuntimeError(f"Claude API returned HTTP {exc.code}") from exc
    except URLError as exc:
        raise RuntimeError(f"Claude API could not be reached: {exc.reason}") from exc
    body = extract_text(result)
    if len(body) < 100:
        raise RuntimeError("Claude returned an empty or unusually short marketing pack")
    return body

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="marketing-output")
    parser.add_argument("--date", default=None)
    args = parser.parse_args()
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        parser.error("ANTHROPIC_API_KEY is required; no content was generated")
    day = args.date or dt.datetime.now(ZoneInfo("America/New_York")).date().isoformat()
    # Only date-like strings are permitted in filenames.
    try:
        dt.date.fromisoformat(day)
    except ValueError as exc:
        parser.error(f"--date must be YYYY-MM-DD: {exc}")
    model = os.environ.get("TRUUOWNER_CLAUDE_MODEL") or DEFAULT_MODEL
    content = generate(key, day, model)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    target = out / f"truuowner-{day}.md"
    target.write_text(
        f"# TruuOwner daily marketing drafts | {day}\n\n"
        "**DRAFT ONLY. Not sent or published.** Verify every claim and review "
        "privacy, permission, and opt-out requirements before use.\n\n"
        + content + "\n", encoding="utf-8"
    )
    print(f"Created {target} (draft only, no messages sent)")

if __name__ == "__main__":
    main()
