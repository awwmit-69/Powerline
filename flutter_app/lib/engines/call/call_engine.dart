/// Provider-neutral call engine abstraction.
///
/// Every implementation must report its true connection state. Mock engines
/// never claim to be live and never contact real numbers.
library;

import 'dart:async';

import '../../domain/models/enums.dart';

class EngineStatus {
  final String provider;
  final bool mockMode;
  final bool connected;
  final List<String> missingConfiguration;
  final List<String> simulatedCapabilities;
  final List<String> unsupportedCapabilities;

  const EngineStatus({
    required this.provider,
    required this.mockMode,
    required this.connected,
    this.missingConfiguration = const [],
    this.simulatedCapabilities = const [],
    this.unsupportedCapabilities = const [],
  });

  String get summary => mockMode
      ? 'MOCK — not connected. Missing: ${missingConfiguration.join(', ')}'
      : (connected ? 'Connected' : 'Not connected');
}

class ActiveCallSnapshot {
  final String callId;
  final String remoteE164;
  final CallDirection direction;
  final CallState state;
  final bool muted;
  final bool onHold;
  final bool recording;
  final DateTime startedAt;
  final DateTime? connectedAt;

  const ActiveCallSnapshot({
    required this.callId,
    required this.remoteE164,
    required this.direction,
    required this.state,
    this.muted = false,
    this.onHold = false,
    this.recording = false,
    required this.startedAt,
    this.connectedAt,
  });

  ActiveCallSnapshot copyWith({CallState? state, bool? muted, bool? onHold, bool? recording, DateTime? connectedAt}) =>
      ActiveCallSnapshot(
        callId: callId,
        remoteE164: remoteE164,
        direction: direction,
        state: state ?? this.state,
        muted: muted ?? this.muted,
        onHold: onHold ?? this.onHold,
        recording: recording ?? this.recording,
        startedAt: startedAt,
        connectedAt: connectedAt ?? this.connectedAt,
      );
}

class CallEngineError {
  final String code;
  final String message;
  const CallEngineError(this.code, this.message);
  @override
  String toString() => '$code: $message';
}

/// The capability surface every engine implements. Engines that do not support
/// an operation must throw [UnsupportedError] rather than silently no-op.
abstract class CallEngine {
  String get providerId;
  EngineStatus get status;
  Stream<ActiveCallSnapshot> get callStates;
  Stream<CallEngineError> get errors;

  Future<void> initialize();
  Future<String> placeCall(String toE164, {String? fromNumberId});
  Future<void> acceptCall(String callId);
  Future<void> rejectCall(String callId);
  Future<void> endCall(String callId);
  Future<void> hold(String callId);
  Future<void> resume(String callId);
  Future<void> mute(String callId);
  Future<void> unmute(String callId);
  Future<void> sendDtmf(String callId, String digits);
  Future<void> transfer(String callId, String toDestination);
  Future<void> conference(String callId, String participantE164);
  Future<void> startRecording(String callId);
  Future<void> stopRecording(String callId);
  Future<void> dispose();
}
