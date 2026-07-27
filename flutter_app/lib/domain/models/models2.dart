/// Powerline domain models, part 2: campaigns, CRM, AI, routing, devices.
library;

import 'enums.dart';

String _s(dynamic v, [String d = '']) => v is String ? v : d;
int _i(dynamic v, [int d = 0]) => v is int ? v : (v is num ? v.toInt() : d);
bool _b(dynamic v, [bool d = false]) => v is bool ? v : d;
List<String> _ls(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];
T _enum<T>(List<T> values, dynamic v, T d) {
  if (v is String) {
    for (final e in values) {
      if (e.toString().split('.').last == v) return e;
    }
  }
  return d;
}

String _en(Object e) => e.toString().split('.').last;

class Campaign {
  final String id;
  final String name;
  final String description;
  final String offer;
  final String industry;
  final CampaignStatus status;
  final String timeZone;
  final List<String> assignedNumberIds;
  final List<String> assignedUserIds;
  final List<String> assignedAgentIds;
  final List<String> leadContactIds;
  final String callScript;
  final List<String> messageTemplates;
  final Map<String, String> objectionLibrary;
  final List<String> dispositions;
  final int dailyLimit;
  final int callingHourStart; // local hour, inclusive
  final int callingHourEnd; // local hour, exclusive
  final DateTime createdAt;

  const Campaign({
    required this.id,
    required this.name,
    this.description = '',
    this.offer = '',
    this.industry = '',
    this.status = CampaignStatus.draft,
    this.timeZone = 'America/Chicago',
    this.assignedNumberIds = const [],
    this.assignedUserIds = const [],
    this.assignedAgentIds = const [],
    this.leadContactIds = const [],
    this.callScript = '',
    this.messageTemplates = const [],
    this.objectionLibrary = const {},
    this.dispositions = const ['contacted', 'appointment-set', 'callback', 'not-interested', 'no-answer', 'dnc'],
    this.dailyLimit = 100,
    this.callingHourStart = 9,
    this.callingHourEnd = 20,
    required this.createdAt,
  });

