typedef TwilioStateCallback = void Function(String state, String callId);
typedef TwilioErrorCallback = void Function(String message);

abstract class TwilioPlatform {
  Future<void> initialize(
    String tokenUrl,
    TwilioStateCallback onState,
    TwilioErrorCallback onError,
  );

  Future<String> placeCall(String destination);
  void hangup();
  void mute(bool muted);
  void sendDigits(String digits);
  void dispose();
}
