/// Local scripted AI-agent call simulator.
///
/// Runs an entirely local conversation: no real number is ever contacted,
/// no external API is called. Produces a transcript, detected intents,
/// appointment decision and escalation decision.
library;

import '../../domain/models/models2.dart';
import 'ai_providers.dart';

class SimTurn {
  final String role; // agent | caller | system
  final String text;
  final String? detectedIntent;
  const SimTurn(this.role, this.text, {this.detectedIntent});
}

class SimResult {
  final List<SimTurn> transcript;
  final bool appointmentBooked;
  final bool escalatedToHuman;
  final bool dncRequested;
  final String outcome;
  const SimResult({
    required this.transcript,
    required this.appointmentBooked,
    required this.escalatedToHuman,
    required this.dncRequested,
    required this.outcome,
  });
}

/// Caller personas drive deterministic scripted behavior.
enum SimPersona { interested, priceShopper, wantsHuman, notInterested }

class AgentSimulator {
  final ConversationModelProvider llm;
  AgentSimulator(this.llm);

  Future<SimResult> run(AiAgent agent, SimPersona persona) async {
    final transcript = <SimTurn>[
      SimTurn(
        'system',
        'SIMULATED CALL — no real number contacted. Agent "${agent.name}" in test mode.',
      ),
      SimTurn(
        'agent',
        agent.greeting.isEmpty
            ? 'Hello! This is a demo AI assistant. This call is simulated.'
            : agent.greeting,
      ),
    ];
    final callerLines = switch (persona) {
      SimPersona.interested => [
          'Hi, yes I heard about the inspection.',
          'Tuesday works, yes.',
        ],
      SimPersona.priceShopper => [
          'How much does this cost?',
          'OK, Thursday could work, yes.',
        ],
      SimPersona.wantsHuman => ['I would rather talk to a human please.'],
      SimPersona.notInterested => [
          'Not interested, please remove me from your list.',
        ],
    };

    var booked = false;
    var escalated = false;
    var dnc = false;
    final turns = <(String, String)>[];

    for (final line in callerLines) {
      transcript.add(SimTurn('caller', line, detectedIntent: _intent(line)));
      turns.add(('user', line));
      final reply = await llm.complete(
        systemPrompt: agent.systemPrompt,
        turns: turns,
      );
      turns.add(('assistant', reply));
      if (reply.startsWith('[BOOK]')) booked = true;
      if (reply.startsWith('[ESCALATE]')) escalated = true;
      if (reply.startsWith('[DNC]')) dnc = true;
      transcript.add(
        SimTurn('agent', reply.replaceFirst(RegExp(r'^\[\w+\] '), '')),
      );
      if (escalated || dnc) break;
    }

    final outcome = dnc
        ? 'dnc-requested'
        : escalated
            ? 'escalated-to-human'
            : booked
                ? 'appointment-booked'
                : 'follow-up-needed';
    transcript.add(SimTurn('system', 'Outcome: $outcome (simulated)'));
    return SimResult(
      transcript: transcript,
      appointmentBooked: booked,
      escalatedToHuman: escalated,
      dncRequested: dnc,
      outcome: outcome,
    );
  }

  String _intent(String line) {
    final l = line.toLowerCase();
    if (l.contains('human') || l.contains('person')) return 'request-human';
    if (l.contains('cost') || l.contains('much') || l.contains('price')) {
      return 'pricing-question';
    }
    if (l.contains('not interested') || l.contains('remove')) return 'opt-out';
    if (l.contains('yes') || l.contains('works')) return 'affirmative';
    return 'general';
  }
}
