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
