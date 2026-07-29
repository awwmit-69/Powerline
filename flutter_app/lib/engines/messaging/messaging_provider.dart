/// Messaging provider abstraction + demo/mock implementations.
library;

import 'dart:async';

import '../call/call_engine.dart' show EngineStatus;
import 'twilio_messaging_client.dart';

class OutboundMessageRequest {
  final String to;
  final String from;
  final String body;
  final List<String> mediaRefs;
  const OutboundMessageRequest({
    required this.to,
    required this.from,
    required this.body,
    this.mediaRefs = const [],
  });
}

class MessagingEvent {
  final String kind; // delivery | failure | inbound | opt-out
  final String messageId;
  final String? body;
  final String? from;
  final String? error;
  const MessagingEvent({
    required this.kind,
    required this.messageId,
    this.body,
    this.from,
    this.error,
  });
}

abstract class MessagingProvider {
  String get providerId;
  EngineStatus get status;
  Stream<MessagingEvent> get events;
  Future<String> sendSms(OutboundMessageRequest req);
  Future<String> sendMms(OutboundMessageRequest req);

  /// Maps a provider-specific inbound webhook payload to a normalized event.
  MessagingEvent mapInboundWebhook(Map<String, dynamic> payload);
  Future<void> dispose();
}

/// Local demo provider: sends nothing over the wire and simulates delivery
/// receipts and replies. Never contacts real numbers.
class DemoMessagingProvider implements MessagingProvider {
  final _events = StreamController<MessagingEvent>.broadcast();
  final Duration tick;
  int _seq = 0;
  bool autoReply;

  DemoMessagingProvider({
    this.tick = const Duration(milliseconds: 600),
    this.autoReply = true,
  });

  @override
  String get providerId => 'demo';

  @override
  EngineStatus get status => const EngineStatus(
        provider: 'Demo messaging (local simulation)',
        mockMode: true,
        connected: false,
        missingConfiguration: ['None — demo only'],
        simulatedCapabilities: [
          'sms',
          'mms-placeholder',
          'delivery-receipts',
          'simulated-replies',
          'opt-out-keywords',
        ],
        unsupportedCapabilities: ['real SMS/MMS traffic'],
      );

  @override
  Stream<MessagingEvent> get events => _events.stream;

  @override
  Future<String> sendSms(OutboundMessageRequest req) async {
    final id = 'demomsg_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
    unawaited(_simulate(id, req));
    return id;
  }

  Future<void> _simulate(String id, OutboundMessageRequest req) async {
    await Future<void>.delayed(tick);
    _events.add(MessagingEvent(kind: 'delivery', messageId: id));
    if (autoReply) {
      await Future<void>.delayed(tick * 2);
      _events.add(
        MessagingEvent(
          kind: 'inbound',
          messageId: 'reply_$id',
          from: req.to,
          body: _cannedReply(req.body),
        ),
      );
    }
  }

  String _cannedReply(String outbound) {
    final lower = outbound.toLowerCase();
    if (lower.contains('appointment') || lower.contains('schedule')) {
      return 'Thursday works for me. (Simulated demo reply)';
    }
    if (lower.contains('price') || lower.contains('quote')) {
      return 'What would a typical estimate look like? (Simulated demo reply)';
    }
    return 'Got it, thanks for the info. (Simulated demo reply)';
  }

  @override
  Future<String> sendMms(OutboundMessageRequest req) => sendSms(req);

  @override
  MessagingEvent mapInboundWebhook(Map<String, dynamic> payload) =>
      MessagingEvent(
        kind: 'inbound',
        messageId: payload['id']?.toString() ?? 'demo-in',
        from: payload['from']?.toString(),
        body: payload['body']?.toString(),
      );

  @override
  Future<void> dispose() async => _events.close();
}

class MockMessagingProvider implements MessagingProvider {
  final String _id;
  final String displayName;
  final List<String> requiredConfig;
  final _events = StreamController<MessagingEvent>.broadcast();

  MockMessagingProvider(this._id, this.displayName, this.requiredConfig);

  @override
  String get providerId => _id;

  @override
  EngineStatus get status => EngineStatus(
        provider: displayName,
        mockMode: true,
        connected: false,
        missingConfiguration: requiredConfig,
        simulatedCapabilities: const ['inbound-webhook-mapping'],
        unsupportedCapabilities: const ['live SMS/MMS'],
      );

