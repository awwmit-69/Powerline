# PowerLine deployed workspace

Login: https://powerline.azdglobal.com/login
Owner Twilio setup: https://powerline.azdglobal.com/setup/twilio

## Current authentication

Username/password sign-in is deployed. Email codes and a Cloudflare Zero Trust
organization are not required. Five accounts have independently generated random
usernames; each initial password equals its corresponding username, as requested.
The display IDs remain owner and agent01–agent04. All five are active; agents start
with no number assignments. Actual credentials are delivered privately and are not
committed to this public repository.

The server stores keyed username lookups, salted PBKDF2 password hashes and hashed
session tokens. Cookies are Secure, HttpOnly and SameSite=Strict. Login attempts
are limited by account and IP. The owner can manage per-number permissions.

## Twilio setup

The authenticated owner setup page accepts the Account SID and Auth Token over
HTTPS, verifies the account, lists existing numbers, creates browser voice keys
and a TwiML application, updates selected-number webhooks and assigns the line to
the owner. Provider credentials are encrypted in D1 using a Worker-secret-derived
key and are never returned to the browser. A number assigned to another app or
SIP trunk is not silently taken over. Configuration does not buy numbers, add
credit, send SMS or place calls.

The owner then chooses a test recipient and explicitly approves usage charges.
Trial recipients must be verified with Twilio. The current account type is checked
again when enabling tests so a paid upgrade is recognized. Test calls are capped
at 60 seconds and outgoing calls/SMS are limited to the chosen recipient.
Carrier and messaging registration restrictions may still block SMS.

No Twilio credentials were available during this work. No real call, two-way
audio or SMS delivery has been verified. No chargeable traffic was enabled by the
agent, and no payment or number purchase was made. The user's planned $20 payment
was not performed or assumed complete.

## Deployment and checks

A dedicated Worker, custom hostname and D1 database are provisioned. Private app
assets and APIs require a signed-in active account; the login page alone is public.
The five password credentials were provisioned to D1. Root secret material is held
in a Worker secret; it is absent from GitHub and the credential delivery file.

42 local backend/browser-bridge tests passed, including password sessions,
logout/revocation, login throttles, CSRF, private asset gates, encrypted provider
storage, trial recipient enforcement, SMS and voice controls with mock providers.
Updated Flutter checks and web/Windows builds run in Actions. Earlier app builds
passed; authenticated browser rendering is not a telephone acceptance test.

The deployed HTTPS runtime check passed owner/agent sign-in, private app and bundle
loading, owner setup access, agent denial from admin/provider pages, traffic-disabled
state and logout revocation. Temporary QA credentials and the schedule were removed.

The cloud browser is unavailable for visual inspection of this hostname. Separately,
external CI clients received Cloudflare managed-challenge HTML instead of app API
responses. The zone has Bot Fight Mode enabled. Cloudflare documents that free Bot
Fight Mode cannot be bypassed by per-path WAF/Page Rules. Changing that zone-wide
setting would also affect the business site and awaits the owner's approval.
WEBHOOK_EDGE_READY is false; changing number routing or enabling paid test traffic
is blocked until that edge conflict is resolved.

## Application scope

Manual browser calling, incoming answer/reject, mute, hang-up, DTMF, call history,
server-backed SMS, delivery status and number permissions are implemented.
Windows opens the authenticated browser workspace for voice; native Windows audio
is not implemented. Voicemail, recording, hold/transfer, campaign automation and
CRM synchronization remain incomplete. Emergency calling is unavailable.

Legacy public SMS/TTS functions are retired in source only; their deployed copies
still need separate provider-side updates. Ambiguous sends require reconciliation.
See PROVIDERS.md for published rates and limitations. The AZD Global website and
its routes were not changed.

## Latest build evidence

Flutter formatting, analysis, tests, private web, preview web and Windows builds
passed in workflow run 41489499422. The private web build from this run was packaged
and deployed to the authenticated Worker. No native Windows audio test or real
telephone call/SMS delivery passed.

Cloudflare references:
https://developers.cloudflare.com/bots/get-started/bot-fight-mode/
https://developers.cloudflare.com/bots/troubleshooting/false-positives/
