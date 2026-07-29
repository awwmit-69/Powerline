import 'twilio_messaging_client_stub.dart'
    if (dart.library.io) 'twilio_messaging_client_io.dart'
    if (dart.library.html) 'twilio_messaging_client_web.dart' as implementation;

abstract class TwilioMessagingClient {
  Future<String> send({
    required String endpoint,
    required String to,
    required String from,
    required String body,
  });
}

TwilioMessagingClient createTwilioMessagingClient() =>
    implementation.createTwilioMessagingClient();
