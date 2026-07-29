/// Mock provider engines: SIP, SignalMash, Twilio, Vonage, Asterisk, VICIdial,
/// AI-voice, plus the ExternalDialerCallEngine.
///
/// Every mock reports mockMode=true, connected=false and the exact missing
/// configuration. Attempting to place a call through an unconfigured mock
/// throws — nothing here pretends to be live.
library;

import 'dart:async';

import 'call_engine.dart';

class MockProviderCallEngine implements CallEngine {
  final String _providerId;
  final String displayName;
  final List<String> requiredConfig;
  final List<String> simulatedCapabilities;
  final List<String> unsupportedCapabilities;

  final _stateCtrl = StreamController<ActiveCallSnapshot>.broadcast();
  final _errorCtrl = StreamController<CallEngineError>.broadcast();

  MockProviderCallEngine({
    required String providerId,
    required this.displayName,
    required this.requiredConfig,
    this.simulatedCapabilities = const [],
    this.unsupportedCapabilities = const ['live-calls'],
  }) : _providerId = providerId;

  @override
  String get providerId => _providerId;

  @override
  EngineStatus get status => EngineStatus(
    provider: displayName,
    mockMode: true,
    connected: false,
    missingConfiguration: requiredConfig,
    simulatedCapabilities: simulatedCapabilities,
    unsupportedCapabilities: unsupportedCapabilities,
  );

  @override
  Stream<ActiveCallSnapshot> get callStates => _stateCtrl.stream;

  @override
  Stream<CallEngineError> get errors => _errorCtrl.stream;

  @override
  Future<void> initialize() async {
    _errorCtrl.add(
      CallEngineError(
        'not-configured',
        '$displayName is a mock: ${requiredConfig.join(', ')} missing',
      ),
    );
  }

  Never _blocked(String op) {
    final err = CallEngineError(
      'mock-blocked',
      '$displayName cannot $op: provider not configured (mock mode). Required: ${requiredConfig.join(', ')}',
    );
    _errorCtrl.add(err);
    throw UnsupportedError(err.toString());
  }

  @override
  Future<String> placeCall(String toE164, {String? fromNumberId}) async =>
      _blocked('place a call');
  @override
  Future<void> acceptCall(String callId) async => _blocked('accept');
  @override
  Future<void> rejectCall(String callId) async => _blocked('reject');
  @override
  Future<void> endCall(String callId) async => _blocked('end');
  @override
  Future<void> hold(String callId) async => _blocked('hold');
  @override
  Future<void> resume(String callId) async => _blocked('resume');
  @override
  Future<void> mute(String callId) async => _blocked('mute');
  @override
  Future<void> unmute(String callId) async => _blocked('unmute');
  @override
  Future<void> sendDtmf(String callId, String digits) async =>
      _blocked('send DTMF');
  @override
  Future<void> transfer(String callId, String toDestination) async =>
      _blocked('transfer');
  @override
  Future<void> conference(String callId, String participantE164) async =>
      _blocked('conference');
  @override
  Future<void> startRecording(String callId) async => _blocked('record');
  @override
  Future<void> stopRecording(String callId) async => _blocked('stop recording');
  @override
  Future<void> dispose() async {
    await _stateCtrl.close();
    await _errorCtrl.close();
  }
}

class MockSipCallEngine extends MockProviderCallEngine {
  MockSipCallEngine()
    : super(
        providerId: 'sip',
        displayName: 'SIP (generic)',
        requiredConfig: ['SIP server', 'username', 'password', 'transport'],
        simulatedCapabilities: ['registration-state-model'],
      );
}

class MockSignalMashCallEngine extends MockProviderCallEngine {
  MockSignalMashCallEngine()
    : super(
        providerId: 'signalmash',
        displayName: 'SignalMash',
        requiredConfig: ['API key', 'SIP trunk credentials'],
      );
}

class MockTwilioCallEngine extends MockProviderCallEngine {
  MockTwilioCallEngine()
    : super(
        providerId: 'twilio',
        displayName: 'Twilio Programmable Voice',
        requiredConfig: [
          'Account SID',
          'Auth token / API key',
          'TwiML app or webhook URL',
        ],
      );
}

class MockVonageCallEngine extends MockProviderCallEngine {
  MockVonageCallEngine()
    : super(
        providerId: 'vonage',
        displayName: 'Vonage Voice API',
        requiredConfig: [
          'API key',
          'API secret',
          'Application ID + private key',
        ],
      );
}

class MockAsteriskCallEngine extends MockProviderCallEngine {
  MockAsteriskCallEngine()
    : super(
        providerId: 'asterisk',
        displayName: 'Asterisk (AMI/ARI)',
        requiredConfig: ['AMI host/port', 'AMI user/secret', 'ARI app name'],
        simulatedCapabilities: ['ami-event-model', 'ari-channel-model'],
      );
}

class MockVicidialCallEngine extends MockProviderCallEngine {
  MockVicidialCallEngine()
    : super(
        providerId: 'vicidial',
        displayName: 'VICIdial agent API',
        requiredConfig: [
          'Server URL',
          'API user/pass',
          'Agent login',
          'Campaign',
        ],
        simulatedCapabilities: ['disposition-sync-model', 'lead-pull-model'],
      );
}

class MockAiVoiceCallEngine extends MockProviderCallEngine {
  MockAiVoiceCallEngine()
    : super(
        providerId: 'ai-voice',
        displayName: 'AI Voice provider',
        requiredConfig: ['Voice provider API key', 'LLM provider API key'],
        simulatedCapabilities: [
          'scripted-local-simulation (see AI Agents tab)',
        ],
      );
}

/// Launches the platform telephone handler (tel: URI) where the OS supports
/// it. The actual launch is delegated so this class stays testable.
class ExternalDialerCallEngine extends MockProviderCallEngine {
  final Future<bool> Function(Uri uri)? launcher;

  ExternalDialerCallEngine({this.launcher})
    : super(
        providerId: 'external-dialer',
        displayName: 'External system dialer',
        requiredConfig: ['Host OS telephone handler'],
        simulatedCapabilities: ['tel: URI handoff'],
        unsupportedCapabilities: ['in-app call control after handoff'],
      );

  @override
  Future<String> placeCall(String toE164, {String? fromNumberId}) async {
    final uri = Uri.parse('tel:$toE164');
    final ok = await (launcher?.call(uri) ?? Future.value(false));
    if (!ok) {
      throw UnsupportedError(
        'No telephone handler available on this platform. Copy the number instead.',
      );
    }
    return 'external_${DateTime.now().millisecondsSinceEpoch}';
  }
}
