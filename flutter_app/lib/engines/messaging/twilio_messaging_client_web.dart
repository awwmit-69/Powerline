// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html';
import 'dart:math';

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
    final uri = Uri.parse(endpoint);
    final target = Uri.base.resolveUri(uri);
    if (target.origin != Uri.base.origin || target.scheme != 'https') {
      throw StateError('Messaging requires an HTTPS service on this origin.');
    }
    final random = Random.secure();
    final suffix = List.generate(4, (_) => random.nextInt(1 << 30)).join('_');
    final requestId = '${DateTime.now().microsecondsSinceEpoch}_$suffix';
    final response = await HttpRequest.request(
      endpoint,
      method: 'POST',
      requestHeaders: {
        'Content-Type': 'application/json',
        'Idempotency-Key': requestId,
      },
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

