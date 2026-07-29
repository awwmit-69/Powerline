import 'twilio_messaging_client.dart';

TwilioMessagingClient createTwilioMessagingClient() =>
    _UnsupportedTwilioMessagingClient();

class _UnsupportedTwilioMessagingClient implements TwilioMessagingClient {
  @override
  Future<String> send({
    required String endpoint,
    required String to,
    required String from,
    required String body,
  }) {
    throw UnsupportedError('Live SMS is unavailable on this platform.');
  }
}
