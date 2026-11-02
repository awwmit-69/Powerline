import 'dart:async';

import 'live_client.dart';

LiveClient createClient() => _Unsupported();

class _Unsupported implements LiveClient {
  Never _blocked() => throw UnsupportedError(
        'Open the protected browser workspace for Twilio audio.',
      );
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async =>
      _blocked();
  @override
  Future<void> initialize() async => _blocked();
  @override
  Future<void> call(String numberId, String to) async => _blocked();
  @override
  void control(String action, [Object? value]) => _blocked();
  @override
  void dispose() {}
}
