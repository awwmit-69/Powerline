import 'package:flutter_test/flutter_test.dart';
import 'package:powerline/engines/ai/agent_simulator.dart';
import 'package:powerline/engines/ai/ai_providers.dart';
import 'package:powerline/engines/call/demo_call_engine.dart';
import 'package:powerline/engines/call/mock_engines.dart';
import 'package:powerline/engines/messaging/messaging_provider.dart';
import 'package:powerline/domain/models/models2.dart';

void main() {
  test('mock engines report mock mode and refuse to place calls', () async {
    final engines = [
      MockSipCallEngine(),
      MockSignalMashCallEngine(),
      MockTwilioCallEngine(),
      MockVonageCallEngine(),
      MockAsteriskCallEngine(),
      MockVicidialCallEngine(),
      MockAiVoiceCallEngine(),
    ];
    for (final e in engines) {
      expect(e.status.mockMode, isTrue);
      expect(e.status.connected, isFalse);
      expect(e.status.missingConfiguration, isNotEmpty);
      await expectLater(
        () => e.placeCall('+12145550100'),
        throwsA(isA<UnsupportedError>()),
      );
      await e.dispose();
    }
  });

  test('demo engine is honest: mock mode, not "connected", simulates', () {
    final e = DemoCallEngine();
    expect(e.status.mockMode, isTrue);
    expect(e.status.connected, isFalse);
    expect(e.status.simulatedCapabilities, contains('place'));
    expect(e.status.unsupportedCapabilities, contains('real audio'));
  });

  test('demo messaging provider simulates delivery + reply', () async {
    final p = DemoMessagingProvider(tick: const Duration(milliseconds: 1));
    final events = <String>[];
    final sub = p.events.listen((e) => events.add(e.kind));
    await p.sendSms(
      const OutboundMessageRequest(
        to: '+12145550100',
        from: '+12145550999',
        body: 'appointment?',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, contains('delivery'));
    expect(events, contains('inbound'));
    await sub.cancel();
    await p.dispose();
  });

  test('mock messaging maps opt-out keyword', () {
    final p = mockTwilioMessaging();
    final ev = p.mapInboundWebhook({
      'MessageSid': 'X',
      'From': '+1',
      'Body': 'STOP',
    });
    expect(ev.kind, 'opt-out');
  });

  test(
    'AI simulator books, escalates, and honors opt-out — never a real call',
    () async {
      final sim = AgentSimulator(mockAnthropicLlm());
      const agent = AiAgent(id: 'a', name: 'Test', greeting: 'hi (simulated)');
      final booked = await sim.run(agent, SimPersona.interested);
      expect(booked.appointmentBooked, isTrue);
      final human = await sim.run(agent, SimPersona.wantsHuman);
      expect(human.escalatedToHuman, isTrue);
      final optout = await sim.run(agent, SimPersona.notInterested);
      expect(optout.dncRequested, isTrue);
      // transcript always starts with a simulation disclosure
      expect(booked.transcript.first.text.toLowerCase(), contains('simulated'));
    },
  );
}
