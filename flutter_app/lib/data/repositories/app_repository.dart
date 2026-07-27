/// Central repository: owns AppState, all CRUD, persistence, sync journal.
///
/// UI widgets never hold business data; they read/watch this repository via
/// Riverpod providers.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/models/models2.dart';
import '../../engines/routing/routing.dart';
import '../local_store.dart';
import '../seed/demo_seed.dart';
import 'package:collection/collection.dart';

const _uuid = Uuid();
String newId(String prefix) => '${prefix}_${_uuid.v4().substring(0, 13)}';

class AppState {
  final List<Contact> contacts;
  final List<Company> companies;
  final List<PowerlineNumber> numbers;
  final List<Conversation> conversations;
  final List<Message> messages;
  final List<CallRecord> calls;
  final List<Voicemail> voicemails;
  final List<Campaign> campaigns;
  final List<PipelineDeal> deals;
  final List<Appointment> appointments;
  final List<CallbackTask> callbacks;
  final List<AiAgent> agents;
  final List<DeviceRecord> devices;
  final List<RoutingRule> routingRules;
  final List<HandoffEvent> handoffs;
  final List<DncRecord> dnc;
  final List<String> smsSuppression;
  final List<IntegrationCard> integrations;
  final List<AppNotification> notifications;
  final BusinessHours businessHours;
  final Map<String, String> settings;
  final List<Map<String, dynamic>> syncJournal;
  final List<String> activityLog;

  const AppState({
    this.contacts = const [],
    this.companies = const [],
    this.numbers = const [],
    this.conversations = const [],
    this.messages = const [],
    this.calls = const [],
    this.voicemails = const [],
    this.campaigns = const [],
    this.deals = const [],
    this.appointments = const [],
    this.callbacks = const [],
    this.agents = const [],
    this.devices = const [],
    this.routingRules = const [],
    this.handoffs = const [],
    this.dnc = const [],
    this.smsSuppression = const [],
    this.integrations = const [],
    this.notifications = const [],
    this.businessHours = const BusinessHours(),
    this.settings = const {},
    this.syncJournal = const [],
    this.activityLog = const [],
  });

  AppState copyWith({
    List<Contact>? contacts,
    List<Company>? companies,
    List<PowerlineNumber>? numbers,
    List<Conversation>? conversations,
    List<Message>? messages,
    List<CallRecord>? calls,
    List<Voicemail>? voicemails,
    List<Campaign>? campaigns,
    List<PipelineDeal>? deals,
    List<Appointment>? appointments,
    List<CallbackTask>? callbacks,
    List<AiAgent>? agents,
    List<DeviceRecord>? devices,
    List<RoutingRule>? routingRules,
    List<HandoffEvent>? handoffs,
    List<DncRecord>? dnc,
    List<String>? smsSuppression,
    List<IntegrationCard>? integrations,
    List<AppNotification>? notifications,
    BusinessHours? businessHours,
    Map<String, String>? settings,
    List<Map<String, dynamic>>? syncJournal,
    List<String>? activityLog,
  }) =>
      AppState(
        contacts: contacts ?? this.contacts,
        companies: companies ?? this.companies,
        numbers: numbers ?? this.numbers,
        conversations: conversations ?? this.conversations,
        messages: messages ?? this.messages,
        calls: calls ?? this.calls,
        voicemails: voicemails ?? this.voicemails,
        campaigns: campaigns ?? this.campaigns,
        deals: deals ?? this.deals,
        appointments: appointments ?? this.appointments,
        callbacks: callbacks ?? this.callbacks,
        agents: agents ?? this.agents,
        devices: devices ?? this.devices,
        routingRules: routingRules ?? this.routingRules,
        handoffs: handoffs ?? this.handoffs,
        dnc: dnc ?? this.dnc,
        smsSuppression: smsSuppression ?? this.smsSuppression,
        integrations: integrations ?? this.integrations,
        notifications: notifications ?? this.notifications,
        businessHours: businessHours ?? this.businessHours,
        settings: settings ?? this.settings,
        syncJournal: syncJournal ?? this.syncJournal,
        activityLog: activityLog ?? this.activityLog,
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'contacts': contacts.map((e) => e.toJson()).toList(),
        'companies': companies.map((e) => e.toJson()).toList(),
        'numbers': numbers.map((e) => e.toJson()).toList(),
        'conversations': conversations.map((e) => e.toJson()).toList(),
        'messages': messages.map((e) => e.toJson()).toList(),
        'calls': calls.map((e) => e.toJson()).toList(),
        'voicemails': voicemails.map((e) => e.toJson()).toList(),
        'campaigns': campaigns.map((e) => e.toJson()).toList(),
        'deals': deals.map((e) => e.toJson()).toList(),
        'appointments': appointments.map((e) => e.toJson()).toList(),
        'callbacks': callbacks.map((e) => e.toJson()).toList(),
        'agents': agents.map((e) => e.toJson()).toList(),
        'devices': devices.map((e) => e.toJson()).toList(),
        'routingRules': routingRules.map((e) => e.toJson()).toList(),
        'handoffs': handoffs.map((e) => e.toJson()).toList(),
        'dnc': dnc.map((e) => e.toJson()).toList(),
        'smsSuppression': smsSuppression,
        'integrations': integrations.map((e) => e.toJson()).toList(),
        'notifications': notifications.map((e) => e.toJson()).toList(),
        'businessHours': businessHours.toJson(),
        'settings': settings,
        'syncJournal': syncJournal,
        'activityLog': activityLog,
      };

