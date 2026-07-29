import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'twilio_platform_contract.dart';

TwilioPlatform createTwilioPlatform() => _NativeTwilioPlatform();

class _NativeTwilioPlatform implements TwilioPlatform {
  static const _channel = MethodChannel('com.azdglobal.powerline/voice');

  String? _tokenUrl;
  TwilioStateCallback? _onState;
  TwilioErrorCallback? _onError;

  @override
  Future<void> initialize(
    String tokenUrl,
    TwilioStateCallback onState,
    TwilioErrorCallback onError,
  ) async {
    _tokenUrl = tokenUrl;
    _onState = onState;
    _onError = onError;
    _channel.setMethodCallHandler((call) async {
      final arguments = Map<String, Object?>.from(
        call.arguments as Map? ?? const {},
      );
      switch (call.method) {
        case 'state':
          _onState?.call(
            arguments['state']?.toString() ?? 'failed',
            arguments['callId']?.toString() ?? '',
          );
          return;
        case 'error':
          _onError?.call(
            arguments['message']?.toString() ?? 'Unknown native call error',
          );
          return;
      }
    });
    await _channel.invokeMethod<void>('initialize');
  }

  Future<String> _fetchToken() async {
    final url = _tokenUrl;
    if (url == null) throw StateError('Twilio Voice is not initialized.');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Token service returned ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final payload = jsonDecode(body) as Map<String, Object?>;
      final token = payload['token']?.toString();
      if (token == null || token.isEmpty) {
        throw const FormatException('Token service did not return a token.');
      }
      return token;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String> placeCall(String destination) async {
    final callId = 'twilio_${DateTime.now().millisecondsSinceEpoch}';
    final token = await _fetchToken();
    final result = await _channel.invokeMethod<String>('placeCall', {
      'token': token,
      'destination': destination,
      'callId': callId,
    });
    return result ?? callId;
  }

  @override
  void hangup() => unawaited(_channel.invokeMethod<void>('hangup'));

  @override
  void mute(bool muted) => unawaited(
        _channel.invokeMethod<void>('mute', {'muted': muted}),
      );

  @override
  void sendDigits(String digits) => unawaited(
        _channel.invokeMethod<void>('sendDigits', {'digits': digits}),
      );

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_channel.invokeMethod<void>('dispose'));
  }
}
