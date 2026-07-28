// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:js' as js;

import 'twilio_platform_contract.dart';

TwilioPlatform createTwilioPlatform() => _WebTwilioPlatform();

class _WebTwilioPlatform implements TwilioPlatform {
  Future<T> _promise<T>(String function, List<Object?> arguments) {
    final completer = Completer<T>();
    final promise = js.context.callMethod<Object?>(function, arguments) as js.JsObject;
    promise.callMethod<Object?>('then', [
      js.allowInterop((Object? value) {
        if (!completer.isCompleted) completer.complete(value as T);
      })
    ]);
    promise.callMethod<Object?>('catch', [
      js.allowInterop((Object? error) {
        if (!completer.isCompleted) completer.completeError(error ?? 'Unknown Twilio error');
      })
    ]);
    return completer.future;
  }

  @override
  Future<void> initialize(String tokenUrl, TwilioStateCallback onState,
      TwilioErrorCallback onError) async {
    await _promise<Object?>('powerlineTwilioInitialize', [
      tokenUrl,
      js.allowInterop(onState),
      js.allowInterop(onError),
    ]);
  }

  @override
  Future<String> placeCall(String destination) =>
      _promise<String>('powerlineTwilioPlaceCall', [destination]);

  @override
  void hangup() => js.context.callMethod<void>('powerlineTwilioHangup');
  @override
  void mute(bool muted) => js.context.callMethod<void>('powerlineTwilioMute', [muted]);
  @override
  void sendDigits(String digits) =>
      js.context.callMethod<void>('powerlineTwilioSendDigits', [digits]);
  @override
  void dispose() => js.context.callMethod<void>('powerlineTwilioDispose');
}
