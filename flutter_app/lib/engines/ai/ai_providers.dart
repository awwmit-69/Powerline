/// Provider-neutral AI interfaces + mock implementations.
///
/// None of these mocks call any external API. They exist so real adapters
/// (Anthropic, OpenAI, Gemini, OpenAI-compatible, local) can be dropped in
/// behind stable interfaces.
library;

abstract class ConversationModelProvider {
  String get providerId;
  bool get isMock;
  Future<String> complete({required String systemPrompt, required List<(String role, String text)> turns});
}

abstract class SpeechToTextProvider {
  String get providerId;
  bool get isMock;
  Future<String> transcribeUtterance(String audioRef);
}

abstract class TextToSpeechProvider {
  String get providerId;
  bool get isMock;
  Future<String> synthesize(String text); // returns audio ref
}

abstract class KnowledgeProvider {
  String get providerId;
  Future<List<String>> retrieve(String query);
}

abstract class CallControlProvider {
  String get providerId;
  Future<void> requestHumanHandoff(String callId, String reason);
  Future<void> bookAppointmentMarker(String callId, DateTime when);
}

abstract class AiAgentProvider {
  String get providerId;
  bool get isMock;
}

class MockLlm implements ConversationModelProvider {
  final String _id;
  final String flavor;
  MockLlm(this._id, this.flavor);

  @override
  String get providerId => _id;
  @override
  bool get isMock => true;

  @override
  Future<String> complete({required String systemPrompt, required List<(String, String)> turns}) async {
    final lastUser = turns.lastWhere((t) => t.$1 == 'user', orElse: () => ('user', '')).$2.toLowerCase();
    if (lastUser.contains('human') || lastUser.contains('person') || lastUser.contains('representative')) {
      return '[ESCALATE] Of course — let me connect you with a team member right away.';
    }
    if (lastUser.contains('yes') || lastUser.contains('tuesday') || lastUser.contains('thursday')) {
      return '[BOOK] Great — I have you down. You will get a confirmation text shortly.';
    }
    if (lastUser.contains('price') || lastUser.contains('cost')) {
      return 'Pricing depends on the inspection findings; the visit itself is free. Would Tuesday 10am or Thursday 2pm work for a free inspection?';
    }
    if (lastUser.contains('not interested') || lastUser.contains('remove')) {
      return '[DNC] Understood — I will mark you as do-not-contact. Sorry for the trouble, and have a great day.';
    }
    return 'Thanks! To recap, we offer a free roof inspection after the recent storms. Would Tuesday 10am or Thursday 2pm work for you? ($flavor mock)';
  }
}

MockLlm mockAnthropicLlm() => MockLlm('anthropic-mock', 'Anthropic-style');
MockLlm mockOpenAiLlm() => MockLlm('openai-mock', 'OpenAI-style');
MockLlm mockGeminiLlm() => MockLlm('gemini-mock', 'Gemini-style');
MockLlm mockOpenAiCompatibleLlm() => MockLlm('openai-compatible-mock', 'OpenAI-compatible endpoint');
MockLlm mockLocalLlm() => MockLlm('local-model-mock', 'Local model');

class MockStt implements SpeechToTextProvider {
  @override
  String get providerId => 'mock-stt';
  @override
  bool get isMock => true;
  @override
  Future<String> transcribeUtterance(String audioRef) async => '[simulated utterance from $audioRef]';
}

class MockTts implements TextToSpeechProvider {
  @override
  String get providerId => 'mock-tts';
  @override
  bool get isMock => true;
  @override
  Future<String> synthesize(String text) async => 'demo-tts://len${text.length}';
}

class MockKnowledge implements KnowledgeProvider {
  final Map<String, String> facts;
  MockKnowledge([this.facts = const {
    'inspection': 'Inspections are free and take about 30 minutes.',
    'insurance': 'We document damage in a format insurers accept.',
    'warranty': 'Workmanship warranty is provided in writing after the job.',
  }]);
  @override
  String get providerId => 'mock-knowledge';
  @override
  Future<List<String>> retrieve(String query) async {
    final q = query.toLowerCase();
    return facts.entries.where((e) => q.contains(e.key)).map((e) => e.value).toList();
  }
}
