import 'package:flutter_test/flutter_test.dart';
import 'package:powerline/domain/models/enums.dart';
import 'package:powerline/engines/handoff/handoff_machine.dart';

void main() {
  group('call-state transitions', () {
    test('legal path preparing->dialing->ringing->connected->completed', () {
      expect(isLegalCallTransition(CallState.preparing, CallState.dialing), isTrue);
      expect(isLegalCallTransition(CallState.dialing, CallState.ringing), isTrue);
      expect(isLegalCallTransition(CallState.ringing, CallState.connected), isTrue);
      expect(isLegalCallTransition(CallState.connected, CallState.completed), isTrue);
    });
    test('illegal jumps rejected', () {
      expect(isLegalCallTransition(CallState.preparing, CallState.connected), isFalse);
      expect(isLegalCallTransition(CallState.completed, CallState.connected), isFalse);
    });
    test('terminal states are terminal', () {
      expect(CallState.completed.isTerminal, isTrue);
      expect(CallState.connected.isTerminal, isFalse);
    });
  });

  group('message-state transitions', () {
    test('draft->queued->sending->sent->delivered legal', () {
      expect(isLegalMessageTransition(MessageState.draft, MessageState.queued), isTrue);
      expect(isLegalMessageTransition(MessageState.queued, MessageState.sending), isTrue);
      expect(isLegalMessageTransition(MessageState.sending, MessageState.sent), isTrue);
      expect(isLegalMessageTransition(MessageState.sent, MessageState.delivered), isTrue);
    });
    test('failed can retry to queued', () {
      expect(isLegalMessageTransition(MessageState.failed, MessageState.queued), isTrue);
    });
    test('delivered is terminal', () {
      expect(isLegalMessageTransition(MessageState.delivered, MessageState.sent), isFalse);
    });
  });

  group('handoff state machine', () {
    test('human -> AI transfer completes', () {
      final m = HandoffMachine();
      expect(m.fire(HandoffTrigger.humanHandsToAi), isTrue);
      expect(m.state, HandoffState.transferringToAi);
      expect(m.fire(HandoffTrigger.aiTransferComplete), isTrue);
      expect(m.state, HandoffState.aiActive);
    });

    test('AI escalates, human listens (warm), whisper, then human active', () {
      final m = HandoffMachine(initial: HandoffState.aiActive);
      expect(m.fire(HandoffTrigger.aiRequestsHuman), isTrue);
      expect(m.state, HandoffState.aiRequestingHuman);
      expect(m.fire(HandoffTrigger.humanStartsListening), isTrue);
      expect(m.state, HandoffState.humanListening);
      expect(m.fire(HandoffTrigger.humanAccepts), isTrue);
      expect(m.state, HandoffState.whispering);
      expect(m.whisperSummary, isNotEmpty);
      expect(m.fire(HandoffTrigger.whisperComplete), isTrue);
      expect(m.state, HandoffState.humanActive);
    });

    test('cold transfer to human', () {
      final m = HandoffMachine(initial: HandoffState.aiActive);
      m.fire(HandoffTrigger.aiFails, reason: 'model error');
      expect(m.state, HandoffState.aiRequestingHuman);
      expect(m.fire(HandoffTrigger.coldTransferToHuman), isTrue);
      expect(m.state, HandoffState.transferringToHuman);
      m.fire(HandoffTrigger.humanAccepts);
      expect(m.state, HandoffState.humanActive);
    });

    test('illegal trigger rejected and history recorded', () {
      final m = HandoffMachine();
      expect(m.fire(HandoffTrigger.whisperComplete), isFalse);
      expect(m.history, isEmpty);
      m.fire(HandoffTrigger.supervisorTakeover);
      expect(m.state, HandoffState.supervisorActive);
      expect(m.history.length, 1);
    });
  });
}
