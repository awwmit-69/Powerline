// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html';

import 'twilio_messaging_client.dart';

TwilioMessagingClient createTwilioMessagingClient() =>
    _WebTwilioMessagingClient();

class _WebTwilioMessagingClient implements TwilioMessagingClient {
  @override
  Future<String> send({
    required String endpoint,
    required String to,
    required String from,
    required String body,
  }) async {
    final response = await HttpRequest.request(
      endpoint,
      method: 'POST',
      requestHeaders: {'Content-Type': 'application/json'},
      sendData: jsonEncode({'to': to, 'from': from, 'body': body}),
    );
    final payload =
        jsonDecode(response.responseText ?? '{}') as Map<String, dynamic>;
    final sid = payload['sid']?.toString();
    if (sid == null || sid.isEmpty) {
      throw const FormatException('SMS service did not return a message SID.');
    }
    return sid;
  }
}
