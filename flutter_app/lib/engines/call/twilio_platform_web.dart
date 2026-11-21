// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:js' as js;

import 'twilio_platform_contract.dart';

TwilioPlatform createTwilioPlatform() => _WebTwilioPlatform();

class _WebTwilioPlatform implements TwilioPlatform {
  Future<Object?> _promise(String function, List<Object?> arguments) {
    final completer = Completer<Object?>();
    final promise = js.context.callMethod(function, arguments) as js.JsObject;
    promise.callMethod('then', [
      js.JsFunction.withThis((Object? _, Object? value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      }),
    ]);
    promise.callMethod('catch', [
      js.JsFunction.withThis((Object? _, Object? error) {
        if (!completer.isCompleted) {
          completer.completeError(error ?? 'Unknown Twilio error');
        }
      }),
    ]);
    return completer.future;
  }

  @override
  Future<void> initialize(
    String tokenUrl,
    TwilioStateCallback onState,
    TwilioErrorCallback onError,
    TwilioIncomingCallback onIncoming,
  ) async {
    await _promise('powerlineTwilioInitialize', [
      tokenUrl,
      js.JsFunction.withThis(
        (Object? _, Object? state, Object? callId) =>
            onState(state.toString(), callId.toString()),
      ),
      js.JsFunction.withThis(
        (Object? _, Object? message) => onError(message.toString()),
      ),
      js.JsFunction.withThis(
        (Object? _, Object? callId, Object? from) =>
            onIncoming(callId.toString(), from.toString()),
      ),
    ]);
  }

  @override
  bool hasSavedSession() =>
      js.context.callMethod('powerlineTwilioHasSession') == true;

  @override
  Future<String> placeCall(String destination) async {
    final callId = await _promise('powerlineTwilioPlaceCall', [destination]);
    return callId.toString();
  }

  @override
  void accept(String callId) =>
      js.context.callMethod('powerlineTwilioAccept', [callId]);
  @override
  void reject(String callId) =>
      js.context.callMethod('powerlineTwilioReject', [callId]);
  @override
  void hangup() => js.context.callMethod('powerlineTwilioHangup');
  @override
  void mute(bool muted) =>
      js.context.callMethod('powerlineTwilioMute', [muted]);
  @override
  void sendDigits(String digits) =>
      js.context.callMethod('powerlineTwilioSendDigits', [digits]);
  @override
  void signOut() => js.context.callMethod('powerlineTwilioSignOut');
  @override
  void dispose() => js.context.callMethod('powerlineTwilioDispose');
}
