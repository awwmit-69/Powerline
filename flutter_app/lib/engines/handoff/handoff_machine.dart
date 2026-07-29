/// Human <-> AI handoff state machine.
///
/// States and transitions cover: human transfers to AI, AI requests human,
/// AI failure escalation, listen-before-accept, warm handoff, cold transfer,
/// supervisor takeover, whisper summary.
library;

enum HandoffState {
  humanActive,
  aiActive,
  aiRequestingHuman,
  humanListening, // human hears the call before accepting (warm)
  whispering, // AI delivers whisper summary to human
  transferringToAi,
  transferringToHuman,
  supervisorActive,
  ended,
}

enum HandoffTrigger {
  humanHandsToAi,
  aiRequestsHuman,
  aiFails,
  humanStartsListening,
  humanAccepts, // warm accept
  coldTransferToHuman,
  whisperComplete,
  supervisorTakeover,
  aiTransferComplete,
  callEnds,
}

class HandoffTransition {
  final HandoffState from;
  final HandoffTrigger trigger;
  final HandoffState to;
  final DateTime at;
  final String reason;
  const HandoffTransition(
    this.from,
    this.trigger,
    this.to,
    this.at,
    this.reason,
  );
}

class HandoffMachine {
  HandoffState _state;
  final List<HandoffTransition> history = [];
  String whisperSummary = '';

  HandoffMachine({HandoffState initial = HandoffState.humanActive})
      : _state = initial;

  HandoffState get state => _state;

  static final Map<HandoffState, Map<HandoffTrigger, HandoffState>> _table = {
    HandoffState.humanActive: {
      HandoffTrigger.humanHandsToAi: HandoffState.transferringToAi,
      HandoffTrigger.supervisorTakeover: HandoffState.supervisorActive,
      HandoffTrigger.callEnds: HandoffState.ended,
    },
    HandoffState.transferringToAi: {
      HandoffTrigger.aiTransferComplete: HandoffState.aiActive,
      HandoffTrigger.aiFails: HandoffState.humanActive, // fall back
      HandoffTrigger.callEnds: HandoffState.ended,
    },
    HandoffState.aiActive: {
      HandoffTrigger.aiRequestsHuman: HandoffState.aiRequestingHuman,
      HandoffTrigger.aiFails: HandoffState.aiRequestingHuman,
      HandoffTrigger.supervisorTakeover: HandoffState.supervisorActive,
      HandoffTrigger.callEnds: HandoffState.ended,
    },
    HandoffState.aiRequestingHuman: {
      HandoffTrigger.humanStartsListening: HandoffState.humanListening,
      HandoffTrigger.coldTransferToHuman: HandoffState.transferringToHuman,
      HandoffTrigger.callEnds: HandoffState.ended,
    },
    HandoffState.humanListening: {
      HandoffTrigger.humanAccepts: HandoffState.whispering,
      HandoffTrigger.callEnds: HandoffState.ended,
    },
    HandoffState.whispering: {
      HandoffTrigger.whisperComplete: HandoffState.humanActive,
      HandoffTrigger.callEnds: HandoffState.ended,
    },
    HandoffState.transferringToHuman: {
      HandoffTrigger.humanAccepts: HandoffState.humanActive,
      HandoffTrigger.callEnds: HandoffState.ended,
    },
    HandoffState.supervisorActive: {
      HandoffTrigger.callEnds: HandoffState.ended,
    },
    HandoffState.ended: {},
  };

  bool canFire(HandoffTrigger t) => _table[_state]?.containsKey(t) ?? false;

  /// Fires a trigger. Returns true when the transition was legal.
  bool fire(HandoffTrigger t, {String reason = ''}) {
    final next = _table[_state]?[t];
    if (next == null) return false;
    history.add(HandoffTransition(_state, t, next, DateTime.now(), reason));
    if (next == HandoffState.whispering) {
      whisperSummary =
          'AI whisper: caller context summary handed to human. Reason: $reason';
    }
    _state = next;
    return true;
  }
}
