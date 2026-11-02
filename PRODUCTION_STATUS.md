# PowerLine build and activation status

## Not activated for real telecom traffic

The existing Flutter application is retained. A new /live route provides the
server-backed communications workspace; preview screens remain separate from it.
No successful real call or SMS delivery is claimed. TELECOM_ENABLED remains false.

## Implemented in source

- Manual browser calls through the existing Twilio JavaScript SDK, incoming
  registration, answer/reject, mute/unmute, hang-up, DTMF, call state and duration.
- Short-lived server-signed Twilio voice tokens. Outbound calls require a 60-second
  single-use intent bound to the authenticated user, assigned number and destination.
  TwiML selects caller ID from server permissions, never a client-provided identity.
- Signed Twilio outgoing/incoming/status routes, server call history, per-number
  inbound routing and status aggregation when multiple agents ring.
- Authenticated SMS sending, incoming replies, delivery callbacks, server history
  polling, opt-out persistence, send limits, duplicate-attempt protection and audit
  records. Provider acceptance is displayed separately from delivery.
- Five team account slots and admin email/line-permission management. Agents cannot
  read a line until assigned to it. Inactive accounts fail closed.
- An authenticated asset-serving Worker configuration and a separate root-path
  production web artifact. Preview publishing remains limited to main.
- The Windows app links to the protected browser calling workspace. Browser audio
  can run in Edge/Chrome or an installed web app. Native Windows Twilio audio is
  **not implemented** and must not be represented as working.

## Provisioned resources

A dedicated Cloudflare D1 database, powerline-db, was created and initialized with
the SMS and voice schemas. It is separate from the AZD Global website database.
Five account records were verified in D1:

| ID | Role | State |
| --- | --- | --- |
| owner | Administrator | Owner email assigned; authentication activation blocked |
| agent01 | Agent | Disabled until an individual email is assigned |
| agent02 | Agent | Disabled until an individual email is assigned |
| agent03 | Agent | Disabled until an individual email is assigned |
| agent04 | Agent | Disabled until an individual email is assigned |

These are account records, not five working authenticated sessions. No shared
password or fabricated email login was activated. The owner email is held in the
private database, not seeded into public source.

## Automated verification

32 local backend/browser-bridge tests pass, covering sessions, webhook signatures,
ACL isolation, SMS persistence/opt-outs/delivery ordering, duplicate-send protection,
voice token signatures, caller-ID enforcement, single-use grants, DNC restrictions,
inbound routing, multi-agent call status and SDK call controls with a mock provider.
These are not real telephone-network or two-way audio acceptance tests.

The repository formatter has formatted the new Dart workspace. Updated Flutter
analysis, tests and browser/Windows release builds run in GitHub Actions. Inspect
their final results before merging this source into a release.

The previous full-history pattern scan inspected 297 reachable text blobs with no
matches for its selected credential rules and skipped 14 binary/large blobs. This
does not establish that every historical secret is absent.

## Confirmed activation blockers

1. Cloudflare Access is not enabled. Automatic approval review rejected creating
   the account-level Zero Trust organization, requesting explicit approval for
   that exact persistent authentication resource. No alternate route was used to
   bypass that rejection. No Access organization or application was created.
2. The protected GitHub Twilio preflight found all six configured values absent:
   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_API_KEY_SID,
   TWILIO_API_KEY_SECRET, TWIML_APP_SID and POWERLINE_FROM_NUMBER. Provider account
   access could not be verified. No secret values were printed in logs.
3. No owned Twilio number has been imported into D1. Number ownership, capabilities,
   messaging registration and signed webhook configuration require provider access.
4. Four individual agent login emails are not yet supplied. Their slots remain
   disabled. Identity-provider policy must permit the authorized team as well as
   the owner; database activation alone is insufficient.
5. Live testing needs an approved destination and usage budget. Outbound voice is
   limited to TEST_DESTINATIONS unless unrestricted calling is explicitly enabled.
   Calls are capped at ten minutes in TwiML. No paid traffic or number purchase
   has been initiated.

## Remaining limitations

Private deployment, owner sign-in, live Twilio routing, two-way audio, real SMS
delivery, browser microphone behavior and Windows runtime calling are unverified.
Voicemail, recording, hold, transfer, native Windows audio, CRM synchronization and
campaign automation are not completed in this build. Emergency calling is unavailable.

Public legacy SMS and TTS Functions are retired in source only. Running provider
copies still require a separate update through protected Twilio access. Failed or
ambiguous provider sends need operator reconciliation; automatic retries are blocked.
Retention controls and a comprehensive manual security review remain release gates.

Provider pricing and cost estimates are in PROVIDERS.md. Nothing changed the AZD
Global website, its DNS routes, Facebook or other external business systems.
