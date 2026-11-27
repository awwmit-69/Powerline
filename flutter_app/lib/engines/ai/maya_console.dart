/// Client for the server's /ai-console endpoint (Maya's calls, recordings,
/// bookings and call-flow script). Live on PowerLine Web, where the signed-in
/// agent session lives; other platforms report [MayaConsole.available] false.
library;

import 'maya_console_stub.dart'
    if (dart.library.html) 'maya_console_web.dart'
    as implementation;

const mayaTokenUrl = String.fromEnvironment('POWERLINE_VOICE_TOKEN_URL');

abstract class MayaConsole {
  bool get available;

  /// Runs one console action and returns its JSON body.
  Future<Map<String, dynamic>> run(
    String action, [
    Map<String, String> fields = const {},
  ]);

  /// Runs an audio action and returns a URL the audio player can play.
  Future<String> audioUrl(String action, Map<String, String> fields);
}

MayaConsole createMayaConsole() => implementation.createMayaConsole();
