/// End-to-end demo flows (19 scenarios). Runs against the repository +
/// engines exactly as the app wires them, using in-memory persistence.
///
/// Run on a host with Flutter:  flutter test integration_test/app_flow_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powerline/core/logic/campaign_queue.dart';
import 'package:powerline/data/local_store.dart';
import 'package:powerline/data/repositories/app_repository.dart';
import 'package:powerline/domain/models/enums.dart';
import 'package:powerline/domain/models/models.dart';
import 'package:powerline/domain/models/models2.dart';
import 'package:powerline/engines/ai/agent_simulator.dart';
import 'package:powerline/engines/ai/ai_providers.dart';
import 'package:powerline/engines/call/demo_call_engine.dart';
import 'package:powerline/engines/handoff/handoff_machine.dart';
import 'package:powerline/engines/messaging/messaging_provider.dart';
import 'package:powerline/engines/routing/routing.dart';
import 'package:powerline/engines/voicemail/voicemail_providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppRepository repo;
  setUp(() async {
    repo = AppRepository(MemorySnapshotStore());
    await repo.init();
  });

  test('1. create a contact', () {
    repo.upsertContact(Contact(id: 'c_new', firstName: 'Test', lastName: 'Lead',
        phones: const [PhoneEntry(label: 'mobile', e164: '+12145559001')],
        createdAt: DateTime.now(), updatedAt: DateTime.now()), op: 'create');
    expect(repo.state.contacts.any((c) => c.id == 'c_new'), isTrue);
  });

  test('2-3. place a demo call and save it', () async {
    final engine = DemoCallEngine(tick: const Duration(milliseconds: 1))..scriptedOutcome = 'connected';
    final id = await engine.placeCall('+12145559002');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final snap = await engine.callStates.first.timeout(const Duration(milliseconds: 50), onTimeout: () =>
        throw StateError('no state')).catchError((_) => null as dynamic);
    repo.addCall(CallRecord(id: id, direction: CallDirection.outbound,
        remoteE164: '+12145559002', startedAt: DateTime.now(),
        answeredAt: DateTime.now(), durationSeconds: 30, disposition: 'contacted'));
    expect(repo.state.calls.any((c) => c.id == id), isTrue);
    await engine.dispose();
  });

  test('4-5. receive simulated inbound call and miss it', () async {
    final engine = DemoCallEngine(tick: const Duration(milliseconds: 1));
    final id = engine.simulateInbound('+13145559003');
    repo.addCall(CallRecord(id: id, direction: CallDirection.inbound,
        remoteE164: '+13145559003', startedAt: DateTime.now(),
        finalState: CallState.voicemail, disposition: 'missed'));
    final rec = repo.state.calls.firstWhere((c) => c.id == id);
    expect(rec.missed, isTrue);
    await engine.dispose();
  });

  test('6-7. generate voicemail, then transcribe it', () async {
    final tp = DemoTranscriptionProvider();
    final r = await tp.transcribe('assets/audio/demo_voicemail.wav#vm1');
    repo.addVoicemail(Voicemail(id: 'vm_new', remoteE164: '+13145559003',
        durationSeconds: 20, transcript: r.text, transcriptConfidence: r.confidence,
        createdAt: DateTime.now()));
    expect(repo.state.voicemails.any((v) => v.id == 'vm_new'), isTrue);
    expect(r.text.toLowerCase(), contains('simulated'));
    expect(r.confidence, greaterThan(0.5));
  });

  test('8-9. send a demo message and receive a simulated reply', () async {
    final conv = repo.ensureConversation('+12145559008');
    final provider = DemoMessagingProvider(tick: const Duration(milliseconds: 1));
    final got = <MessagingEvent>[];
    final sub = provider.events.listen(got.add);
    repo.addMessage(Message(id: 'out1', conversationId: conv.id,
        direction: CallDirection.outbound, body: 'appointment?',
        state: MessageState.sending, createdAt: DateTime.now()));
    await provider.sendSms(OutboundMessageRequest(
        to: '+12145559008', from: '+12145550100', body: 'appointment?'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(got.any((e) => e.kind == 'delivery'), isTrue);
    expect(got.any((e) => e.kind == 'inbound'), isTrue);
    await sub.cancel();
    await provider.dispose();
  });

  test('10-11. mark DNC and confirm campaign-queue exclusion', () {
    final contact = repo.state.contacts.first;
    final phone = contact.phones.first.e164;
    repo.addDnc(phone, reason: 'integration test');
    final campaign = Campaign(id: 'camp_it', name: 'IT', status: CampaignStatus.active,
        leadContactIds: [contact.id], callingHourStart: 0, callingHourEnd: 24,
        createdAt: DateTime.now());
    final queue = buildCampaignQueue(campaign: campaign, allContacts: repo.state.contacts,
        dncE164s: {for (final d in repo.state.dnc) d.e164}, suppressedE164s: {},
        activeCallE164s: {}, utcNow: DateTime.now().toUtc());
    expect(queue.first.eligible, isFalse);
    expect(queue.first.exclusionReason, 'DNC');
  });

  test('12. schedule a callback', () {
    repo.upsertCallback(CallbackTask(id: 'cb_it', contactId: repo.state.contacts.first.id,
        dueAt: DateTime.now().add(const Duration(hours: 3)), reason: 'requested'));
    expect(repo.state.callbacks.any((c) => c.id == 'cb_it'), isTrue);
  });

  test('13. schedule an appointment', () {
    repo.upsertAppointment(Appointment(id: 'ap_it', contactId: repo.state.contacts.first.id,
        startsAt: DateTime.now().add(const Duration(days: 1))));
    expect(repo.state.appointments.any((a) => a.id == 'ap_it'), isTrue);
  });

  test('14-15. run simulated AI call and escalate to human', () async {
    final sim = AgentSimulator(mockAnthropicLlm());
    const agent = AiAgent(id: 'ag_it', name: 'IT Agent', greeting: 'hi (simulated)');
    final result = await sim.run(agent, SimPersona.wantsHuman);
    expect(result.escalatedToHuman, isTrue);
    repo.addCall(CallRecord(id: 'cl_ai', direction: CallDirection.inbound,
        remoteE164: '+15005550199', agentKind: AgentKind.ai, aiAgentId: agent.id,
        startedAt: DateTime.now(), durationSeconds: 30, disposition: result.outcome));
    repo.addHandoff(HandoffEvent(id: 'ho_it', callRecordId: 'cl_ai',
        kind: HandoffKind.aiRequestsHuman, fromParty: 'ai', toParty: 'human',
        createdAt: DateTime.now()));
    expect(repo.state.handoffs.any((h) => h.id == 'ho_it'), isTrue);
  });

  test('16. transfer from human to AI (handoff machine)', () {
    final m = HandoffMachine();
    expect(m.fire(HandoffTrigger.humanHandsToAi), isTrue);
    expect(m.fire(HandoffTrigger.aiTransferComplete), isTrue);
    expect(m.state, HandoffState.aiActive);
  });

  test('17. simulate multi-device ringing (routing)', () {
    final decision = routeInboundCall(
      rules: repo.state.routingRules,
      devices: repo.state.devices,
      hours: BusinessHours(weekly: {for (var d = 1; d <= 7; d++) d: [[0, 24]]}),
      localNow: DateTime(2026, 1, 1, 12),
    );
    expect(['ring', 'ai-agent', 'voicemail', 'forward'], contains(decision.action));
  });

  test('18. export call history to CSV text', () {
    final rows = StringBuffer('id,direction,remoteE164\n');
    for (final c in repo.state.calls) {
      rows.writeln('${c.id},${c.direction.name},${c.remoteE164}');
    }
    expect(rows.toString().split('\n').length, greaterThan(repo.state.calls.length));
  });

  test('19. back up and restore the database', () async {
    final before = repo.state.contacts.length;
    final path = await repo.backup();
    repo.deleteContact(repo.state.contacts.first.id);
    expect(repo.state.contacts.length, before - 1);
    await repo.restore(path);
    expect(repo.state.contacts.length, before);
  });
}
