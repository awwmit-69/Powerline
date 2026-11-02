import 'dart:async';

import 'live_client_stub.dart' if (dart.library.html) 'live_client_web.dart'
    as implementation;

abstract class LiveClient {
  Stream<Map<String, dynamic>> get events;
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]);
  Future<void> initialize();
  Future<void> call(String numberId, String to);
  void control(String action, [Object? value]);
  void dispose();
}

LiveClient createLiveClient() => implementation.createClient();
