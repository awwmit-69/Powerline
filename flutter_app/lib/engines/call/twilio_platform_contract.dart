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

  /// True when this device already holds a signed-in agent session.
  bool hasSavedSession();

  Future<String> placeCall(String destination);

  /// Opens the consent-gated AI-call dialog; the server dials [destination]
  /// and hands the call to the AI agent. Returns the call SID.
  Future<String> aiCall(String destination, String tokenUrl);

  /// Opens the Appointments panel (bookings made by Maya).
  Future<void> openAppointments(String tokenUrl);
  void accept(String callId);
  void reject(String callId);
  void hangup();
  void mute(bool muted);
  void sendDigits(String digits);
  void signOut();
  void dispose();
}
