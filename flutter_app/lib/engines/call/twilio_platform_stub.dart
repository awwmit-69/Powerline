import 'twilio_platform_contract.dart';

TwilioPlatform createTwilioPlatform() => _UnsupportedTwilioPlatform();

class _UnsupportedTwilioPlatform implements TwilioPlatform {
  Never _unsupported() => throw UnsupportedError(
        'Twilio browser calling is available on PowerLine Web only.',
      );

  @override
  Future<void> initialize(
    String tokenUrl,
    TwilioStateCallback onState,
    TwilioErrorCallback onError,
  ) async =>
      _unsupported();
  @override
  Future<String> placeCall(String destination) async => _unsupported();
  @override
  void hangup() => _unsupported();
  @override
  void mute(bool muted) => _unsupported();
  @override
  void sendDigits(String digits) => _unsupported();
  @override
  void dispose() {}
}
