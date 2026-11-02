// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;

import 'live_client.dart';

LiveClient createClient() => _BrowserClient();

class _BrowserClient implements LiveClient {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  bool _disposed = false;

  Future<Object?> _invoke(String name, List<Object?> values) {
    final result = Completer<Object?>();
    try {
      final promise = js.context.callMethod(name, values) as js.JsObject;
      promise.callMethod('then', [
        js.JsFunction.withThis((Object? _, Object? value) {
          if (!result.isCompleted) result.complete(value);
        }),
      ]);
      promise.callMethod('catch', [
        js.JsFunction.withThis((Object? _, Object? error) {
          if (!result.isCompleted) {
            result.completeError(StateError(error.toString()));
          }
        }),
      ]);
    } catch (error) {
      result.completeError(error);
    }
    return result.future;
  }

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final value = await _invoke('powerlineLiveRequest', [
      method,
      path,
      body == null ? null : jsonEncode(body),
    ]);
    return jsonDecode(value.toString()) as Map<String, dynamic>;
  }

  @override
  Future<void> initialize() async {
    await _invoke('powerlineLiveInitialize', [
      js.JsFunction.withThis((Object? _, Object? value) {
        if (!_disposed) {
          _events.add(jsonDecode(value.toString()) as Map<String, dynamic>);
        }
      }),
    ]);
  }

  @override
  Future<void> call(String numberId, String to) async {
    await _invoke('powerlineLiveCall', [numberId, to]);
  }

  @override
  void control(String action, [Object? value]) {
    const names = {
      'answer': 'powerlineLiveAnswer',
      'reject': 'powerlineLiveReject',
      'hangup': 'powerlineLiveHangup',
      'mute': 'powerlineLiveMute',
      'digits': 'powerlineLiveDigits',
    };
    final function = names[action];
    if (function == null) throw ArgumentError('Unknown call control');
    js.context.callMethod(function, value == null ? [] : [value]);
  }

  @override
  void dispose() {
    _disposed = true;
    js.context.callMethod('powerlineLiveDispose');
    _events.close();
  }
}
