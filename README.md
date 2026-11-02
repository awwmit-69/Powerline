# Powerline

Powerline is AZD Global's cross-platform communications workspace. This
repository includes a deterministic preview and an authenticated Twilio workspace
for web, with a browser handoff from Windows. The live service is not deployed or
verified against a real telephone line.

## Current status

- Dashboard, dialpad, messages, calls, voicemail, contacts, campaigns, agents,
  analytics, settings, and provider configuration screens are available with
  fictional local demo data.
- The default preview uses simulated calls and messages. The separate `/live`
  workspace uses server APIs and fails closed when private sign-in, provider
  configuration or number permissions are missing.
- `/live` implements manual Twilio browser calling, incoming call controls,
  two-way SMS storage/status synchronization and team-number permissions.
  Live provider traffic remains disabled and unverified. Native Windows audio,
  emergency calling and CRM synchronization are not implemented.
- See [PRODUCTION_STATUS.md](PRODUCTION_STATUS.md) for builds, provisioned account
  slots, activation blockers and test evidence.
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
