/// AI Agents workspace: agent cards + local scripted simulator + handoff demo.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../data/repositories/app_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/models/models2.dart';
import '../../engines/ai/agent_simulator.dart';
import '../../providers.dart';
import 'package:collection/collection.dart';

class AgentsScreen extends ConsumerStatefulWidget {
  const AgentsScreen({super.key});

  @override
  ConsumerState<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends ConsumerState<AgentsScreen> {
  String? selectedAgentId;
  SimPersona persona = SimPersona.interested;
  SimResult? result;
  bool running = false;

  @override
  Widget build(BuildContext context) {
    final s = stateOf(ref);
    selectedAgentId ??= s.agents.firstOrNull?.id;
    final agent = s.agents.where((a) => a.id == selectedAgentId).firstOrNull;
    final wide = MediaQuery.of(context).size.width >= 1000;

    final list = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Row(
          children: [
            Text(
              'AI Agents',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SizedBox(width: 8),
            DemoBadge(label: 'TEST MODE — never calls real numbers'),
          ],
        ),
        const SizedBox(height: 8),
        for (final a in s.agents)
          Card(
            child: ListTile(
              selected: a.id == selectedAgentId,
              selectedTileColor: PowerlineColors.cobaltDeep.withValues(
                alpha: 0.12,
              ),
              leading: const Icon(Icons.smart_toy_outlined),
              title: Text(a.name),
              subtitle: Text(
                '${a.role} · ${a.status} · LLM: ${a.llmProvider} (mock) · voice: ${a.voiceProvider} (mock)\n'
                'limits: ${a.dailyCallLimit}/day, ${a.workingHourStart}:00–${a.workingHourEnd}:00 · DNC honored: ${a.honorsDnc ? 'yes' : 'no'} · consent required: ${a.consentRequired ? 'yes' : 'no'}',
                style: const TextStyle(fontSize: 11),
              ),
              isThreeLine: true,
              onTap: () => setState(() {
                selectedAgentId = a.id;
                result = null;
              }),
            ),
          ),
      ],
    );

    final detail = agent == null
        ? const Center(child: Text('Select an agent'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                agent.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                agent.description,
                style: const TextStyle(color: PowerlineColors.textSecondary),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Configuration',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      _kv('Greeting', agent.greeting),
                      _kv(
                        'System prompt',
                        agent.systemPrompt.isEmpty
                            ? '(default)'
                            : agent.systemPrompt,
                      ),
                      _kv('Allowed actions', agent.allowedActions.join(', ')),
                      _kv(
                        'Forbidden actions',
                        agent.forbiddenActions.join(', '),
                      ),
                      _kv(
                        'Escalation conditions',
                        agent.escalationConditions.join(', '),
                      ),
                      _kv('Handoff destination', agent.handoffDestination),
                      _kv(
                        'Recording',
                        agent.recordingEnabled ? 'enabled' : 'disabled',
                      ),
                      _kv(
                        'Transcription',
                        agent.transcriptionEnabled ? 'enabled' : 'disabled',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'Call simulator',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(width: 8),
                          DemoBadge(label: 'LOCAL SCRIPTED — no real call'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          DropdownButton<SimPersona>(
                            value: persona,
                            items: const [
                              DropdownMenuItem(
                                value: SimPersona.interested,
                                child: Text('Interested caller'),
                              ),
                              DropdownMenuItem(
                                value: SimPersona.priceShopper,
                                child: Text('Price shopper'),
                              ),
                              DropdownMenuItem(
                                value: SimPersona.wantsHuman,
                                child: Text('Wants a human'),
                              ),
                              DropdownMenuItem(
                                value: SimPersona.notInterested,
                                child: Text('Not interested / opt-out'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => persona = v ?? persona),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: running ? null : () => _run(agent),
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: Text(
                              running ? 'Running…' : 'Run simulation',
                            ),
                          ),
                        ],
                      ),
                      if (result != null) ...[
                        const Divider(),
                        for (final t in result!.transcript)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    t.role.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: switch (t.role) {
                                        'agent' => PowerlineColors.cobalt,
                                        'caller' => PowerlineColors.stateHold,
                                        _ => PowerlineColors.textSecondary,
                                      },
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.text,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      if (t.detectedIntent != null)
                                        Text(
                                          'intent: ${t.detectedIntent}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color:
                                                PowerlineColors.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            Chip(label: Text('Outcome: ${result!.outcome}')),
                            Chip(
                              label: Text(
                                'Appointment: ${result!.appointmentBooked ? 'booked' : 'no'}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Escalated: ${result!.escalatedToHuman ? 'yes' : 'no'}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'DNC: ${result!.dncRequested ? 'requested' : 'no'}',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recent handoff events',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      for (final h in s.handoffs.take(6))
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.swap_horiz, size: 16),
                          title: Text(
                            '${h.kind.name}: ${h.fromParty} → ${h.toParty}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            '${h.reason}${h.whisperSummary.isNotEmpty ? '\nWhisper: ${h.whisperSummary}' : ''}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );

    if (!wide) {
      return ListView(
        children: [
          SizedBox(height: 400, child: list),
          detail,
        ],
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 380,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: PowerlineColors.border)),
            ),
            child: list,
          ),
        ),
        Expanded(child: detail),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: Text(
                k,
                style: const TextStyle(
                  fontSize: 11,
                  color: PowerlineColors.textSecondary,
                ),
              ),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  Future<void> _run(AiAgent agent) async {
    setState(() => running = true);
    final sim = ref.read(agentSimulatorProvider);
    final r = await sim.run(agent, persona);
    final repo = ref.read(appRepositoryProvider);
    // Persist the AI conversation as an AI call record.
    final callId = newId('cl');
    repo.addCall(
      CallRecord(
        id: callId,
        direction: agent.role == 'outbound'
            ? CallDirection.outbound
            : CallDirection.inbound,
        remoteE164: '+15005550199', // fictional simulator counterpart
        agentKind: AgentKind.ai,
        aiAgentId: agent.id,
        startedAt: DateTime.now(),
        answeredAt: DateTime.now(),
        endedAt: DateTime.now().add(const Duration(seconds: 45)),
        durationSeconds: 45,
        disposition: r.outcome,
        notes: r.transcript.map((t) => '${t.role}: ${t.text}').join('\n'),
        finalState: CallState.completed,
      ),
    );
    if (r.escalatedToHuman) {
      repo.addHandoff(
        HandoffEvent(
          id: newId('ho'),
          callRecordId: callId,
          kind: HandoffKind.aiRequestsHuman,
          reason: 'Simulated caller requested human',
          fromParty: 'ai:${agent.name}',
          toParty: agent.handoffDestination,
          whisperSummary: 'Caller context from simulation.',
          createdAt: DateTime.now(),
        ),
      );
    }
    if (r.dncRequested) {
      repo.addDnc(
        '+15005550199',
        reason: 'requested during AI simulation',
        source: 'ai-agent',
      );
    }
    setState(() {
      result = r;
      running = false;
    });
  }
}
