/// Riverpod wiring: repository, engines, active-call session controller,
/// inbound-call simulator, device presence, global search.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/local_store.dart';
import 'data/repositories/app_repository.dart';
import 'domain/models/enums.dart';
import 'domain/models/models.dart';
import 'domain/models/models2.dart';
import 'engines/ai/agent_simulator.dart';
import 'engines/ai/ai_providers.dart';
import 'engines/call/call_engine.dart';
import 'engines/call/demo_call_engine.dart';
import 'engines/call/mock_engines.dart';
import 'engines/handoff/handoff_machine.dart';
import 'engines/messaging/messaging_provider.dart';
import 'engines/routing/routing.dart';
import 'engines/voicemail/voicemail_providers.dart';
import 'package:collection/collection.dart';

final snapshotStoreProvider = Provider<SnapshotStore>(
  (ref) => kIsWeb ? MemorySnapshotStore() : FileSnapshotStore(),
);

final appRepositoryProvider = Provider<AppRepository>((ref) {
  final repo = AppRepository(ref.watch(snapshotStoreProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

/// Reactive app state.
final appStateProvider = StreamProvider<AppState>((ref) async* {
  final repo = ref.watch(appRepositoryProvider);
  yield repo.state;
  yield* repo.changes;
});

AppState stateOf(WidgetRef ref) =>
    ref.watch(appStateProvider).valueOrNull ?? const AppState();

// ---- Engines ----
final demoCallEngineProvider = Provider<DemoCallEngine>((ref) {
  final e = DemoCallEngine();
  ref.onDispose(() => e.dispose());
  return e;
});

final allCallEnginesProvider = Provider<List<CallEngine>>(
  (ref) => [
    ref.watch(demoCallEngineProvider),
    ExternalDialerCallEngine(),
    MockSipCallEngine(),
    MockSignalMashCallEngine(),
    MockTwilioCallEngine(),
    MockVonageCallEngine(),
    MockAsteriskCallEngine(),
    MockVicidialCallEngine(),
    MockAiVoiceCallEngine(),
  ],
);

final demoMessagingProvider = Provider<DemoMessagingProvider>((ref) {
  final p = DemoMessagingProvider();
  ref.onDispose(() => p.dispose());
  return p;
});

final transcriptionProvider = Provider<TranscriptionProvider>(
  (ref) => DemoTranscriptionProvider(),
);

final agentSimulatorProvider = Provider<AgentSimulator>(
  (ref) => AgentSimulator(mockAnthropicLlm()),
);

// ---- Active call session ----
class CallSession {
  final ActiveCallSnapshot snapshot;
  final Contact? contact;
  final String? campaignId;
  final HandoffMachine handoff;
  final String notes;
  const CallSession({
    required this.snapshot,
    this.contact,
    this.campaignId,
    required this.handoff,
    this.notes = '',
  });

  CallSession copyWith({ActiveCallSnapshot? snapshot, String? notes}) =>
      CallSession(
        snapshot: snapshot ?? this.snapshot,
        contact: contact,
        campaignId: campaignId,
        handoff: handoff,
        notes: notes ?? this.notes,
      );
}

class CallSessionController extends Notifier<CallSession?> {
  StreamSubscription<ActiveCallSnapshot>? _sub;

  @override
  CallSession? build() {
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  DemoCallEngine get _engine => ref.read(demoCallEngineProvider);
  AppRepository get _repo => ref.read(appRepositoryProvider);

  Future<void> placeDemoCall(
    String e164, {
    String? fromNumberId,
    String? campaignId,
  }) async {
    if (_repo.isDnc(e164)) {
      _repo.notify('warning', 'Call blocked', '$e164 is on the DNC list.');
      return;
    }
    final callId = await _engine.placeCall(e164, fromNumberId: fromNumberId);
    _attach(callId, e164, CallDirection.outbound, campaignId: campaignId);
  }

  void simulateInbound(String fromE164) {
    final callId = _engine.simulateInbound(fromE164);
    _attach(callId, fromE164, CallDirection.inbound);
    _repo.notify('call', 'Incoming demo call', 'From $fromE164');
  }

  void _attach(
    String callId,
    String e164,
    CallDirection dir, {
    String? campaignId,
  }) {
    final contact = _repo.state.contacts
        .where((c) => c.phones.any((p) => p.e164 == e164))
        .firstOrNull;
    state = CallSession(
      snapshot: ActiveCallSnapshot(
        callId: callId,
        remoteE164: e164,
        direction: dir,
        state: dir == CallDirection.inbound
            ? CallState.ringing
            : CallState.preparing,
        startedAt: DateTime.now(),
      ),
      contact: contact,
      campaignId: campaignId,
      handoff: HandoffMachine(),
    );
    _sub?.cancel();
    _sub = _engine.callStates.listen((snap) {
      if (state == null || snap.callId != state!.snapshot.callId) return;
      state = state!.copyWith(snapshot: snap);
      if (snap.state.isTerminal) _finalize(snap);
    });
  }

  void _finalize(ActiveCallSnapshot snap) {
    final s = state;
    if (s == null) return;
    final now = DateTime.now();
    final record = CallRecord(
      id: snap.callId,
      direction: snap.direction,
      contactId: s.contact?.id,
      remoteE164: snap.remoteE164,
      powerlineNumberId: _repo.state.numbers.firstOrNull?.id,
      agentKind: AgentKind.human,
      campaignId: s.campaignId,
      startedAt: snap.startedAt,
      answeredAt: snap.connectedAt,
      endedAt: now,
      durationSeconds: snap.connectedAt == null
          ? 0
          : now.difference(snap.connectedAt!).inSeconds,
      disposition: switch (snap.state) {
        CallState.completed =>
          snap.connectedAt != null ? 'contacted' : 'cancelled',
        CallState.busy => 'busy',
        CallState.noAnswer => 'no-answer',
        CallState.voicemail => 'voicemail',
        _ => 'failed',
      },
      notes: s.notes,
      finalState: snap.state,
    );
    _repo.addCall(record);
    if (snap.state == CallState.voicemail) {
      _generateVoicemail(record);
    }
    if (record.missed) {
      _repo.notify('call', 'Missed demo call', 'From ${snap.remoteE164}');
    }
  }

  Future<void> _generateVoicemail(CallRecord record) async {
    final vmId = newId('vm');
    final tp = ref.read(transcriptionProvider);
    final result = await tp.transcribe(
      'assets/audio/demo_voicemail.wav#${record.id}',
    );
    _repo.addVoicemail(
      Voicemail(
        id: vmId,
        callRecordId: record.id,
        remoteE164: record.remoteE164,
        durationSeconds: 24,
        transcript: result.text,
        transcriptConfidence: result.confidence,
        createdAt: DateTime.now(),
      ),
    );
    _repo.updateCall(record.copyWith(voicemailId: vmId));
  }

  // Call controls — delegate to engine.
  Future<void> accept() async => _engine.acceptCall(state!.snapshot.callId);
  Future<void> reject() async => _engine.rejectCall(state!.snapshot.callId);
  Future<void> sendToVoicemail() async =>
      _engine.sendToVoicemail(state!.snapshot.callId);
  Future<void> end() async => _engine.endCall(state!.snapshot.callId);
  Future<void> hold() async => _engine.hold(state!.snapshot.callId);
  Future<void> resume() async => _engine.resume(state!.snapshot.callId);
  Future<void> toggleMute() async {
    final s = state!.snapshot;
    s.muted ? await _engine.unmute(s.callId) : await _engine.mute(s.callId);
  }

  Future<void> dtmf(String d) async =>
      _engine.sendDtmf(state!.snapshot.callId, d);
  Future<void> transfer(String dest) async =>
      _engine.transfer(state!.snapshot.callId, dest);

  void setNotes(String notes) => state = state?.copyWith(notes: notes);

  void recordHandoff(HandoffKind kind, String reason, String from, String to) {
    final s = state;
    if (s == null) return;
    _repo.addHandoff(
      HandoffEvent(
        id: newId('ho'),
        callRecordId: s.snapshot.callId,
        kind: kind,
        reason: reason,
        fromParty: from,
        toParty: to,
        whisperSummary: s.handoff.whisperSummary,
        createdAt: DateTime.now(),
      ),
    );
  }

  void clear() {
    _sub?.cancel();
    state = null;
  }
}

final callSessionProvider =
    NotifierProvider<CallSessionController, CallSession?>(
  CallSessionController.new,
);

// ---- Multi-device ring simulation ----
class RingSimEvent {
  final String deviceId;
  final String deviceName;
  final String status; // ringing | stopped | answered-elsewhere
  const RingSimEvent(this.deviceId, this.deviceName, this.status);
}

class DevicePresenceSimulator extends Notifier<List<RingSimEvent>> {
  @override
  List<RingSimEvent> build() => const [];

  Future<void> simulateRing(String remoteE164) async {
    final repo = ref.read(appRepositoryProvider);
    final hours = repo.state.businessHours;
    final decision = routeInboundCall(
      rules: repo.state.routingRules,
      devices: repo.state.devices,
      hours: hours,
      localNow: DateTime.now(),
    );
    if (decision.action != 'ring') {
      state = [RingSimEvent('router', decision.explanation, decision.action)];
      return;
    }
    final devices = repo.state.devices
        .where((d) => decision.ringDeviceIds.contains(d.id))
        .toList();
    state = [for (final d in devices) RingSimEvent(d.id, d.name, 'ringing')];
    await Future<void>.delayed(const Duration(seconds: 2));
    state = [
      for (final d in devices)
        RingSimEvent(
          d.id,
          d.name,
          d.isThisDevice ? 'answered-here' : 'answered-elsewhere',
        ),
    ];
  }

  void clearEvents() => state = const [];
}

final ringSimProvider =
    NotifierProvider<DevicePresenceSimulator, List<RingSimEvent>>(
  DevicePresenceSimulator.new,
);

// ---- Global search ----
class SearchHit {
  final String category;
  final String title;
  final String subtitle;
  final String route;
  const SearchHit(this.category, this.title, this.subtitle, this.route);
}

List<SearchHit> globalSearch(AppState s, String query) {
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return const [];
  final hits = <SearchHit>[];
  for (final c in s.contacts) {
    if (c.displayName.toLowerCase().contains(q) ||
        c.phones.any((p) => p.e164.contains(q))) {
      hits.add(
        SearchHit('Contact', c.displayName, c.primaryPhone ?? '', '/contacts'),
      );
    }
  }
  for (final co in s.companies) {
    if (co.name.toLowerCase().contains(q)) {
      hits.add(SearchHit('Company', co.name, co.industry ?? '', '/contacts'));
    }
  }
  for (final n in s.numbers) {
    if (n.e164.contains(q) || n.label.toLowerCase().contains(q)) {
      hits.add(SearchHit('Number', n.label, n.e164, '/settings'));
    }
  }
  for (final m in s.messages) {
    if (m.body.toLowerCase().contains(q)) {
      hits.add(
        SearchHit('Message', m.body, m.createdAt.toString(), '/messages'),
      );
    }
  }
  for (final cl in s.calls) {
    if (cl.remoteE164.contains(q)) {
      hits.add(
        SearchHit('Call', cl.remoteE164, cl.disposition ?? '', '/calls'),
      );
    }
  }
  for (final v in s.voicemails) {
    if (v.transcript.toLowerCase().contains(q)) {
      hits.add(
        SearchHit('Voicemail', v.transcript, v.remoteE164, '/voicemail'),
      );
    }
  }
  for (final cp in s.campaigns) {
    if (cp.name.toLowerCase().contains(q)) {
      hits.add(SearchHit('Campaign', cp.name, cp.status.name, '/campaigns'));
    }
  }
  for (final a in s.agents) {
    if (a.name.toLowerCase().contains(q)) {
      hits.add(SearchHit('AI Agent', a.name, a.role, '/agents'));
    }
  }
  for (final ap in s.appointments) {
    if (ap.kind.toLowerCase().contains(q) ||
        (ap.address ?? '').toLowerCase().contains(q)) {
      hits.add(
        SearchHit('Appointment', ap.kind, ap.startsAt.toString(), '/campaigns'),
      );
    }
  }
  for (final d in s.deals) {
    if (d.nextAction.toLowerCase().contains(q) ||
        d.notes.toLowerCase().contains(q)) {
      hits.add(SearchHit('Deal', d.nextAction, d.stage.name, '/campaigns'));
    }
  }
  return hits.take(40).toList();
}
