import 'dart:convert';
import 'dart:io';

import 'twilio_messaging_client.dart';

TwilioMessagingClient createTwilioMessagingClient() =>
    _IoTwilioMessagingClient();

class _IoTwilioMessagingClient implements TwilioMessagingClient {
  @override
  Future<String> send({
    required String endpoint,
    required String to,
    required String from,
    required String body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'to': to, 'from': from, 'body': body}));
      final response = await request.close();
      final payloadText = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'SMS service returned ${response.statusCode}: $payloadText',
        );
      }
      final payload = jsonDecode(payloadText) as Map<String, dynamic>;
      final sid = payload['sid']?.toString();
      if (sid == null || sid.isEmpty) {
        throw const FormatException(
          'SMS service did not return a message SID.',
        );
      }
      return sid;
    } finally {
      client.close(force: true);
    }
  }
}
