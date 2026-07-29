import 'package:flutter_test/flutter_test.dart';
import 'package:powerline/core/logic/analytics.dart';
import 'package:powerline/data/local_store.dart';
import 'package:powerline/data/repositories/app_repository.dart';
import 'package:powerline/data/seed/demo_seed.dart';
import 'package:powerline/domain/models/enums.dart';
import 'package:powerline/domain/models/models.dart';

void main() {
  test('analytics compute from seed data', () {
    final s = buildDemoSeed();
    final a = computeAnalytics(
      calls: s.calls,
      messages: s.messages,
      voicemails: s.voicemails,
      appointments: s.appointments,
      handoffs: s.handoffs,
      dnc: s.dnc,
    );
    expect(a.callsAttempted, s.calls.length);
    expect(a.callsAttempted, greaterThanOrEqualTo(60));
    expect(a.aiCalls + a.humanCalls, a.callsAttempted);
    expect(a.deliveryRate, inInclusiveRange(0, 1));
    expect(a.dncCount, s.dnc.length);
  });

  test('seed meets required demo volumes and is fictional', () {
    final s = buildDemoSeed();
    expect(s.contacts.length, greaterThanOrEqualTo(75));
    expect(s.companies.length, greaterThanOrEqualTo(20));
    expect(s.conversations.length, greaterThanOrEqualTo(30));
    expect(s.calls.length, greaterThanOrEqualTo(60));
    expect(s.campaigns.length, 5);
    expect(s.agents.length, 6);
    for (final c in s.contacts) {
      for (final p in c.phones) {
        expect(
          RegExp(r'^\+1\d{3}555\d{4}$').hasMatch(p.e164),
          isTrue,
          reason: '${p.e164} must be fictional 555 range',
        );
      }
    }
  });

  test('backup and restore round-trip via memory store', () async {
    final store = MemorySnapshotStore();
    final repo = AppRepository(store);
    await repo.init();
    final origContacts = repo.state.contacts.length;
    final backupPath = await repo.backup();
    // mutate
    repo.upsertContact(
      Contact(
        id: 'newc',
        firstName: 'Temp',
        lastName: 'Rary',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      op: 'create',
    );
    expect(repo.state.contacts.length, origContacts + 1);
    await repo.restore(backupPath);
    expect(repo.state.contacts.length, origContacts);
  });

  test('DNC enforcement via repository', () async {
    final repo = AppRepository(MemorySnapshotStore());
    await repo.init();
    expect(repo.isDnc('+19995550000'), isFalse);
    repo.addDnc('+19995550000', reason: 'test');
    expect(repo.isDnc('+19995550000'), isTrue);
    // a seeded DNC contact is recognized
    final dncContact = repo.state.contacts.firstWhere((c) => c.dnc);
    expect(repo.isDnc(dncContact.phones.first.e164), isTrue);
  });

  test('message state transition guard in repo', () async {
    final repo = AppRepository(MemorySnapshotStore());
    await repo.init();
    final conv = repo.ensureConversation('+12145550777');
    final msg = Message(
      id: 'm1',
      conversationId: conv.id,
      direction: CallDirection.outbound,
      body: 'hi',
      state: MessageState.sending,
      createdAt: DateTime.now(),
    );
    repo.addMessage(msg);
    repo.updateMessageState('m1', MessageState.sent);
    expect(
      repo.state.messages.firstWhere((m) => m.id == 'm1').state,
      MessageState.sent,
    );
    // illegal jump ignored
    repo.updateMessageState('m1', MessageState.draft);
    expect(
      repo.state.messages.firstWhere((m) => m.id == 'm1').state,
      MessageState.sent,
    );
  });
}
