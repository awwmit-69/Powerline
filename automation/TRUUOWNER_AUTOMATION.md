# TruuOwner: daily Claude marketing packs

This is a **draft generator**, not a live campaign sender. It generates fresh
TruuOwner copy using Claude once daily, saving a dated Markdown pack under a
GitHub Actions artifact. It never calls, texts, emails, scrapes, or imports leads.

## Setup after this branch is merged into main

1. In GitHub repository **Settings > Secrets and variables > Actions**, add an
   **Actions secret** named \`ANTHROPIC_API_KEY\`. Use a Claude API key, never put
   it in this repository, chat, workflow YAML, or an issue.
2. Optionally set an Actions **variable** \`TRUUOWNER_CLAUDE_MODEL\` to an
   accessible Anthropic model ID. Defaults to \`claude-sonnet-4-6\`.
3. Open **Actions > TruuOwner daily Claude marketing drafts > Run workflow**
   to test manually. Review the downloadable campaign-pack artifact.
4. After merging, GitHub Actions schedules the workflow daily at **9:17 AM
   America/New_York**, including daylight-saving changes. Scheduled jobs may
   start late. GitHub schedules run from the repository's default branch.
5. Review claims about pricing, data availability, sourcing, permissions,
   privacy notices, and fulfillment before publishing anything.

Cost: Claude API calls are billed separately from ChatGPT or Claude chat plans.
Missing credentials cause the job to fail without pretending content was made.

## Roadmap for actual outreach

* Phase 1 (this change): automatic draft production + reviewable output.
* Phase 2: connect a permission-verified CRM export and suppress unsubscribed,
  invalid, disputed, or unverified contacts. Keep outreach approval-gated.
* Phase 3: integrate a legitimate sending provider for approved recipients and
  an opt-in AI callback service. Record permissions, opt-outs, delivery outcomes,
  and replies. Comply with applicable telemarketing, privacy, consent, and
  recording rules. Buying a dataset does not imply contact consent.

## Run locally

Python 3.12+ and an API key:
\`\`\`bash
export ANTHROPIC_API_KEY="your-key-in-your-own-terminal"
python -m unittest discover -s automation -p 'test_*.py'
python automation/truuowner_daily.py --out marketing-output
\`\`\`

Never commit the key or generated prospect data.
