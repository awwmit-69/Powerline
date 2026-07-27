/// Voicemail, transcription and storage provider abstractions with
/// deterministic demo implementations.
library;

abstract class VoicemailProvider {
  String get providerId;
  Future<String> fetchAudioRef(String voicemailId);
}

abstract class TranscriptionProvider {
  String get providerId;
  Future<TranscriptionResult> transcribe(String audioRef);
}

abstract class StorageProvider {
  String get providerId;
  Future<String> store(String localPath);
  Future<String> resolve(String ref);
}

class TranscriptionResult {
  final String text;
  final double confidence;
  const TranscriptionResult(this.text, this.confidence);
}

class DemoVoicemailProvider implements VoicemailProvider {
  @override
  String get providerId => 'demo-voicemail';
  @override
  Future<String> fetchAudioRef(String voicemailId) async =>
      'assets/audio/demo_voicemail.wav';
}

/// Deterministic: same audioRef always yields the same transcript, so tests
/// and demos are reproducible. Clearly labelled as simulated.
class DemoTranscriptionProvider implements TranscriptionProvider {
  static const _bank = [
    'Hi, this is a demo voicemail. Please call me back about the roof inspection quote. Thanks.',
    'Hey, following up on the storm damage estimate we discussed. Call me when you can.',
    'Hello, I got your message about the appointment. Tuesday morning works for me.',
    'Hi there, checking whether the crew is still coming out this week. Thanks, bye.',
  ];

  @override
  String get providerId => 'demo-transcription';

  @override
  Future<TranscriptionResult> transcribe(String audioRef) async {
    final idx = audioRef.codeUnits.fold<int>(0, (a, b) => a + b) % _bank.length;
    return TranscriptionResult(
      '${_bank[idx]} [Simulated transcript]',
      0.9 + (idx * 0.02),
    );
  }
}

class DemoStorageProvider implements StorageProvider {
  final Map<String, String> _store = {};
  @override
  String get providerId => 'demo-storage';
  @override
  Future<String> store(String localPath) async {
    final ref = 'demo-store://${_store.length}';
    _store[ref] = localPath;
    return ref;
  }

  @override
  Future<String> resolve(String ref) async => _store[ref] ?? ref;
}
