/// Analytics computed from local records. All values are clearly demo-derived.
library;

import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/models/models2.dart';

class AnalyticsSummary {
  final int callsAttempted;
  final int callsAnswered;
  final int missedCalls;
  final double avgCallDurationSeconds;
  final int inboundCalls;
  final int outboundCalls;
  final int messagesSent;
  final int messagesReceived;
  final double deliveryRate;
  final double responseRate;
  final int voicemails;
  final int appointmentsBooked;
  final int appointmentsConfirmed;
  final int aiCalls;
  final int humanCalls;
  final int handoffCount;
  final double aiResolutionRate;
  final int dncCount;

  const AnalyticsSummary({
    required this.callsAttempted,
    required this.callsAnswered,
    required this.missedCalls,
    required this.avgCallDurationSeconds,
    required this.inboundCalls,
    required this.outboundCalls,
    required this.messagesSent,
    required this.messagesReceived,
    required this.deliveryRate,
    required this.responseRate,
    required this.voicemails,
    required this.appointmentsBooked,
    required this.appointmentsConfirmed,
    required this.aiCalls,
    required this.humanCalls,
    required this.handoffCount,
    required this.aiResolutionRate,
    required this.dncCount,
  });
}

AnalyticsSummary computeAnalytics({
  required List<CallRecord> calls,
  required List<Message> messages,
  required List<Voicemail> voicemails,
  required List<Appointment> appointments,
  required List<HandoffEvent> handoffs,
  required List<DncRecord> dnc,
}) {
  final answered = calls.where((c) => c.answeredAt != null).toList();
  final connected = calls.where((c) => c.durationSeconds > 0).toList();
  final outboundMsgs = messages
      .where((m) => m.direction == CallDirection.outbound)
      .toList();
  final inboundMsgs = messages
      .where((m) => m.direction == CallDirection.inbound)
      .toList();
  final delivered = outboundMsgs
      .where(
        (m) =>
            m.state == MessageState.delivered || m.state == MessageState.read,
      )
      .length;
  final aiCalls = calls.where((c) => c.agentKind == AgentKind.ai).toList();
  final aiResolved = aiCalls
      .where(
        (c) =>
            c.disposition != null &&
            c.disposition != 'escalated' &&
            c.handoffEventIds.isEmpty,
      )
      .length;

  return AnalyticsSummary(
    callsAttempted: calls.length,
    callsAnswered: answered.length,
    missedCalls: calls.where((c) => c.missed).length,
    avgCallDurationSeconds: connected.isEmpty
        ? 0
        : connected.map((c) => c.durationSeconds).reduce((a, b) => a + b) /
              connected.length,
    inboundCalls: calls
        .where((c) => c.direction == CallDirection.inbound)
        .length,
    outboundCalls: calls
        .where((c) => c.direction == CallDirection.outbound)
        .length,
    messagesSent: outboundMsgs.length,
    messagesReceived: inboundMsgs.length,
    deliveryRate: outboundMsgs.isEmpty ? 0 : delivered / outboundMsgs.length,
    responseRate: outboundMsgs.isEmpty
        ? 0
        : inboundMsgs.length / outboundMsgs.length,
    voicemails: voicemails.length,
    appointmentsBooked: appointments.length,
    appointmentsConfirmed: appointments.where((a) => a.confirmed).length,
    aiCalls: aiCalls.length,
    humanCalls: calls.length - aiCalls.length,
    handoffCount: handoffs.length,
    aiResolutionRate: aiCalls.isEmpty ? 0 : aiResolved / aiCalls.length,
    dncCount: dnc.length,
  );
}
