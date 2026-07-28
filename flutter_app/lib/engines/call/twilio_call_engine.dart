import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/enums.dart';
import 'call_engine.dart';
import 'twilio_platform.dart';
import 'twilio_platform_contract.dart';

class TwilioCallEngine implements CallEngine {
  static const tokenUrl = 'https://powerline-voice-2020.twil.io/token';

  final TwilioPlatform _platform;
  final _stateController = StreamController<ActiveCallSnapshot>.broadcast();
  final _errorController = StreamController<CallEngineError>.broadcast();
  final Map<String, ActiveCallSnapshot> _calls = {};
  bool _initialized = false;

  TwilioCallEngine({TwilioPlatform? platform})
      : _platform = platform ?? createTwilioPlatform();

  @override
  String get providerId => 'twilio';

  @override
  EngineStatus get status => EngineStatus(
        provider: 'Twilio Voice',
        mockMode: false,
        connected: kIsWeb && _initialized,
        missingConfiguration:
            kIsWeb ? const [] : const ['PowerLine Web is required'],
        unsupportedCapabilities: const [
          'hold',
          'transfer',
          'conference',
          'browser recording',
          'E911',
        ],
      );

  @override
  Stream<ActiveCallSnapshot> get callStates => _stateController.stream;
  @override
  Stream<CallEngineError> get errors => _errorController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _platform.initialize(tokenUrl, _onState, (message) {
      _errorController.add(CallEngineError('twilio', message));
    });
    _initialized = true;
  }

  @override
  Future<String> placeCall(String toE164, {String? fromNumberId}) async {
    await initialize();
    final callId = await _platform.placeCall(toE164);
    final snapshot = ActiveCallSnapshot(
      callId: callId,
      remoteE164: toE164,
      direction: CallDirection.outbound,
      state: CallState.dialing,
      startedAt: DateTime.now(),
    );
    _calls[callId] = snapshot;
    scheduleMicrotask(() => _stateController.add(snapshot));
    return callId;
  }

  void _onState(String state, String callId) {
    final current = _calls[callId];
    if (current == null) return;
    final next = switch (state) {
      'ringing' => CallState.ringing,
      'connected' => CallState.connected,
      'completed' => CallState.completed,
      _ => CallState.failed,
    };
    final updated = current.copyWith(
      state: next,
      connectedAt: next == CallState.connected ? DateTime.now() : null,
    );
    _calls[callId] = updated;
    _stateController.add(updated);
  }

  ActiveCallSnapshot _require(String callId) {
    final call = _calls[callId];
    if (call == null) throw StateError('Unknown Twilio call $callId');
    return call;
  }

  @override
  Future<void> endCall(String callId) async {
    _require(callId);
    _platform.hangup();
  }

  @override
  Future<void> mute(String callId) async {
    final call = _require(callId).copyWith(muted: true);
    _calls[callId] = call;
    _platform.mute(true);
    _stateController.add(call);
  }

  @override
  Future<void> unmute(String callId) async {
    final call = _require(callId).copyWith(muted: false);
    _calls[callId] = call;
    _platform.mute(false);
    _stateController.add(call);
  }

  @override
  Future<void> sendDtmf(String callId, String digits) async {
    _require(callId);
    _platform.sendDigits(digits);
  }

  @override
  Future<void> acceptCall(String callId) async =>
      throw UnsupportedError('Incoming Twilio calls are not enabled yet.');
  @override
  Future<void> rejectCall(String callId) async =>
      throw UnsupportedError('Incoming Twilio calls are not enabled yet.');
  @override
  Future<void> hold(String callId) async =>
      throw UnsupportedError('Hold is not enabled for Twilio Web.');
  @override
  Future<void> resume(String callId) async =>
      throw UnsupportedError('Hold is not enabled for Twilio Web.');
  @override
  Future<void> transfer(String callId, String toDestination) async =>
      throw UnsupportedError('Transfer is not enabled for this trial.');
  @override
  Future<void> conference(String callId, String participantE164) async =>
      throw UnsupportedError('Conference is not enabled for this trial.');
  @override
  Future<void> startRecording(String callId) async =>
      throw UnsupportedError('Browser recording is not enabled.');
  @override
  Future<void> stopRecording(String callId) async =>
      throw UnsupportedError('Browser recording is not enabled.');

  @override
  Future<void> dispose() async {
    _platform.dispose();
    await _stateController.close();
    await _errorController.close();
  }
}
