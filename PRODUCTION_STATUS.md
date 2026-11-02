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

41 local backend/browser-bridge tests passed, including password sessions,
logout/revocation, login throttles, CSRF, private asset gates, encrypted provider
storage, trial recipient enforcement, SMS and voice controls with mock providers.
Updated Flutter checks and web/Windows builds run in Actions. Earlier app builds
passed; authenticated browser rendering is not a telephone acceptance test.

The cloud browser available to the agent rejected this hostname at the environment
network boundary. This was not a site CAPTCHA or bot-detection finding. Separate
HTTPS and deployed-runtime checks are used where available; their outcomes must
be recorded before claiming sign-in has been verified remotely.

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
