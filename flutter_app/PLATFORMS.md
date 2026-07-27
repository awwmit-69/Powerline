# Platform folders

These folders (`android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`)
contain declarative project structure: manifests, entitlements/Info.plist,
Gradle config, CMake stubs, and platform entrypoints with the app identity
`com.azdglobal.powerline` and display name **Powerline**.

They were authored by hand in a Linux sandbox WITHOUT the Flutter SDK (pub.dev
is network-blocked here), so the ephemeral generated files (`.dart_tool/`,
`Generated.xcconfig`, `GeneratedPluginRegistrant`, desktop runner boilerplate,
Gradle wrapper JARs) are NOT present.

To materialize fully runnable platform projects on a real host:

```
cd flutter_app
flutter create .          # regenerates ephemeral platform files, keeps lib/ and these manifests
flutter pub get
```

`flutter create .` is non-destructive to `lib/`, `test/`, `pubspec.yaml`, and
these hand-written manifests — it only fills in the generated glue.