  static List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
      (v as List? ?? []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();

  factory AppState.fromJson(Map<String, dynamic> j) => AppState(
        contacts: _list(j['contacts'], Contact.fromJson),
        companies: _list(j['companies'], Company.fromJson),
        numbers: _list(j['numbers'], PowerlineNumber.fromJson),
        conversations: _list(j['conversations'], Conversation.fromJson),
        messages: _list(j['messages'], Message.fromJson),
        calls: _list(j['calls'], CallRecord.fromJson),
        voicemails: _list(j['voicemails'], Voicemail.fromJson),
        campaigns: _list(j['campaigns'], Campaign.fromJson),
        deals: _list(j['deals'], PipelineDeal.fromJson),
        appointments: _list(j['appointments'], Appointment.fromJson),
        callbacks: _list(j['callbacks'], CallbackTask.fromJson),
        agents: _list(j['agents'], AiAgent.fromJson),
        devices: _list(j['devices'], DeviceRecord.fromJson),
        routingRules: _list(j['routingRules'], RoutingRule.fromJson),
        handoffs: _list(j['handoffs'], HandoffEvent.fromJson),
        dnc: _list(j['dnc'], DncRecord.fromJson),
        smsSuppression: (j['smsSuppression'] as List? ?? []).map((e) => e.toString()).toList(),
        integrations: _list(j['integrations'], IntegrationCard.fromJson),
        notifications: _list(j['notifications'], AppNotification.fromJson),
        businessHours: j['businessHours'] == null
            ? const BusinessHours()
            : BusinessHours.fromJson(Map<String, dynamic>.from(j['businessHours'] as Map)),
        settings: (j['settings'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), v.toString())),
        syncJournal: (j['syncJournal'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        activityLog: (j['activityLog'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

class AppRepository {
  final SnapshotStore store;
  AppState _state = const AppState();
  final _changes = StreamController<AppState>.broadcast();

  AppRepository(this.store);

  AppState get state => _state;
  Stream<AppState> get changes => _changes.stream;

  Future<void> init() async {
    final snap = await store.load();
    _state = snap == null ? buildDemoSeed() : AppState.fromJson(snap);
    _changes.add(_state);
    if (snap == null) await _persist();
  }

  Future<void> _persist() => store.save(_state.toJson());

  void _update(AppState next, {String? journalEntity, String? journalId, String? op, String? log}) {
    var s = next;
    if (journalEntity != null) {
      s = s.copyWith(syncJournal: [
        ...s.syncJournal,
        {
          'id': newId('se'),
          'entity': journalEntity,
          'entityId': journalId,
          'op': op ?? 'update',
          'createdAt': DateTime.now().toIso8601String(),
        }
      ]);
    }
    if (log != null) {
      s = s.copyWith(
          activityLog: [...s.activityLog, '${DateTime.now().toIso8601String()} $log']);
    }
    _state = s;
    _changes.add(_state);
    unawaited(_persist());
  }

  // ---- Contacts ----
  void upsertContact(Contact c, {String op = 'update'}) {
    final list = [..._state.contacts];
    final i = list.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      list[i] = c;
    } else {
      list.add(c);
    }
    _update(_state.copyWith(contacts: list),
        journalEntity: 'contact', journalId: c.id, op: op, log: '$op contact ${c.displayName}');
  }

  void deleteContact(String id) {
    _update(_state.copyWith(contacts: _state.contacts.where((c) => c.id != id).toList()),
        journalEntity: 'contact', journalId: id, op: 'delete', log: 'delete contact $id');
  }

  // ---- DNC / suppression ----
  bool isDnc(String e164) =>
      _state.dnc.any((d) => d.e164 == e164) ||
      _state.contacts.any((c) => c.dnc && c.phones.any((p) => p.e164 == e164));

  void addDnc(String e164, {String reason = 'manual', String source = 'manual'}) {
    if (_state.dnc.any((d) => d.e164 == e164)) return;
    _update(
      _state.copyWith(dnc: [
        ..._state.dnc,
        DncRecord(id: newId('dnc'), e164: e164, reason: reason, source: source, createdAt: DateTime.now())
      ]),
      journalEntity: 'dnc', journalId: e164, op: 'create', log: 'DNC added for $e164 ($reason)',
    );
  }

  void addSmsSuppression(String e164) {
    if (_state.smsSuppression.contains(e164)) return;
    _update(_state.copyWith(smsSuppression: [..._state.smsSuppression, e164]),
        journalEntity: 'suppression', journalId: e164, op: 'create', log: 'SMS opt-out $e164');
  }

  // ---- Messaging ----
  Conversation ensureConversation(String remoteE164, {String? contactId}) {
    final existing = _state.conversations.where((c) => c.remoteE164 == remoteE164);
    if (existing.isNotEmpty) return existing.first;
    final conv = Conversation(
      id: newId('cv'),
      remoteE164: remoteE164,
      contactId: contactId ??
          _state.contacts
              .where((c) => c.phones.any((p) => p.e164 == remoteE164))
              .map((c) => c.id)
              .firstOrNull,
      powerlineNumberId: _state.numbers.isEmpty ? null : _state.numbers.first.id,
      lastMessageAt: DateTime.now(),
    );
    _update(_state.copyWith(conversations: [conv, ..._state.conversations]),
        journalEntity: 'conversation', journalId: conv.id, op: 'create');
    return conv;
  }

  void addMessage(Message m) {
    final convs = _state.conversations.map((c) {
      if (c.id != m.conversationId) return c;
      return c.copyWith(
        lastMessageAt: m.createdAt,
        unreadCount: m.direction == CallDirection.inbound ? c.unreadCount + 1 : c.unreadCount,
        draft: m.direction == CallDirection.outbound ? '' : c.draft,
      );
    }).toList();
    _update(_state.copyWith(messages: [..._state.messages, m], conversations: convs),
        journalEntity: 'message', journalId: m.id, op: 'create');
  }

  void updateMessageState(String messageId, MessageState next) {
    final list = _state.messages.map((m) {
      if (m.id != messageId) return m;
      if (!isLegalMessageTransition(m.state, next)) return m;
      return m.copyWith(state: next);
    }).toList();
    _update(_state.copyWith(messages: list));
  }

  void updateConversation(Conversation c) {
    _update(_state.copyWith(
        conversations: _state.conversations.map((x) => x.id == c.id ? c : x).toList()));
  }

  void deleteConversationLocal(String id) {
    _update(_state.copyWith(
      conversations: _state.conversations.where((c) => c.id != id).toList(),
      messages: _state.messages.where((m) => m.conversationId != id).toList(),
    ), log: 'deleted conversation $id locally');
  }

  // ---- Calls ----
  void addCall(CallRecord r) {
    _update(_state.copyWith(calls: [r, ..._state.calls]),
        journalEntity: 'call', journalId: r.id, op: 'create', log: 'call ${r.direction.name} ${r.remoteE164}');
  }

  void updateCall(CallRecord r) {
    _update(_state.copyWith(calls: _state.calls.map((x) => x.id == r.id ? r : x).toList()),
        journalEntity: 'call', journalId: r.id, op: 'update');
  }

  // ---- Voicemail ----
  void addVoicemail(Voicemail v) {
    _update(_state.copyWith(voicemails: [v, ..._state.voicemails]),
        journalEntity: 'voicemail', journalId: v.id, op: 'create');
    notify('voicemail', 'New voicemail', 'From ${v.remoteE164}');
  }

  void updateVoicemail(Voicemail v) {
    _update(_state.copyWith(
        voicemails: _state.voicemails.map((x) => x.id == v.id ? v : x).toList()));
  }

  // ---- Campaigns / CRM ----
  void updateCampaign(Campaign c) {
    _update(_state.copyWith(
        campaigns: _state.campaigns.map((x) => x.id == c.id ? c : x).toList()),
        journalEntity: 'campaign', journalId: c.id, op: 'update');
  }

  void upsertDeal(PipelineDeal d) {
    final list = [..._state.deals];
    final i = list.indexWhere((x) => x.id == d.id);
    if (i >= 0) {
      list[i] = d;
    } else {
      list.add(d);
    }
    _update(_state.copyWith(deals: list), journalEntity: 'deal', journalId: d.id);
  }

  void upsertAppointment(Appointment a) {
    final list = [..._state.appointments];
    final i = list.indexWhere((x) => x.id == a.id);
    if (i >= 0) {
      list[i] = a;
    } else {
      list.add(a);
    }
    _update(_state.copyWith(appointments: list),
        journalEntity: 'appointment', journalId: a.id, log: 'appointment ${a.id} ${a.status.name}');
  }

  void upsertCallback(CallbackTask t) {
    final list = [..._state.callbacks];
    final i = list.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      list[i] = t;
    } else {
      list.add(t);
    }
    _update(_state.copyWith(callbacks: list), journalEntity: 'callback', journalId: t.id);
  }

  // ---- Handoffs ----
  void addHandoff(HandoffEvent e) {
    final calls = _state.calls.map((c) {
      if (c.id != e.callRecordId) return c;
      return c.copyWith(handoffEventIds: [...c.handoffEventIds, e.id]);
    }).toList();
    _update(_state.copyWith(handoffs: [..._state.handoffs, e], calls: calls),
        journalEntity: 'handoff', journalId: e.id, op: 'create',
        log: 'handoff ${e.kind.name}: ${e.fromParty} -> ${e.toParty}');
  }

  // ---- Devices ----
  void updateDevice(DeviceRecord d) {
    _update(_state.copyWith(
        devices: _state.devices.map((x) => x.id == d.id ? d : x).toList()));
  }

  // ---- Integrations ----
  void updateIntegration(IntegrationCard c) {
    _update(_state.copyWith(
        integrations: _state.integrations.map((x) => x.id == c.id ? c : x).toList()),
        log: 'integration ${c.provider}: ${c.state.name}');
  }

  // ---- Notifications ----
  void notify(String kind, String title, String body) {
    _update(_state.copyWith(notifications: [
      AppNotification(
          id: newId('nt'), kind: kind, title: title, body: body, at: DateTime.now()),
      ..._state.notifications,
    ]));
  }

  void markNotificationRead(String id) {
    _update(_state.copyWith(
        notifications: _state.notifications
            .map((n) => n.id == id ? n.copyWith(read: true) : n)
            .toList()));
  }

  // ---- Settings ----
  void setSetting(String key, String value) {
    _update(_state.copyWith(settings: {..._state.settings, key: value}));
  }

  // ---- Backup / restore / reset ----
  Future<String> backup() async {
    await _persist();
    return store.backupTo(DateTime.now().millisecondsSinceEpoch.toString());
  }

  Future<void> restore(String path) async {
    await store.restoreFrom(path);
    final snap = await store.load();
    if (snap != null) {
      _state = AppState.fromJson(snap);
      _changes.add(_state);
    }
  }

  Future<void> resetDemoData() async {
    _state = buildDemoSeed();
    _changes.add(_state);
    await _persist();
  }

  Future<void> deleteAllData() async {
    _state = const AppState();
    _changes.add(_state);
    await store.wipe();
  }

  void dispose() {
    _changes.close();
  }
}
