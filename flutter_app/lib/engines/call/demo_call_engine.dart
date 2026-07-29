/// DemoCallEngine — honest, fully local call simulation.
///
/// No audio leaves the device; no external recipient is ever contacted.
/// The UI must label these calls "Demo call".
library;

import 'dart:async';
import 'dart:math';

import '../../domain/models/enums.dart';
import 'call_engine.dart';

class DemoCallEngine implements CallEngine {
  final _stateCtrl = StreamController<ActiveCallSnapshot>.broadcast();
  final _errorCtrl = StreamController<CallEngineError>.broadcast();
  final Map<String, ActiveCallSnapshot> _calls = {};
  final Random _rng;
  final Duration tick;
  int _seq = 0;

  /// [scriptedOutcome] forces the ringing result for deterministic tests:
  /// one of connected|busy|noAnswer|voicemail|failed. Null = pseudo-random.
  String? scriptedOutcome;

  DemoCallEngine({int? seed, this.tick = const Duration(milliseconds: 900)})
      : _rng = Random(seed ?? 42);

  @override
  String get providerId => 'demo';

  @override
  EngineStatus get status => const EngineStatus(
        provider: 'Demo VoIP (local simulation)',
        mockMode: true,
        connected: false,
        missingConfiguration: ['No live provider needed — demo only'],
        simulatedCapabilities: [
          'place',
          'accept',
          'reject',
          'end',
          'hold',
          'resume',
          'mute',
          'dtmf',
          'transfer',
          'conference-marker',
          'recording-marker',
        ],
        unsupportedCapabilities: ['real audio', 'real PSTN', 'E911'],
      );

  @override
  Stream<ActiveCallSnapshot> get callStates => _stateCtrl.stream;

  @override
  Stream<CallEngineError> get errors => _errorCtrl.stream;

  @override
  Future<void> initialize() async {}

  void _emit(ActiveCallSnapshot snap) {
    _calls[snap.callId] = snap;
    _stateCtrl.add(snap);
  }

  ActiveCallSnapshot _require(String callId) {
    final c = _calls[callId];
    if (c == null) throw StateError('unknown call $callId');
    return c;
  }

  void _transition(String callId, CallState to) {
    final c = _require(callId);
    if (!isLegalCallTransition(c.state, to)) {
      _errorCtrl.add(
        CallEngineError('illegal-transition', '${c.state} -> $to'),
      );
      return;
    }
    _emit(
      c.copyWith(
        state: to,
        connectedAt: to == CallState.connected ? DateTime.now() : null,
      ),
    );
  }

  @override
  Future<String> placeCall(String toE164, {String? fromNumberId}) async {
    final callId =
        'democall_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
    _emit(
      ActiveCallSnapshot(
        callId: callId,
        remoteE164: toE164,
        direction: CallDirection.outbound,
        state: CallState.preparing,
        startedAt: DateTime.now(),
      ),
    );
    unawaited(_progressOutbound(callId));
    return callId;
  }

  Future<void> _progressOutbound(String callId) async {
    await Future<void>.delayed(tick);
    if (_isGone(callId)) return;
    _transition(callId, CallState.dialing);
    await Future<void>.delayed(tick);
    if (_isGone(callId)) return;
    _transition(callId, CallState.ringing);
    await Future<void>.delayed(tick * 3);
    if (_isGone(callId)) return;
    final c = _require(callId);
    if (c.state != CallState.ringing) return; // user already acted
    final outcome = scriptedOutcome ?? _randomOutcome();
    switch (outcome) {
      case 'connected':
        _transition(callId, CallState.connected);
      case 'busy':
        _transition(callId, CallState.busy);
      case 'noAnswer':
        _transition(callId, CallState.noAnswer);
      case 'voicemail':
        _transition(callId, CallState.voicemail);
      default:
        _transition(callId, CallState.failed);
    }
  }

  String _randomOutcome() {
    final r = _rng.nextDouble();
    if (r < 0.65) return 'connected';
    if (r < 0.75) return 'busy';
    if (r < 0.88) return 'noAnswer';
    if (r < 0.96) return 'voicemail';
    return 'failed';
  }

  bool _isGone(String callId) {
    final c = _calls[callId];
    return c == null || c.state.isTerminal;
  }

  /// Simulates an inbound demo call appearing on this device.
  String simulateInbound(String fromE164) {
    final callId = 'demoin_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
    _emit(
      ActiveCallSnapshot(
        callId: callId,
        remoteE164: fromE164,
        direction: CallDirection.inbound,
        state: CallState.ringing,
        startedAt: DateTime.now(),
      ),
    );
    return callId;
  }

  @override
  Future<void> acceptCall(String callId) async =>
      _transition(callId, CallState.connected);

  @override
  Future<void> rejectCall(String callId) async =>
      _transition(callId, CallState.completed);

  /// Route an unanswered inbound call to voicemail.
  Future<void> sendToVoicemail(String callId) async =>
      _transition(callId, CallState.voicemail);

  @override
  Future<void> endCall(String callId) async {
    final c = _require(callId);
    if (c.state.isTerminal) return;
    _transition(callId, CallState.completed);
  }

  @override
  Future<void> hold(String callId) async {
    _transition(callId, CallState.onHold);
    _emit(_require(callId).copyWith(onHold: true));
  }

  @override
  Future<void> resume(String callId) async {
    _transition(callId, CallState.connected);
    _emit(_require(callId).copyWith(onHold: false));
  }

  @override
  Future<void> mute(String callId) async =>
      _emit(_require(callId).copyWith(muted: true));

  @override
  Future<void> unmute(String callId) async =>
      _emit(_require(callId).copyWith(muted: false));

  @override
  Future<void> sendDtmf(String callId, String digits) async {
    if (!RegExp(r'^[0-9*#]+$').hasMatch(digits)) {
      _errorCtrl.add(const CallEngineError('bad-dtmf', 'invalid DTMF digits'));
    }
  }

  @override
  Future<void> transfer(String callId, String toDestination) async {
    _transition(callId, CallState.transferring);
    await Future<void>.delayed(tick);
    if (!_isGone(callId)) _transition(callId, CallState.completed);
  }

  @override
  Future<void> conference(String callId, String participantE164) async {
    // Demo marker only; snapshot state unchanged.
  }

  @override
  Future<void> startRecording(String callId) async =>
      _emit(_require(callId).copyWith(recording: true));

  @override
  Future<void> stopRecording(String callId) async =>
      _emit(_require(callId).copyWith(recording: false));

  @override
  Future<void> dispose() async {
    await _stateCtrl.close();
    await _errorCtrl.close();
  }
}
