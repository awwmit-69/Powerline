# PowerLine production status

## Release gate: NOT READY

This branch preserves the Flutter application and adds a security foundation. It
does not finish the production phone system. No calls, SMS, purchases, DNS changes,
provider configuration changes, or production deployments were made in this work.

## Implemented

- Retire the legacy unauthenticated Twilio SMS function with HTTP 410 and no CORS.
  This closes the source vulnerability only. The replacement must also be deployed
  to the existing Twilio Function; repository changes do not secure a running copy.
- Remove automatic use of the public hardcoded voice token and SMS endpoints.
  Compile-time POWERLINE_TOKEN_URL and POWERLINE_SMS_URL default to disabled.
- Require HTTPS and same-origin access for browser SMS. Add a random request key.
- Stop treating provider acceptance as delivery; live messaging is not reported
  connected before verification. The existing UI still needs receipt synchronization.
- Add a Cloudflare Worker backend with RS256 Cloudflare Access JWT verification,
  exact issuer/audience/expiry checks, invited-user lookup, active-user enforcement,
  admin/agent roles, per-number read/send permissions and no cross-origin CORS.
- Add a D1 schema for users, numbers, permissions, messages, suppressions, audit
  events, durable rate limits and duplicate-send claims.
- Add signed Twilio inbound SMS and delivery-status webhooks with account checks,
  persistent STOP suppression and duplicate inbound-message protection.
- Add authenticated session, number listing and per-number message APIs. SMS send
  is disabled unless TELECOM_ENABLED is explicitly true and secrets are present.
- Add tests using real SQLite and a mock provider; no paid traffic is generated.

## Test results

21 Node tests passed locally: JWT validation/rejection, signature validation,
legacy endpoint retirement, ACL isolation, unknown-user rejection, disabled
traffic, suppression enforcement, SMS persistence, send deduplication and inbound
STOP retry behavior. CI runs the same suite on Node 24.

Flutter and Dart SDKs are unavailable in the execution container. Existing GitHub
Actions remain responsible for formatting, analysis, Flutter tests, web and Windows
builds. Build and CI results must be reviewed before merge. No live acceptance
tests, browser audio checks, Windows runtime tests or deployed-auth tests passed.

## Infrastructure inspection

The connected Cloudflare account has active azdglobal.com and existing AZD Global
Workers/Pages/D1 resources. No PowerLine Worker/Pages deployment was found.
Cloudflare reports Access is not enabled for the account. The business website,
its routes, DNS and database were left untouched.

GitHub connector read/write access works. Direct Git cloning is denied by the
execution network. Current relevant source and recent commit metadata were read
through GitHub. A complete historical credential audit has NOT been performed;
no assertion that Git history is secret-free is made.

## Remaining engineering

- Protected voice-token issuance, authorized outgoing TwiML, incoming call routing,
  browser registration/answer/reject, provider call history and reconnect handling.
- Server-backed frontend repository and message synchronization, delivery receipts,
  contact import/export/sync, voicemail, routing and multi-user administration.
- A durable outbox/reconciliation path for ambiguous sends. A pending send claim
  deliberately blocks automatic retries, but no reconciliation UI exists yet.
- Delivery callbacks are persisted before updating messages, including callbacks
  that arrive before the outbound insert. Provider reconciliation is still needed
  for ambiguous network responses and failed database writes after sending.
- Rate-limit/attempt/audit retention cleanup and user-facing retention controls.
- SignalMash/VoIP.ms adapters. Published pricing and integration constraints are in PROVIDERS.md; account-specific quotes remain unverified.
- Deployment automation, private Flutter build, full security review and acceptance.

## Configuration needed before private deployment and live tests

1. Enable an appropriate private identity system. For this Worker, configure
   Cloudflare Access and its exact allowed owner identity, issuer and audience.
2. Create a dedicated PowerLine D1 database, apply backend/schema.sql, and bind DB.
   Provision the verified owner in users; explicitly assign authorized numbers.
3. Obtain Twilio account ownership/configuration through a protected workflow.
   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and later voice API key credentials must
   be stored as Worker secrets, never in Flutter, GitHub source or chat text.
4. Configure the provider webhooks at the exact PUBLIC_ORIGIN paths, with POST form
   encoding. App APIs need Access; provider webhooks need signature validation
   without an interactive Access login. The Worker verifies every webhook itself.
5. Deploy the legacy Function retirement separately using provider access.
6. Approve the exact usage cost and live test recipient before enabling traffic.

Do not set TELECOM_ENABLED=true until unfinished engineering and release checks
above have been completed. These tests demonstrate the implemented boundary,
not production readiness, emergency calling, carrier registration or consent.
