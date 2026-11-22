import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/enums.dart';
import 'call_engine.dart';
import 'twilio_platform.dart';
import 'twilio_platform_contract.dart';

class TwilioCallEngine implements CallEngine {
  static const tokenUrl = String.fromEnvironment('POWERLINE_VOICE_TOKEN_URL');
  static const callerId = String.fromEnvironment('POWERLINE_CALLER_ID');

  final TwilioPlatform _platform;
  final _stateController = StreamController<ActiveCallSnapshot>.broadcast();
  final _errorController = StreamController<CallEngineError>.broadcast();
  final _incomingController = StreamController<ActiveCallSnapshot>.broadcast();
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
        connected: kIsWeb && _initialized && tokenUrl.isNotEmpty,
        missingConfiguration: !kIsWeb
            ? const ['PowerLine Web is required']
            : tokenUrl.isEmpty
                ? const ['POWERLINE_VOICE_TOKEN_URL is not configured']
                : const [],
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

  /// Inbound calls ringing this signed-in browser.
  Stream<ActiveCallSnapshot> get incomingCalls => _incomingController.stream;

  bool get isOnline => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (tokenUrl.isEmpty) {
      throw StateError(
        'Configure POWERLINE_VOICE_TOKEN_URL before enabling live calls.',
      );
    }
    await _platform.initialize(
      tokenUrl,
      _onState,
      (message) => _errorController.add(CallEngineError('twilio', message)),
      _onIncoming,
    );
    _initialized = true;
  }

  /// Goes online automatically when this browser is already signed in,
  /// so inbound calls ring without any clicks (like a desk phone).
  Future<void> resumeIfSignedIn() async {
    if (!kIsWeb || tokenUrl.isEmpty || _initialized) return;
    try {
      if (!_platform.hasSavedSession()) return;
      await initialize();
    } catch (error) {
      _errorController.add(CallEngineError('twilio', error.toString()));
    }
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

  /// Server dials [toE164] and the AI agent (Maya) talks to the lead.
  /// The consent dialog runs in the browser before anything is dialed.
  Future<String> startAiCall(String toE164) {
    if (!kIsWeb || tokenUrl.isEmpty) {
      throw StateError(
          'AI calls need the PowerLine web app with Twilio set up.');
    }
    return _platform.aiCall(toE164, tokenUrl);
  }

  void _onIncoming(String callId, String from) {
    final snapshot = ActiveCallSnapshot(
      callId: callId,
      remoteE164: from,
      direction: CallDirection.inbound,
      state: CallState.ringing,
      startedAt: DateTime.now(),
    );
    _calls[callId] = snapshot;
    _incomingController.add(snapshot);
    _stateController.add(snapshot);
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
  Future<void> acceptCall(String callId) async {
    _require(callId);
    _platform.accept(callId);
  }

  @override
  Future<void> rejectCall(String callId) async {
    _require(callId);
    _platform.reject(callId);
  }

  /// Signs the agent out and stops ringing this browser.
  void signOut() {
    _platform.signOut();
    _initialized = false;
  }

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
    await _incomingController.close();
  }
}
