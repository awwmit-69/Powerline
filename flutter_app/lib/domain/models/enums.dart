/// Shared enums for the Powerline domain.
library;

enum CallDirection { inbound, outbound }

enum CallState {
  preparing,
  dialing,
  ringing,
  connected,
  onHold,
  transferring,
  completed,
  failed,
  busy,
  noAnswer,
  voicemail,
}

extension CallStateX on CallState {
  bool get isTerminal => const {
        CallState.completed,
        CallState.failed,
        CallState.busy,
        CallState.noAnswer,
        CallState.voicemail,
      }.contains(this);

  bool get isLive => const {
        CallState.connected,
        CallState.onHold,
        CallState.transferring,
      }.contains(this);
}

/// Legal call-state transitions for the demo engine. Guarded so UI bugs cannot
/// produce impossible histories.
const Map<CallState, Set<CallState>> callStateTransitions = {
  CallState.preparing: {CallState.dialing, CallState.failed},
  CallState.dialing: {CallState.ringing, CallState.failed, CallState.busy},
  CallState.ringing: {
    CallState.connected,
    CallState.noAnswer,
    CallState.voicemail,
    CallState.failed,
    CallState.busy,
    CallState.completed,
  },
  CallState.connected: {
    CallState.onHold,
    CallState.transferring,
    CallState.completed,
    CallState.failed,
  },
  CallState.onHold: {CallState.connected, CallState.completed},
  CallState.transferring: {
    CallState.connected,
    CallState.completed,
    CallState.failed,
  },
  CallState.completed: {},
  CallState.failed: {},
  CallState.busy: {},
  CallState.noAnswer: {},
  CallState.voicemail: {},
};

bool isLegalCallTransition(CallState from, CallState to) =>
    callStateTransitions[from]?.contains(to) ?? false;

enum MessageState {
  draft,
  queued,
  sending,
  sent,
  delivered,
  failed,
  received,
  read,
  suppressed,
}

const Map<MessageState, Set<MessageState>> messageStateTransitions = {
  MessageState.draft: {MessageState.queued, MessageState.suppressed},
  MessageState.queued: {
    MessageState.sending,
    MessageState.failed,
    MessageState.suppressed,
  },
  MessageState.sending: {MessageState.sent, MessageState.failed},
  MessageState.sent: {MessageState.delivered, MessageState.failed},
  MessageState.delivered: {},
  MessageState.failed: {MessageState.queued},
  MessageState.received: {MessageState.read},
  MessageState.read: {},
  MessageState.suppressed: {},
};

bool isLegalMessageTransition(MessageState from, MessageState to) =>
    messageStateTransitions[from]?.contains(to) ?? false;

enum PipelineStage {
  newLead,
  attempted,
  contacted,
  qualified,
  appointmentScheduled,
  followUp,
  proposalSent,
  won,
  lost,
  dnc,
  suppressed,
}

enum AgentKind { human, ai }

enum ProviderState { notConfigured, configured, disabled, activeDemo, error }

enum DeviceType { windowsDesktop, macDesktop, androidPhone, iphone, webSession }

enum CampaignStatus { draft, active, paused, completed, archived }

enum AppointmentStatus {
  scheduled,
  confirmed,
  completed,
  missed,
  cancelled,
  rescheduled,
}

enum HandoffKind {
  humanToAi,
  aiRequestsHuman,
  aiEscalation,
  supervisorTakeover,
  warmHandoff,
  coldTransfer,
}
