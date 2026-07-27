import 'package:flutter_test/flutter_test.dart';
import 'package:powerline/core/logic/campaign_queue.dart';
import 'package:powerline/domain/models/enums.dart';
import 'package:powerline/domain/models/models.dart';
import 'package:powerline/domain/models/models2.dart';

Contact c(
  String id,
  String phone, {
  bool dnc = false,
  String tz = 'America/Chicago',
}) =>
    Contact(
      id: id,
      firstName: 'F$id',
      lastName: 'L$id',
      phones: [PhoneEntry(label: 'mobile', e164: phone)],
      timeZone: tz,
      dnc: dnc,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  final contacts = [
    c('1', '+12145550101'),
    c('2', '+12145550102', dnc: true),
    c('3', '+12145550103'),
    c('4', '+12145550104'),
  ];
  final campaign = Campaign(
    id: 'camp',
    name: 'Test',
    status: CampaignStatus.active,
    leadContactIds: const ['1', '2', '3', '4'],
    callingHourStart: 0,
    callingHourEnd: 24,
    createdAt: DateTime(2026),
  );

  test('DNC contact excluded with reason', () {
    final q = buildCampaignQueue(
      campaign: campaign,
      allContacts: contacts,
      dncE164s: {},
      suppressedE164s: {},
      activeCallE164s: {},
      utcNow: DateTime.utc(2026, 1, 1, 18),
    );
    final dncEntry = q.firstWhere((e) => e.contact.id == '2');
    expect(dncEntry.eligible, isFalse);
    expect(dncEntry.exclusionReason, 'DNC');
  });

  test('separate DNC list excludes contact', () {
    final q = buildCampaignQueue(
      campaign: campaign,
      allContacts: contacts,
      dncE164s: {'+12145550103'},
      suppressedE164s: {},
      activeCallE164s: {},
      utcNow: DateTime.utc(2026, 1, 1, 18),
    );
    expect(q.firstWhere((e) => e.contact.id == '3').eligible, isFalse);
  });

  test('suppressed and active-call excluded', () {
    final q = buildCampaignQueue(
      campaign: campaign,
      allContacts: contacts,
      dncE164s: {},
      suppressedE164s: {'+12145550101'},
      activeCallE164s: {'+12145550104'},
      utcNow: DateTime.utc(2026, 1, 1, 18),
    );
    expect(
      q.firstWhere((e) => e.contact.id == '1').exclusionReason,
      'suppressed',
    );
    expect(
      q.firstWhere((e) => e.contact.id == '4').exclusionReason,
      'already in an active call',
    );
  });

  test('paused campaign excludes everyone with reason', () {
    final paused = campaign.copyWith(status: CampaignStatus.paused);
    final q = buildCampaignQueue(
      campaign: paused,
      allContacts: contacts,
      dncE164s: {},
      suppressedE164s: {},
      activeCallE164s: {},
      utcNow: DateTime.utc(2026, 1, 1, 18),
    );
    expect(q.every((e) => !e.eligible), isTrue);
    expect(q.first.exclusionReason, contains('paused'));
  });

  test('calling-hours enforced by contact timezone', () {
    final narrow = Campaign(
      id: 'c2',
      name: 'Narrow',
      status: CampaignStatus.active,
      leadContactIds: const ['1'],
      callingHourStart: 9,
      callingHourEnd: 17,
      timeZone: 'America/Chicago',
      createdAt: DateTime(2026),
    );
    // 06:00 UTC -> 00:00 Central -> outside 9-17
    final q = buildCampaignQueue(
      campaign: narrow,
      allContacts: contacts,
      dncE164s: {},
      suppressedE164s: {},
      activeCallE164s: {},
      utcNow: DateTime.utc(2026, 1, 1, 6),
    );
    expect(q.first.eligible, isFalse);
    expect(q.first.exclusionReason, contains('calling hours'));
  });
}
