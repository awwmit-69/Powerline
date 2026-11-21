typedef TwilioStateCallback = void Function(String state, String callId);
typedef TwilioErrorCallback = void Function(String message);
typedef TwilioIncomingCallback = void Function(String callId, String from);

abstract class TwilioPlatform {
  /// Signs the agent in if needed, fetches a short-lived voice token from
  /// [tokenUrl], and registers this device for inbound calls.
  Future<void> initialize(
    String tokenUrl,
    TwilioStateCallback onState,
    TwilioErrorCallback onError,
    TwilioIncomingCallback onIncoming,
  );

  Future<String> placeCall(String destination);
  void accept(String callId);
  void reject(String callId);
  void hangup();
  void mute(bool muted);
  void sendDigits(String digits);
  void signOut();
  void dispose();
}