  Campaign copyWith({CampaignStatus? status, List<String>? leadContactIds}) => Campaign(
        id: id,
        name: name,
        description: description,
        offer: offer,
        industry: industry,
        status: status ?? this.status,
        timeZone: timeZone,
        assignedNumberIds: assignedNumberIds,
        assignedUserIds: assignedUserIds,
        assignedAgentIds: assignedAgentIds,
        leadContactIds: leadContactIds ?? this.leadContactIds,
        callScript: callScript,
        messageTemplates: messageTemplates,
        objectionLibrary: objectionLibrary,
        dispositions: dispositions,
        dailyLimit: dailyLimit,
        callingHourStart: callingHourStart,
        callingHourEnd: callingHourEnd,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'offer': offer,
        'industry': industry,
        'status': _en(status),
        'timeZone': timeZone,
        'assignedNumberIds': assignedNumberIds,
        'assignedUserIds': assignedUserIds,
        'assignedAgentIds': assignedAgentIds,
        'leadContactIds': leadContactIds,
        'callScript': callScript,
        'messageTemplates': messageTemplates,
        'objectionLibrary': objectionLibrary,
        'dispositions': dispositions,
        'dailyLimit': dailyLimit,
        'callingHourStart': callingHourStart,
        'callingHourEnd': callingHourEnd,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Campaign.fromJson(Map<String, dynamic> j) => Campaign(
        id: _s(j['id']),
        name: _s(j['name']),
        description: _s(j['description']),
        offer: _s(j['offer']),
        industry: _s(j['industry']),
        status: _enum(CampaignStatus.values, j['status'], CampaignStatus.draft),
        timeZone: _s(j['timeZone'], 'America/Chicago'),
        assignedNumberIds: _ls(j['assignedNumberIds']),
        assignedUserIds: _ls(j['assignedUserIds']),
        assignedAgentIds: _ls(j['assignedAgentIds']),
        leadContactIds: _ls(j['leadContactIds']),
        callScript: _s(j['callScript']),
        messageTemplates: _ls(j['messageTemplates']),
        objectionLibrary: (j['objectionLibrary'] as Map? ?? {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        dispositions: _ls(j['dispositions']),
        dailyLimit: _i(j['dailyLimit'], 100),
        callingHourStart: _i(j['callingHourStart'], 9),
        callingHourEnd: _i(j['callingHourEnd'], 20),
        createdAt: DateTime.tryParse(_s(j['createdAt'])) ?? DateTime.now(),
      );
}

class PipelineDeal {
  final String id;
  final String contactId;
  final String? campaignId;
  final PipelineStage stage;
  final double value;
  final DateTime? expectedClose;
  final String nextAction;
  final String notes;
  final String? ownerId;
  final String? aiAgentId;

  const PipelineDeal({
    required this.id,
    required this.contactId,
    this.campaignId,
    this.stage = PipelineStage.newLead,
    this.value = 0,
    this.expectedClose,
    this.nextAction = '',
    this.notes = '',
    this.ownerId,
    this.aiAgentId,
  });

  PipelineDeal copyWith({PipelineStage? stage, double? value, String? nextAction, String? notes}) =>
      PipelineDeal(
        id: id,
        contactId: contactId,
        campaignId: campaignId,
        stage: stage ?? this.stage,
        value: value ?? this.value,
        expectedClose: expectedClose,
        nextAction: nextAction ?? this.nextAction,
        notes: notes ?? this.notes,
        ownerId: ownerId,
        aiAgentId: aiAgentId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'contactId': contactId,
        'campaignId': campaignId,
        'stage': _en(stage),
        'value': value,
        'expectedClose': expectedClose?.toIso8601String(),
        'nextAction': nextAction,
        'notes': notes,
        'ownerId': ownerId,
        'aiAgentId': aiAgentId,
      };

  factory PipelineDeal.fromJson(Map<String, dynamic> j) => PipelineDeal(
        id: _s(j['id']),
        contactId: _s(j['contactId']),
        campaignId: j['campaignId'] as String?,
        stage: _enum(PipelineStage.values, j['stage'], PipelineStage.newLead),
        value: (j['value'] as num?)?.toDouble() ?? 0,
        expectedClose: DateTime.tryParse(_s(j['expectedClose'])),
        nextAction: _s(j['nextAction']),
        notes: _s(j['notes']),
        ownerId: j['ownerId'] as String?,
        aiAgentId: j['aiAgentId'] as String?,
      );
}

class Appointment {
  final String id;
  final String contactId;
  final String? campaignId;
  final DateTime startsAt;
  final String timeZone;
  final String kind;
  final String? address;
  final String? meetingLink;
  final String? repUserId;
  final String? aiAgentId;
  final AppointmentStatus status;
  final bool reminderSent;
  final bool confirmed;
  final String notes;

  const Appointment({
    required this.id,
    required this.contactId,
    this.campaignId,
    required this.startsAt,
    this.timeZone = 'America/Chicago',
    this.kind = 'inspection',
    this.address,
    this.meetingLink,
    this.repUserId,
    this.aiAgentId,
    this.status = AppointmentStatus.scheduled,
    this.reminderSent = false,
    this.confirmed = false,
    this.notes = '',
  });

  Appointment copyWith({AppointmentStatus? status, bool? reminderSent, bool? confirmed, DateTime? startsAt, String? notes}) =>
      Appointment(
        id: id,
        contactId: contactId,
        campaignId: campaignId,
        startsAt: startsAt ?? this.startsAt,
        timeZone: timeZone,
        kind: kind,
        address: address,
        meetingLink: meetingLink,
        repUserId: repUserId,
        aiAgentId: aiAgentId,
        status: status ?? this.status,
        reminderSent: reminderSent ?? this.reminderSent,
        confirmed: confirmed ?? this.confirmed,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'contactId': contactId,
        'campaignId': campaignId,
        'startsAt': startsAt.toIso8601String(),
        'timeZone': timeZone,
        'kind': kind,
        'address': address,
        'meetingLink': meetingLink,
        'repUserId': repUserId,
        'aiAgentId': aiAgentId,
        'status': _en(status),
        'reminderSent': reminderSent,
        'confirmed': confirmed,
        'notes': notes,
      };

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: _s(j['id']),
        contactId: _s(j['contactId']),
        campaignId: j['campaignId'] as String?,
        startsAt: DateTime.tryParse(_s(j['startsAt'])) ?? DateTime.now(),
        timeZone: _s(j['timeZone'], 'America/Chicago'),
        kind: _s(j['kind'], 'inspection'),
        address: j['address'] as String?,
        meetingLink: j['meetingLink'] as String?,
        repUserId: j['repUserId'] as String?,
        aiAgentId: j['aiAgentId'] as String?,
        status: _enum(AppointmentStatus.values, j['status'], AppointmentStatus.scheduled),
        reminderSent: _b(j['reminderSent']),
        confirmed: _b(j['confirmed']),
        notes: _s(j['notes']),
      );
}

class CallbackTask {
  final String id;
  final String contactId;
  final String? campaignId;
  final DateTime dueAt;
  final String reason;
  final bool done;

  const CallbackTask({
    required this.id,
    required this.contactId,
    this.campaignId,
    required this.dueAt,
    this.reason = '',
    this.done = false,
  });

  CallbackTask copyWith({bool? done, DateTime? dueAt}) => CallbackTask(
      id: id, contactId: contactId, campaignId: campaignId, dueAt: dueAt ?? this.dueAt, reason: reason, done: done ?? this.done);

  Map<String, dynamic> toJson() => {
        'id': id, 'contactId': contactId, 'campaignId': campaignId,
        'dueAt': dueAt.toIso8601String(), 'reason': reason, 'done': done,
      };

  factory CallbackTask.fromJson(Map<String, dynamic> j) => CallbackTask(
        id: _s(j['id']),
        contactId: _s(j['contactId']),
        campaignId: j['campaignId'] as String?,
        dueAt: DateTime.tryParse(_s(j['dueAt'])) ?? DateTime.now(),
        reason: _s(j['reason']),
        done: _b(j['done']),
      );
}

class AiAgent {
  final String id;
  final String name;
  final String description;
  final String status; // test-mode | enabled | disabled
  final String role; // inbound | outbound
  final String voiceProvider; // placeholder id
  final String llmProvider; // placeholder id
  final List<String> assignedNumberIds;
  final List<String> assignedCampaignIds;
  final String greeting;
  final String systemPrompt;
  final List<String> knowledgeSources;
  final List<String> qualificationGoals;
  final List<String> allowedActions;
  final List<String> forbiddenActions;
  final List<String> escalationConditions;
  final String handoffDestination;
  final bool recordingEnabled;
  final bool transcriptionEnabled;
  final int workingHourStart;
  final int workingHourEnd;
  final int dailyCallLimit;
  final bool honorsDnc;
  final bool consentRequired;
  final bool testMode;

  const AiAgent({
    required this.id,
    required this.name,
    this.description = '',
    this.status = 'test-mode',
    this.role = 'inbound',
    this.voiceProvider = 'mock-voice',
    this.llmProvider = 'mock-llm',
    this.assignedNumberIds = const [],
    this.assignedCampaignIds = const [],
    this.greeting = '',
    this.systemPrompt = '',
    this.knowledgeSources = const [],
    this.qualificationGoals = const [],
    this.allowedActions = const ['answer-questions', 'book-appointment', 'take-message'],
    this.forbiddenActions = const ['quote-final-price', 'legal-advice', 'payment-collection'],
    this.escalationConditions = const ['caller-requests-human', 'repeated-misunderstanding', 'complaint'],
    this.handoffDestination = 'ring-group:sales',
    this.recordingEnabled = false,
    this.transcriptionEnabled = true,
    this.workingHourStart = 8,
    this.workingHourEnd = 20,
    this.dailyCallLimit = 50,
    this.honorsDnc = true,
    this.consentRequired = true,
    this.testMode = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'description': description, 'status': status, 'role': role,
        'voiceProvider': voiceProvider, 'llmProvider': llmProvider,
        'assignedNumberIds': assignedNumberIds, 'assignedCampaignIds': assignedCampaignIds,
        'greeting': greeting, 'systemPrompt': systemPrompt, 'knowledgeSources': knowledgeSources,
        'qualificationGoals': qualificationGoals, 'allowedActions': allowedActions,
        'forbiddenActions': forbiddenActions, 'escalationConditions': escalationConditions,
        'handoffDestination': handoffDestination, 'recordingEnabled': recordingEnabled,
        'transcriptionEnabled': transcriptionEnabled, 'workingHourStart': workingHourStart,
        'workingHourEnd': workingHourEnd, 'dailyCallLimit': dailyCallLimit, 'honorsDnc': honorsDnc,
        'consentRequired': consentRequired, 'testMode': testMode,
      };

  factory AiAgent.fromJson(Map<String, dynamic> j) => AiAgent(
        id: _s(j['id']),
        name: _s(j['name']),
        description: _s(j['description']),
        status: _s(j['status'], 'test-mode'),
        role: _s(j['role'], 'inbound'),
        voiceProvider: _s(j['voiceProvider'], 'mock-voice'),
        llmProvider: _s(j['llmProvider'], 'mock-llm'),
        assignedNumberIds: _ls(j['assignedNumberIds']),
        assignedCampaignIds: _ls(j['assignedCampaignIds']),
        greeting: _s(j['greeting']),
        systemPrompt: _s(j['systemPrompt']),
        knowledgeSources: _ls(j['knowledgeSources']),
        qualificationGoals: _ls(j['qualificationGoals']),
        allowedActions: _ls(j['allowedActions']),
        forbiddenActions: _ls(j['forbiddenActions']),
        escalationConditions: _ls(j['escalationConditions']),
        handoffDestination: _s(j['handoffDestination'], 'ring-group:sales'),
        recordingEnabled: _b(j['recordingEnabled']),
        transcriptionEnabled: _b(j['transcriptionEnabled'], true),
        workingHourStart: _i(j['workingHourStart'], 8),
        workingHourEnd: _i(j['workingHourEnd'], 20),
        dailyCallLimit: _i(j['dailyCallLimit'], 50),
        honorsDnc: _b(j['honorsDnc'], true),
        consentRequired: _b(j['consentRequired'], true),
        testMode: _b(j['testMode'], true),
      );
}

class DeviceRecord {
  final String id;
  final String name;
  final DeviceType type;
  final DateTime lastActive;
  final String pushStatus; // registered | unregistered | n/a-demo
  final bool ringEnabled;
  final bool messageNotifications;
  final bool voicemailNotifications;
  final bool revoked;
  final bool isThisDevice;

  const DeviceRecord({
    required this.id,
    required this.name,
    required this.type,
    required this.lastActive,
    this.pushStatus = 'n/a-demo',
    this.ringEnabled = true,
    this.messageNotifications = true,
    this.voicemailNotifications = true,
    this.revoked = false,
    this.isThisDevice = false,
  });

  DeviceRecord copyWith({bool? ringEnabled, bool? messageNotifications, bool? voicemailNotifications, bool? revoked, DateTime? lastActive}) =>
      DeviceRecord(
        id: id, name: name, type: type, lastActive: lastActive ?? this.lastActive,
        pushStatus: pushStatus, ringEnabled: ringEnabled ?? this.ringEnabled,
        messageNotifications: messageNotifications ?? this.messageNotifications,
        voicemailNotifications: voicemailNotifications ?? this.voicemailNotifications,
        revoked: revoked ?? this.revoked, isThisDevice: isThisDevice,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'type': _en(type), 'lastActive': lastActive.toIso8601String(),
        'pushStatus': pushStatus, 'ringEnabled': ringEnabled,
        'messageNotifications': messageNotifications, 'voicemailNotifications': voicemailNotifications,
        'revoked': revoked, 'isThisDevice': isThisDevice,
      };

  factory DeviceRecord.fromJson(Map<String, dynamic> j) => DeviceRecord(
        id: _s(j['id']),
        name: _s(j['name']),
        type: _enum(DeviceType.values, j['type'], DeviceType.webSession),
        lastActive: DateTime.tryParse(_s(j['lastActive'])) ?? DateTime.now(),
        pushStatus: _s(j['pushStatus'], 'n/a-demo'),
        ringEnabled: _b(j['ringEnabled'], true),
        messageNotifications: _b(j['messageNotifications'], true),
        voicemailNotifications: _b(j['voicemailNotifications'], true),
        revoked: _b(j['revoked']),
        isThisDevice: _b(j['isThisDevice']),
      );
}

class BusinessHours {
  /// weekday (1=Mon..7=Sun) -> list of [startHour, endHour) windows.
  final Map<int, List<List<int>>> weekly;
  final String timeZone;
  final List<String> holidays; // ISO dates
  final bool temporarilyClosed;
  final String afterHoursBehavior; // voicemail | ai-agent | forward

  const BusinessHours({
    this.weekly = const {
      1: [[9, 17]], 2: [[9, 17]], 3: [[9, 17]], 4: [[9, 17]], 5: [[9, 17]],
    },
    this.timeZone = 'America/Chicago',
    this.holidays = const [],
    this.temporarilyClosed = false,
    this.afterHoursBehavior = 'voicemail',
  });

  bool isOpenAt(DateTime local) {
    if (temporarilyClosed) return false;
    final dateStr =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    if (holidays.contains(dateStr)) return false;
    final windows = weekly[local.weekday] ?? const [];
    for (final w in windows) {
      if (local.hour >= w[0] && local.hour < w[1]) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'weekly': weekly.map((k, v) => MapEntry(k.toString(), v)),
        'timeZone': timeZone,
        'holidays': holidays,
        'temporarilyClosed': temporarilyClosed,
        'afterHoursBehavior': afterHoursBehavior,
      };

  factory BusinessHours.fromJson(Map<String, dynamic> j) => BusinessHours(
        weekly: (j['weekly'] as Map? ?? {}).map((k, v) => MapEntry(
            int.tryParse(k.toString()) ?? 1,
            (v as List)
                .map((w) => (w as List).map((x) => _i(x)).toList())
                .toList())),
        timeZone: _s(j['timeZone'], 'America/Chicago'),
        holidays: _ls(j['holidays']),
        temporarilyClosed: _b(j['temporarilyClosed']),
        afterHoursBehavior: _s(j['afterHoursBehavior'], 'voicemail'),
      );
}

class HandoffEvent {
  final String id;
  final String callRecordId;
  final HandoffKind kind;
  final String reason;
  final String fromParty;
  final String toParty;
  final String whisperSummary;
  final DateTime createdAt;

  const HandoffEvent({
    required this.id,
    required this.callRecordId,
    required this.kind,
    this.reason = '',
    required this.fromParty,
    required this.toParty,
    this.whisperSummary = '',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'callRecordId': callRecordId, 'kind': _en(kind), 'reason': reason,
        'fromParty': fromParty, 'toParty': toParty, 'whisperSummary': whisperSummary,
        'createdAt': createdAt.toIso8601String(),
      };

  factory HandoffEvent.fromJson(Map<String, dynamic> j) => HandoffEvent(
        id: _s(j['id']),
        callRecordId: _s(j['callRecordId']),
        kind: _enum(HandoffKind.values, j['kind'], HandoffKind.aiEscalation),
        reason: _s(j['reason']),
        fromParty: _s(j['fromParty']),
        toParty: _s(j['toParty']),
        whisperSummary: _s(j['whisperSummary']),
        createdAt: DateTime.tryParse(_s(j['createdAt'])) ?? DateTime.now(),
      );
}

class DncRecord {
  final String id;
  final String e164;
  final String reason;
  final String source;
  final DateTime createdAt;
  const DncRecord({required this.id, required this.e164, this.reason = '', this.source = 'manual', required this.createdAt});
  Map<String, dynamic> toJson() =>
      {'id': id, 'e164': e164, 'reason': reason, 'source': source, 'createdAt': createdAt.toIso8601String()};
  factory DncRecord.fromJson(Map<String, dynamic> j) => DncRecord(
      id: _s(j['id']), e164: _s(j['e164']), reason: _s(j['reason']),
      source: _s(j['source'], 'manual'),
      createdAt: DateTime.tryParse(_s(j['createdAt'])) ?? DateTime.now());
}

class IntegrationCard {
  final String id;
  final String provider;
  final String category; // telephony | messaging | ai | transcription | calendar | crm
  final ProviderState state;
  final DateTime? lastTestAt;
  final String? lastTestResult;
  final String? lastError;
  final List<String> capabilities;
  final List<String> missingCapabilities;
  final List<String> configFields;
  /// Secrets are stored write-only; only field NAMES are kept in state.
  final List<String> configuredFieldNames;

  const IntegrationCard({
    required this.id,
    required this.provider,
    required this.category,
    this.state = ProviderState.notConfigured,
    this.lastTestAt,
    this.lastTestResult,
    this.lastError,
    this.capabilities = const [],
    this.missingCapabilities = const [],
    this.configFields = const [],
    this.configuredFieldNames = const [],
  });

  IntegrationCard copyWith({ProviderState? state, DateTime? lastTestAt, String? lastTestResult, String? lastError, List<String>? configuredFieldNames}) =>
      IntegrationCard(
        id: id, provider: provider, category: category, state: state ?? this.state,
        lastTestAt: lastTestAt ?? this.lastTestAt, lastTestResult: lastTestResult ?? this.lastTestResult,
        lastError: lastError ?? this.lastError, capabilities: capabilities,
        missingCapabilities: missingCapabilities, configFields: configFields,
        configuredFieldNames: configuredFieldNames ?? this.configuredFieldNames,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'provider': provider, 'category': category, 'state': _en(state),
        'lastTestAt': lastTestAt?.toIso8601String(), 'lastTestResult': lastTestResult,
        'lastError': lastError, 'capabilities': capabilities,
        'missingCapabilities': missingCapabilities, 'configFields': configFields,
        'configuredFieldNames': configuredFieldNames,
      };

  factory IntegrationCard.fromJson(Map<String, dynamic> j) => IntegrationCard(
        id: _s(j['id']),
        provider: _s(j['provider']),
        category: _s(j['category']),
        state: _enum(ProviderState.values, j['state'], ProviderState.notConfigured),
        lastTestAt: DateTime.tryParse(_s(j['lastTestAt'])),
        lastTestResult: j['lastTestResult'] as String?,
        lastError: j['lastError'] as String?,
        capabilities: _ls(j['capabilities']),
        missingCapabilities: _ls(j['missingCapabilities']),
        configFields: _ls(j['configFields']),
        configuredFieldNames: _ls(j['configuredFieldNames']),
      );
}

class AppNotification {
  final String id;
  final String kind;
  final String title;
  final String body;
  final DateTime at;
  final bool read;
  const AppNotification({required this.id, required this.kind, required this.title, required this.body, required this.at, this.read = false});
  AppNotification copyWith({bool? read}) =>
      AppNotification(id: id, kind: kind, title: title, body: body, at: at, read: read ?? this.read);
  Map<String, dynamic> toJson() =>
      {'id': id, 'kind': kind, 'title': title, 'body': body, 'at': at.toIso8601String(), 'read': read};
  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
      id: _s(j['id']), kind: _s(j['kind']), title: _s(j['title']), body: _s(j['body']),
      at: DateTime.tryParse(_s(j['at'])) ?? DateTime.now(), read: _b(j['read']));
}
