/// Powerline domain models: plain immutable Dart classes with JSON round-trip.
///
/// Deliberately hand-written (no freezed/json_serializable) because the build
/// sandbox cannot run codegen; the classes keep the same shape a generated
/// model would have.
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

class PhoneEntry {
  final String label;
  final String e164;
  const PhoneEntry({required this.label, required this.e164});
  Map<String, dynamic> toJson() => {'label': label, 'e164': e164};
  factory PhoneEntry.fromJson(Map<String, dynamic> j) =>
      PhoneEntry(label: _s(j['label'], 'mobile'), e164: _s(j['e164']));
}

class Contact {
  final String id;
  final String firstName;
  final String lastName;
  final String? companyId;
  final String? jobTitle;
  final List<PhoneEntry> phones;
  final List<String> emails;
  final List<String> tags;
  final String? timeZone;
  final bool dnc;
  final bool smsOptOut;
  final bool emailOptOut;
  final bool favorite;
  final bool archived;
  final String notes;
  final String? ownerId;
  final Map<String, String> customFields;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Contact({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.companyId,
    this.jobTitle,
    this.phones = const [],
    this.emails = const [],
    this.tags = const [],
    this.timeZone,
    this.dnc = false,
    this.smsOptOut = false,
    this.emailOptOut = false,
    this.favorite = false,
    this.archived = false,
    this.notes = '',
    this.ownerId,
    this.customFields = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  String get displayName => '$firstName $lastName'.trim();
  String? get primaryPhone => phones.isEmpty ? null : phones.first.e164;

  Contact copyWith({
    String? firstName,
    String? lastName,
    String? companyId,
    String? jobTitle,
    List<PhoneEntry>? phones,
    List<String>? emails,
    List<String>? tags,
    String? timeZone,
    bool? dnc,
    bool? smsOptOut,
    bool? emailOptOut,
    bool? favorite,
    bool? archived,
    String? notes,
    DateTime? updatedAt,
  }) =>
      Contact(
        id: id,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        companyId: companyId ?? this.companyId,
        jobTitle: jobTitle ?? this.jobTitle,
        phones: phones ?? this.phones,
        emails: emails ?? this.emails,
        tags: tags ?? this.tags,
        timeZone: timeZone ?? this.timeZone,
        dnc: dnc ?? this.dnc,
        smsOptOut: smsOptOut ?? this.smsOptOut,
        emailOptOut: emailOptOut ?? this.emailOptOut,
        favorite: favorite ?? this.favorite,
        archived: archived ?? this.archived,
        notes: notes ?? this.notes,
        ownerId: ownerId,
        customFields: customFields,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'companyId': companyId,
        'jobTitle': jobTitle,
        'phones': phones.map((p) => p.toJson()).toList(),
        'emails': emails,
        'tags': tags,
        'timeZone': timeZone,
        'dnc': dnc,
        'smsOptOut': smsOptOut,
        'emailOptOut': emailOptOut,
        'favorite': favorite,
        'archived': archived,
        'notes': notes,
        'ownerId': ownerId,
        'customFields': customFields,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        id: _s(j['id']),
        firstName: _s(j['firstName']),
        lastName: _s(j['lastName']),
        companyId: j['companyId'] as String?,
        jobTitle: j['jobTitle'] as String?,
        phones: (j['phones'] as List? ?? [])
            .map((e) => PhoneEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        emails: _ls(j['emails']),
        tags: _ls(j['tags']),
        timeZone: j['timeZone'] as String?,
        dnc: _b(j['dnc']),
        smsOptOut: _b(j['smsOptOut']),
        emailOptOut: _b(j['emailOptOut']),
        favorite: _b(j['favorite']),
        archived: _b(j['archived']),
        notes: _s(j['notes']),
        ownerId: j['ownerId'] as String?,
        customFields: (j['customFields'] as Map? ?? {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        createdAt: DateTime.tryParse(_s(j['createdAt'])) ?? DateTime.now(),
        updatedAt: DateTime.tryParse(_s(j['updatedAt'])) ?? DateTime.now(),
      );
}

class Company {
  final String id;
  final String name;
  final String? domain;
  final String? industry;
  const Company({required this.id, required this.name, this.domain, this.industry});
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'domain': domain, 'industry': industry};
  factory Company.fromJson(Map<String, dynamic> j) => Company(
      id: _s(j['id']),
      name: _s(j['name']),
      domain: j['domain'] as String?,
      industry: j['industry'] as String?);
}

class PowerlineNumber {
  final String id;
  final String e164;
  final String label;
  final String country;
  final String provider;
  final bool voiceEnabled;
  final bool smsEnabled;
  final bool mmsEnabled;
  final String e911Status; // not-configured | pending | validated
  final String cnamStatus;
  final String a2pStatus;
  final String tollFreeStatus;
  final List<String> assignedUserIds;
  final List<String> assignedAgentIds;
  final String status; // demo | active | released
  final bool isDemo;

  const PowerlineNumber({
    required this.id,
    required this.e164,
    required this.label,
    this.country = 'US',
    this.provider = 'demo',
    this.voiceEnabled = true,
    this.smsEnabled = true,
    this.mmsEnabled = true,
    this.e911Status = 'not-configured',
    this.cnamStatus = 'none',
    this.a2pStatus = 'unregistered',
    this.tollFreeStatus = 'n/a',
    this.assignedUserIds = const [],
    this.assignedAgentIds = const [],
    this.status = 'demo',
    this.isDemo = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'e164': e164,
        'label': label,
        'country': country,
        'provider': provider,
        'voiceEnabled': voiceEnabled,
        'smsEnabled': smsEnabled,
        'mmsEnabled': mmsEnabled,
        'e911Status': e911Status,
        'cnamStatus': cnamStatus,
        'a2pStatus': a2pStatus,
        'tollFreeStatus': tollFreeStatus,
        'assignedUserIds': assignedUserIds,
        'assignedAgentIds': assignedAgentIds,
        'status': status,
        'isDemo': isDemo,
      };

  factory PowerlineNumber.fromJson(Map<String, dynamic> j) => PowerlineNumber(
        id: _s(j['id']),
        e164: _s(j['e164']),
        label: _s(j['label']),
        country: _s(j['country'], 'US'),
        provider: _s(j['provider'], 'demo'),
        voiceEnabled: _b(j['voiceEnabled'], true),
        smsEnabled: _b(j['smsEnabled'], true),
        mmsEnabled: _b(j['mmsEnabled'], true),
        e911Status: _s(j['e911Status'], 'not-configured'),
        cnamStatus: _s(j['cnamStatus'], 'none'),
        a2pStatus: _s(j['a2pStatus'], 'unregistered'),
        tollFreeStatus: _s(j['tollFreeStatus'], 'n/a'),
        assignedUserIds: _ls(j['assignedUserIds']),
        assignedAgentIds: _ls(j['assignedAgentIds']),
        status: _s(j['status'], 'demo'),
        isDemo: _b(j['isDemo'], true),
      );
}

class Message {
  final String id;
  final String conversationId;
  final CallDirection direction; // inbound/outbound reuse
  final String body;
  final MessageState state;
  final String provider;
  final List<String> mediaRefs;
  final DateTime createdAt;
  final bool isDemo;

  const Message({
    required this.id,
    required this.conversationId,
    required this.direction,
    required this.body,
    required this.state,
    this.provider = 'demo',
    this.mediaRefs = const [],
    required this.createdAt,
    this.isDemo = true,
  });

  Message copyWith({MessageState? state}) => Message(
        id: id,
        conversationId: conversationId,
        direction: direction,
        body: body,
        state: state ?? this.state,
        provider: provider,
        mediaRefs: mediaRefs,
        createdAt: createdAt,
        isDemo: isDemo,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'direction': _en(direction),
        'body': body,
        'state': _en(state),
        'provider': provider,
        'mediaRefs': mediaRefs,
        'createdAt': createdAt.toIso8601String(),
        'isDemo': isDemo,
      };

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: _s(j['id']),
        conversationId: _s(j['conversationId']),
        direction: _enum(CallDirection.values, j['direction'], CallDirection.outbound),
        body: _s(j['body']),
        state: _enum(MessageState.values, j['state'], MessageState.sent),
        provider: _s(j['provider'], 'demo'),
        mediaRefs: _ls(j['mediaRefs']),
        createdAt: DateTime.tryParse(_s(j['createdAt'])) ?? DateTime.now(),
        isDemo: _b(j['isDemo'], true),
      );
}

class Conversation {
  final String id;
  final String? contactId;
  final String remoteE164;
  final String? powerlineNumberId;
  final String? campaignId;
  final int unreadCount;
  final bool pinned;
  final bool archived;
  final String draft;
  final DateTime? lastMessageAt;

  const Conversation({
    required this.id,
    this.contactId,
    required this.remoteE164,
    this.powerlineNumberId,
    this.campaignId,
    this.unreadCount = 0,
    this.pinned = false,
    this.archived = false,
    this.draft = '',
    this.lastMessageAt,
  });

  Conversation copyWith({
    int? unreadCount,
    bool? pinned,
    bool? archived,
    String? draft,
    DateTime? lastMessageAt,
    String? contactId,
  }) =>
      Conversation(
        id: id,
        contactId: contactId ?? this.contactId,
        remoteE164: remoteE164,
        powerlineNumberId: powerlineNumberId,
        campaignId: campaignId,
        unreadCount: unreadCount ?? this.unreadCount,
        pinned: pinned ?? this.pinned,
        archived: archived ?? this.archived,
        draft: draft ?? this.draft,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'contactId': contactId,
        'remoteE164': remoteE164,
        'powerlineNumberId': powerlineNumberId,
        'campaignId': campaignId,
        'unreadCount': unreadCount,
        'pinned': pinned,
        'archived': archived,
        'draft': draft,
        'lastMessageAt': lastMessageAt?.toIso8601String(),
      };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: _s(j['id']),
        contactId: j['contactId'] as String?,
        remoteE164: _s(j['remoteE164']),
        powerlineNumberId: j['powerlineNumberId'] as String?,
        campaignId: j['campaignId'] as String?,
        unreadCount: _i(j['unreadCount']),
        pinned: _b(j['pinned']),
        archived: _b(j['archived']),
        draft: _s(j['draft']),
        lastMessageAt: DateTime.tryParse(_s(j['lastMessageAt'])),
      );
}

class CallRecord {
  final String id;
  final CallDirection direction;
  final String? contactId;
  final String remoteE164;
  final String? powerlineNumberId;
  final String provider;
  final AgentKind agentKind;
  final String? aiAgentId;
  final String? campaignId;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final String? disposition;
  final String notes;
  final CallState finalState;
  final String? voicemailId;
  final List<String> handoffEventIds;
  final bool isDemo;

  const CallRecord({
    required this.id,
    required this.direction,
    this.contactId,
    required this.remoteE164,
    this.powerlineNumberId,
    this.provider = 'demo',
    this.agentKind = AgentKind.human,
    this.aiAgentId,
    this.campaignId,
    required this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.disposition,
    this.notes = '',
    this.finalState = CallState.completed,
    this.voicemailId,
    this.handoffEventIds = const [],
    this.isDemo = true,
  });

  bool get missed => direction == CallDirection.inbound && answeredAt == null;

  CallRecord copyWith({
    DateTime? answeredAt,
    DateTime? endedAt,
    int? durationSeconds,
    String? disposition,
    String? notes,
    CallState? finalState,
    String? voicemailId,
    List<String>? handoffEventIds,
  }) =>
      CallRecord(
        id: id,
        direction: direction,
        contactId: contactId,
        remoteE164: remoteE164,
        powerlineNumberId: powerlineNumberId,
        provider: provider,
        agentKind: agentKind,
        aiAgentId: aiAgentId,
        campaignId: campaignId,
        startedAt: startedAt,
        answeredAt: answeredAt ?? this.answeredAt,
        endedAt: endedAt ?? this.endedAt,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        disposition: disposition ?? this.disposition,
        notes: notes ?? this.notes,
        finalState: finalState ?? this.finalState,
        voicemailId: voicemailId ?? this.voicemailId,
        handoffEventIds: handoffEventIds ?? this.handoffEventIds,
        isDemo: isDemo,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'direction': _en(direction),
        'contactId': contactId,
        'remoteE164': remoteE164,
        'powerlineNumberId': powerlineNumberId,
        'provider': provider,
        'agentKind': _en(agentKind),
        'aiAgentId': aiAgentId,
        'campaignId': campaignId,
        'startedAt': startedAt.toIso8601String(),
        'answeredAt': answeredAt?.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'durationSeconds': durationSeconds,
        'disposition': disposition,
        'notes': notes,
        'finalState': _en(finalState),
        'voicemailId': voicemailId,
        'handoffEventIds': handoffEventIds,
        'isDemo': isDemo,
      };

  factory CallRecord.fromJson(Map<String, dynamic> j) => CallRecord(
        id: _s(j['id']),
        direction: _enum(CallDirection.values, j['direction'], CallDirection.outbound),
        contactId: j['contactId'] as String?,
        remoteE164: _s(j['remoteE164']),
        powerlineNumberId: j['powerlineNumberId'] as String?,
        provider: _s(j['provider'], 'demo'),
        agentKind: _enum(AgentKind.values, j['agentKind'], AgentKind.human),
        aiAgentId: j['aiAgentId'] as String?,
        campaignId: j['campaignId'] as String?,
        startedAt: DateTime.tryParse(_s(j['startedAt'])) ?? DateTime.now(),
        answeredAt: DateTime.tryParse(_s(j['answeredAt'])),
        endedAt: DateTime.tryParse(_s(j['endedAt'])),
        durationSeconds: _i(j['durationSeconds']),
        disposition: j['disposition'] as String?,
        notes: _s(j['notes']),
        finalState: _enum(CallState.values, j['finalState'], CallState.completed),
        voicemailId: j['voicemailId'] as String?,
        handoffEventIds: _ls(j['handoffEventIds']),
        isDemo: _b(j['isDemo'], true),
      );
}

class Voicemail {
  final String id;
  final String? callRecordId;
  final String remoteE164;
  final int durationSeconds;
  final String audioAsset;
  final String transcript;
  final double transcriptConfidence;
  final bool read;
  final bool archived;
  final String notes;
  final DateTime createdAt;

  const Voicemail({
    required this.id,
    this.callRecordId,
    required this.remoteE164,
    required this.durationSeconds,
    this.audioAsset = 'assets/audio/demo_voicemail.wav',
    this.transcript = '',
    this.transcriptConfidence = 0,
    this.read = false,
    this.archived = false,
    this.notes = '',
    required this.createdAt,
  });

  Voicemail copyWith({bool? read, bool? archived, String? transcript, double? transcriptConfidence, String? notes}) =>
      Voicemail(
        id: id,
        callRecordId: callRecordId,
        remoteE164: remoteE164,
        durationSeconds: durationSeconds,
        audioAsset: audioAsset,
        transcript: transcript ?? this.transcript,
        transcriptConfidence: transcriptConfidence ?? this.transcriptConfidence,
        read: read ?? this.read,
        archived: archived ?? this.archived,
        notes: notes ?? this.notes,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'callRecordId': callRecordId,
        'remoteE164': remoteE164,
        'durationSeconds': durationSeconds,
        'audioAsset': audioAsset,
        'transcript': transcript,
        'transcriptConfidence': transcriptConfidence,
        'read': read,
        'archived': archived,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Voicemail.fromJson(Map<String, dynamic> j) => Voicemail(
        id: _s(j['id']),
        callRecordId: j['callRecordId'] as String?,
        remoteE164: _s(j['remoteE164']),
        durationSeconds: _i(j['durationSeconds']),
        audioAsset: _s(j['audioAsset'], 'assets/audio/demo_voicemail.wav'),
        transcript: _s(j['transcript']),
        transcriptConfidence: (j['transcriptConfidence'] as num?)?.toDouble() ?? 0,
        read: _b(j['read']),
        archived: _b(j['archived']),
        notes: _s(j['notes']),
        createdAt: DateTime.tryParse(_s(j['createdAt'])) ?? DateTime.now(),
      );
}