  @override
  Stream<MessagingEvent> get events => _events.stream;

  Never _blocked() => throw UnsupportedError(
        '$displayName is not configured (mock). Required: ${requiredConfig.join(', ')}',
      );

  @override
  Future<String> sendSms(OutboundMessageRequest req) async => _blocked();
  @override
  Future<String> sendMms(OutboundMessageRequest req) async => _blocked();

  @override
  MessagingEvent mapInboundWebhook(Map<String, dynamic> payload) {
    // Twilio-shaped payloads use MessageSid/From/Body; generic uses id/from/body.
    final id = payload['MessageSid'] ??
        payload['messageId'] ??
        payload['id'] ??
        'unknown';
    final from = payload['From'] ?? payload['from'];
    final body = payload['Body'] ?? payload['body'];
    final optOut = body is String &&
        const [
          'stop',
          'unsubscribe',
          'stopall',
          'cancel',
          'end',
          'quit',
        ].contains(body.trim().toLowerCase());
    return MessagingEvent(
      kind: optOut ? 'opt-out' : 'inbound',
      messageId: id.toString(),
      from: from?.toString(),
      body: body?.toString(),
    );
  }

  @override
  Future<void> dispose() async => _events.close();
}

class TwilioMessagingProvider implements MessagingProvider {
  final String endpoint;
  final TwilioMessagingClient _client;
  final _events = StreamController<MessagingEvent>.broadcast();

  TwilioMessagingProvider({
    this.endpoint = 'https://powerline-voice-2020.twil.io/sms',
    TwilioMessagingClient? client,
  }) : _client = client ?? createTwilioMessagingClient();

  @override
  String get providerId => 'twilio';

  @override
  EngineStatus get status => const EngineStatus(
        provider: 'Twilio Messaging',
        mockMode: false,
        connected: true,
        missingConfiguration: [],
        simulatedCapabilities: [],
        unsupportedCapabilities: ['MMS attachments'],
      );

  @override
  Stream<MessagingEvent> get events => _events.stream;

  @override
  Future<String> sendSms(OutboundMessageRequest req) async {
    try {
      final sid = await _client.send(
        endpoint: endpoint,
        to: req.to,
        from: req.from,
        body: req.body,
      );
      _events.add(MessagingEvent(kind: 'delivery', messageId: sid));
      return sid;
    } catch (error) {
      _events.add(
        MessagingEvent(
          kind: 'failure',
          messageId: '',
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<String> sendMms(OutboundMessageRequest req) {
    throw UnsupportedError('Live MMS attachments are not enabled yet.');
  }

  @override
  MessagingEvent mapInboundWebhook(Map<String, dynamic> payload) {
    final body = payload['Body']?.toString() ?? payload['body']?.toString();
    final normalized = body?.trim().toLowerCase();
    final optOut = const {
      'stop',
      'unsubscribe',
      'stopall',
      'cancel',
      'end',
      'quit',
    }.contains(normalized);
    return MessagingEvent(
      kind: optOut ? 'opt-out' : 'inbound',
      messageId: payload['MessageSid']?.toString() ??
          payload['messageId']?.toString() ??
          'twilio-inbound',
      from: payload['From']?.toString() ?? payload['from']?.toString(),
      body: body,
    );
  }

  @override
  Future<void> dispose() => _events.close();
}

MockMessagingProvider mockSignalMashMessaging() => MockMessagingProvider(
      'signalmash',
      'SignalMash Messaging',
      ['API key', '10DLC campaign'],
    );
MockMessagingProvider mockTwilioMessaging() => MockMessagingProvider(
      'twilio',
      'Twilio Messaging',
      ['Account SID', 'Auth token', 'Messaging Service SID'],
    );
MockMessagingProvider mockVonageMessaging() => MockMessagingProvider(
      'vonage',
      'Vonage Messages API',
      ['API key', 'API secret'],
    );
MockMessagingProvider mockSipMessaging() => MockMessagingProvider(
      'sip-simple',
      'SIP SIMPLE messaging',
      ['SIP registration'],
    );
MockMessagingProvider externalWebhookMessaging() => MockMessagingProvider(
      'generic-webhook',
      'Generic webhook provider',
      ['Webhook URL', 'Signing secret'],
    );
