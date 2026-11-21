# Powerline

Powerline is AZD Global's cross-platform communications workspace. This
repository currently ships a deterministic product preview for web and Windows.

## Current status

- Dashboard, dialpad, messages, calls, voicemail, contacts, campaigns, agents,
  analytics, settings, and provider configuration screens are available with
  fictional local demo data.
- Calls and messages are simulated. No live telecom traffic leaves the app.
- Provider cards describe required configuration, but production SIP/WebRTC,
  SMS, emergency calling, and CRM connectivity are not implemented.
- The app must not be represented as a production phone system until provider
  registration, inbound and outbound calls, two-way audio, call lifecycle, and
  reconnect behavior have been tested with a real provider.

## Run locally

Install the current stable Flutter SDK, then:

```bash
cd flutter_app
flutter pub get
flutter run
```

Run the quality gate with:

```bash
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

## Builds

Every pull request must pass formatting, analysis, and tests before web and
Windows builds run. Pushes to `main` also deploy the web preview to GitHub
Pages. Windows ZIPs are retained as workflow artifacts; tagged releases are
published deliberately rather than overwritten by every commit.

## Fonts

Manrope and JetBrains Mono are committed in `flutter_app/assets/fonts` for
reproducible builds. Their Open Font License texts are in
`flutter_app/assets/licenses`.

## Live provider readiness (not a production launch)

The preview remains in demo mode unless a supported live integration is explicitly selected and configured. The Flutter web build accepts these non-secret compile-time settings:

```bash
flutter build web --release --base-href /Powerline/ \
  --dart-define=POWERLINE_VOICE_TOKEN_URL=https://YOUR-API.example.com/voice/token \
  --dart-define=POWERLINE_SMS_URL=https://YOUR-API.example.com/sms
```

These addresses must point to **your authenticated, server-side endpoints**. Never embed Twilio auth tokens, API secrets, or provider credentials in Dart defines or browser code. The token endpoint must authenticate the signed-in agent, issue short-lived scoped voice tokens, and apply rate limits. The SMS endpoint must enforce login, permission checks, recipient opt-in, suppression/DNC checks, send limits, abuse controls, and server-side provider authentication. Configure the proper callback URLs and CORS policy on that backend. A public browser-callable unauthenticated SMS relay is unsafe and must never be deployed.

In the absence of these settings, the live voice and SMS integrations report missing configuration instead of presenting themselves as ready. A passing Flutter build is **not** a live call test. Validate provider activation, microphone permission, two-way audio, inbound routing, delivery receipts, STOP handling, and device reconnection before production use. The Twilio integration is web-only, and Android/iOS native calling still requires separate implementation and testing.
