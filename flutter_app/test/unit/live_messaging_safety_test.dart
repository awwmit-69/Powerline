import 'package:flutter_test/flutter_test.dart';
import 'package:powerline/engines/messaging/messaging_provider.dart';
import 'package:powerline/engines/messaging/twilio_messaging_client.dart';

class _Client implements TwilioMessagingClient {
  int sends = 0;

  @override
  Future<String> send({
    required String endpoint,
    required String to,
    required String from,
    required String body,
  }) async {
    sends++;
    return 'SMtest';
  }
}

const _request = OutboundMessageRequest(
  to: '+12025550123',
  from: '+12025550124',
  body: 'Test',
);

void main() {
  test('unconfigured live messaging never contacts a provider', () async {
    final client = _Client();
    final provider = TwilioMessagingProvider(endpoint: '', client: client);
    expect(provider.status.connected, isFalse);
    await expectLater(provider.sendSms(_request), throwsStateError);
    expect(client.sends, 0);
    await provider.dispose();
  });

  test('provider acceptance never fabricates delivery', () async {
    final client = _Client();
    final provider = TwilioMessagingProvider(
      endpoint: '/api/messages',
      client: client,
    );
    final events = <String>[];
    final sub = provider.events.listen((event) => events.add(event.kind));
    expect(await provider.sendSms(_request), 'SMtest');
    await Future<void>.delayed(Duration.zero);
    expect(events, ['accepted']);
    expect(client.sends, 1);
    expect(provider.status.connected, isFalse);
    await sub.cancel();
    await provider.dispose();
  });
}
