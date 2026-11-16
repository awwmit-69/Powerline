# PowerLine Twilio configuration (new account)

PowerLine must use the **new active Twilio account**, not any historic trial
account or hard-coded `*.twil.io` URL. Configure these values in **protected
server-side environment variables** (never in GitHub, Flutter web code, a
`--dart-define`, or a shared screenshot):

| Variable | Purpose |
| --- | --- |
| `TWILIO_ACCOUNT_SID` | New account SID (starts `AC`) |
| `TWILIO_API_KEY_SID` | API Key SID for this account (starts `SK`) |
| `TWILIO_API_KEY_SECRET` | API Key secret; store only on server |
| `POWERLINE_FROM_NUMBER` | Purchased Twilio DID in E.164 (`+1...`) |
| `TWIML_APP_SID` | Voice TwiML Application SID (starts `AP`) |
| `ELEVENLABS_API_KEY` | Optional, for TTS features only |
| `ELEVENLABS_VOICE_ID` | Optional private voice identifier |

Use Twilio Console to verify the purchased number has **Voice** and, if SMS is
planned, **SMS** capabilities. The new account must have its own TwiML App,
phone-number webhook configuration, credentials, and approved messaging setup.
Never reuse credentials from a suspended or prior account.

## What must be deployed before live calling

1. A backend requiring authenticated PowerLine agent sessions and authorization.
2. A short-lived Twilio Voice Access Token endpoint which uses the new account's
   SID, API Key SID/secret, and TwiML App SID. Validate the signed-in agent and
   restrict the identity and TTL; add rate limits.
3. An outbound voice TwiML webhook that validates the Twilio request, validates
   dialed destinations, applies agent and account call permissions, and uses the
   purchased number as caller ID.
4. Inbound voice and inbound messaging webhooks for the purchased DID, with
   Twilio signature validation, storage, and routing to the signed-in agent.
5. A separate authenticated SMS backend enforcing consent, suppression/STOP,
   allowed destinations, rate limits, and delivery tracking. Register applicable
   US messaging traffic (for example A2P 10DLC) before outbound campaigns.
6. End-to-end tests for browser microphone permissions, two-way audio,
   inbound/outbound calls, SMS opt-out handling, and delivery status.

The Flutter app's nonsecret endpoint addresses are configured using
`POWERLINE_VOICE_TOKEN_URL` and `POWERLINE_SMS_URL` on the readiness branch.
They must point to **authenticated endpoints**. Simply adding these URLs does
not make live calling or texting functional.

**Important:** The repository intentionally does not contain account-specific
identifiers, secrets, phone numbers, voice recordings, or private voice IDs.
