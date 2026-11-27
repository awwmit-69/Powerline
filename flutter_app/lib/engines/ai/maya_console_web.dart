// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;

import 'maya_console.dart';

MayaConsole createMayaConsole() => _WebMayaConsole();

class _WebMayaConsole implements MayaConsole {
  @override
  bool get available =>
      mayaTokenUrl.isNotEmpty && js.context.hasProperty('powerlineConsole');

  Future<Object?> _promise(String function, List<Object?> arguments) {
    final completer = Completer<Object?>();
    final promise = js.context.callMethod(function, arguments) as js.JsObject;
    promise.callMethod('then', [
      js.JsFunction.withThis((Object? _, Object? value) {
        if (!completer.isCompleted) completer.complete(value);
      }),
    ]);
    promise.callMethod('catch', [
      js.JsFunction.withThis((Object? _, Object? error) {
        if (completer.isCompleted) return;
        final message = error is js.JsObject
            ? (error['message'] ?? error).toString()
            : (error ?? 'Request failed').toString();
        completer.completeError(Exception(message));
      }),
    ]);
    return completer.future;
  }

  @override
  Future<Map<String, dynamic>> run(
    String action, [
    Map<String, String> fields = const {},
  ]) async {
    final raw = await _promise('powerlineConsole', [
      jsonEncode({...fields, 'action': action}),
      mayaTokenUrl,
    ]);
    return jsonDecode(raw.toString()) as Map<String, dynamic>;
  }

  @override
  Future<String> audioUrl(String action, Map<String, String> fields) async {
    final url = await _promise('powerlineConsoleAudio', [
      jsonEncode({...fields, 'action': action}),
      mayaTokenUrl,
    ]);
    return url.toString();
  }
}
