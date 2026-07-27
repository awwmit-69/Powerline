/// Campaign calling-queue builder with lawful-exclusion reasons.
library;

import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/models/models2.dart';

class QueueEntry {
  final Contact contact;
  final bool eligible;
  final String? exclusionReason;
  const QueueEntry(this.contact, this.eligible, [this.exclusionReason]);
}

/// Builds the preview calling queue for a campaign.
/// Every excluded lead carries an explicit reason so operators can see WHY.
List<QueueEntry> buildCampaignQueue({
  required Campaign campaign,
  required List<Contact> allContacts,
  required Set<String> dncE164s,
  required Set<String> suppressedE164s,
  required Set<String> activeCallE164s,
  required DateTime utcNow,
  int callsMadeToday = 0,
}) {
  final entries = <QueueEntry>[];
  if (campaign.status != CampaignStatus.active) {
    return campaign.leadContactIds
        .map((id) => allContacts.where((c) => c.id == id))
        .expand((c) => c)
        .map((c) => QueueEntry(c, false, 'campaign is ${campaign.status.name}'))
        .toList();
  }
  if (callsMadeToday >= campaign.dailyLimit) {
    return campaign.leadContactIds
        .map((id) => allContacts.where((c) => c.id == id))
        .expand((c) => c)
        .map(
          (c) => QueueEntry(
            c,
            false,
            'daily limit reached (${campaign.dailyLimit})',
          ),
        )
        .toList();
  }

  for (final id in campaign.leadContactIds) {
    final matches = allContacts.where((c) => c.id == id);
    if (matches.isEmpty) continue;
    final c = matches.first;
    final phone = c.primaryPhone;
    if (phone == null) {
      entries.add(QueueEntry(c, false, 'no phone number'));
      continue;
    }
    if (c.dnc || dncE164s.contains(phone)) {
      entries.add(QueueEntry(c, false, 'DNC'));
      continue;
    }
    if (suppressedE164s.contains(phone)) {
      entries.add(QueueEntry(c, false, 'suppressed'));
      continue;
    }
    if (activeCallE164s.contains(phone)) {
      entries.add(QueueEntry(c, false, 'already in an active call'));
      continue;
    }
    final localHour = _localHourFor(c.timeZone ?? campaign.timeZone, utcNow);
    if (localHour < campaign.callingHourStart ||
        localHour >= campaign.callingHourEnd) {
      entries.add(
        QueueEntry(
          c,
          false,
          'outside contact-local calling hours (local hour $localHour)',
        ),
      );
      continue;
    }
    entries.add(QueueEntry(c, true));
  }
  return entries;
}

/// Fixed-offset approximation for demo/test determinism. A production build
/// would use a real tz database; documented in COMPLIANCE.md.
int _localHourFor(String timeZone, DateTime utcNow) {
  const offsets = {
    'America/New_York': -5,
    'America/Chicago': -6,
    'America/Denver': -7,
    'America/Phoenix': -7,
    'America/Los_Angeles': -8,
  };
  final off = offsets[timeZone] ?? -6;
  return (utcNow.toUtc().hour + off + 24) % 24;
}
