/// Campaigns workspace: campaign list, calling queue with exclusion reasons,
/// CRM pipeline board, appointments & callbacks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logic/campaign_queue.dart';
import '../../core/theme/theme.dart';
import '../../core/util/phone.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models2.dart';
import '../../data/repositories/app_repository.dart';
import '../../providers.dart';
import 'package:collection/collection.dart';

class CampaignsScreen extends ConsumerStatefulWidget {
  const CampaignsScreen({super.key});

  @override
  ConsumerState<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends ConsumerState<CampaignsScreen> {
  String? selectedCampaignId;
  int _tab = 0;

  static const _tabLabels = [
    'Campaigns',
    'Calling queue',
    'Pipeline',
    'Appointments',
  ];

  @override
  Widget build(BuildContext context) {
    final s = stateOf(ref);
    selectedCampaignId ??= s.campaigns.firstOrNull?.id;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              for (var i = 0; i < _tabLabels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_tabLabels[i]),
                    selected: _tab == i,
                    onSelected: (_) => setState(() => _tab = i),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (_tab) {
            0 => _campaignList(s),
            1 => _queue(s),
            2 => _pipeline(s),
            _ => _appointments(s),
          },
        ),
      ],
    );
  }

  Widget _campaignList(AppState s) {
    final repo = ref.read(appRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Row(
          children: [
            Text(
              'Campaigns',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SizedBox(width: 8),
            DemoBadge(label: 'EXECUTION DISABLED — preview/manual only'),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Automated campaign dialing is disabled by design in demo mode. Queues are preview-only; each call requires explicit operator action.',
          style: TextStyle(fontSize: 11, color: PowerlineColors.textSecondary),
        ),
        const SizedBox(height: 10),
        for (final cp in s.campaigns)
          Card(
            child: ListTile(
              selected: cp.id == selectedCampaignId,
              title: Row(
                children: [
                  Text(cp.name),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      cp.status.name,
                      style: const TextStyle(fontSize: 10),
                    ),
                    backgroundColor: cp.status == CampaignStatus.active
                        ? PowerlineColors.stateConnected.withValues(alpha: 0.2)
                        : null,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              subtitle: Text(
                '${cp.description}\n${cp.leadContactIds.length} leads · daily limit ${cp.dailyLimit} · hours ${cp.callingHourStart}:00–${cp.callingHourEnd}:00 (${cp.timeZone})',
                style: const TextStyle(fontSize: 11),
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  final next = switch (v) {
                    'activate' => CampaignStatus.active,
                    'pause' => CampaignStatus.paused,
                    _ => CampaignStatus.archived,
                  };
                  repo.updateCampaign(cp.copyWith(status: next));
                },
                itemBuilder: (c) => const [
                  PopupMenuItem(value: 'activate', child: Text('Activate')),
                  PopupMenuItem(value: 'pause', child: Text('Pause')),
                  PopupMenuItem(value: 'archive', child: Text('Archive')),
                ],
              ),
              onTap: () => setState(() {
                selectedCampaignId = cp.id;
                setState(() => _tab = 1);
              }),
            ),
          ),
      ],
    );
  }

  Widget _queue(AppState s) {
    final cp = s.campaigns.where((c) => c.id == selectedCampaignId).firstOrNull;
    if (cp == null) return const Center(child: Text('Select a campaign'));
    final activeCallE164 = ref.watch(callSessionProvider)?.snapshot.remoteE164;
    final entries = buildCampaignQueue(
      campaign: cp,
      allContacts: s.contacts,
      dncE164s: {for (final d in s.dnc) d.e164},
      suppressedE164s: {...s.smsSuppression},
      activeCallE164s: {if (activeCallE164 != null) activeCallE164},
      utcNow: DateTime.now().toUtc(),
    );
    final eligible = entries.where((e) => e.eligible).toList();
    final excluded = entries.where((e) => !e.eligible).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Queue for "${cp.name}" — ${eligible.length} callable, ${excluded.length} excluded',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'DNC, suppression, campaign status, calling hours and contact time zones are enforced. Manual preview dialing only.',
          style: TextStyle(fontSize: 11, color: PowerlineColors.textSecondary),
        ),
        const SizedBox(height: 10),
        for (final e in eligible)
          Card(
            child: ListTile(
              dense: true,
              leading: const Icon(
                Icons.check_circle_outline,
                color: PowerlineColors.stateConnected,
                size: 18,
              ),
              title: Text(e.contact.displayName),
              subtitle: Text(
                '${PhoneNumberUtil.format(e.contact.primaryPhone ?? '')} · ${e.contact.timeZone ?? cp.timeZone}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: FilledButton.tonalIcon(
                onPressed: () => ref
                    .read(callSessionProvider.notifier)
                    .placeDemoCall(e.contact.primaryPhone!, campaignId: cp.id),
                icon: const Icon(Icons.call, size: 14),
                label: const Text('Preview call'),
              ),
            ),
          ),
        if (excluded.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'Excluded (with reasons)',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final e in excluded)
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.block,
                color: PowerlineColors.stateFailed,
                size: 16,
              ),
              title: Text(e.contact.displayName),
              subtitle: Text(
                e.exclusionReason ?? '',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
        const Divider(height: 24),
        const Text(
          'Other queues',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        _MiniQueue(
          title: 'Callback queue',
          items: [
            for (final cb in s.callbacks.where((c) => !c.done))
              '${_name(s, cb.contactId)} — due ${cb.dueAt.month}/${cb.dueAt.day} ${cb.dueAt.hour}:00 (${cb.reason})',
          ],
        ),
        _MiniQueue(
          title: 'Missed-call return queue',
          items: [
            for (final c in s.calls.where((c) => c.missed).take(5))
              '${_name(s, c.contactId)} — missed ${c.startedAt.month}/${c.startedAt.day}',
          ],
        ),
        _MiniQueue(
          title: 'Voicemail callback queue',
          items: [
            for (final v in s.voicemails.where((v) => !v.read))
              '${PhoneNumberUtil.format(v.remoteE164)} — new voicemail',
          ],
        ),
        _MiniQueue(
          title: 'Appointment-confirmation queue',
          items: [
            for (final a in s.appointments.where((a) => !a.confirmed))
              '${_name(s, a.contactId)} — ${a.startsAt.month}/${a.startsAt.day} ${a.kind}',
          ],
        ),
      ],
    );
  }

  Widget _pipeline(AppState s) {
    final repo = ref.read(appRepositoryProvider);
    const stages = PipelineStage.values;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final st in stages)
            Container(
              width: 210,
              margin: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${st.name} (${s.deals.where((d) => d.stage == st).length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final d in s.deals.where((d) => d.stage == st))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _name(s, d.contactId),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '\$${d.value.toStringAsFixed(0)} · ${d.nextAction}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Move left',
                                  icon: const Icon(
                                    Icons.chevron_left,
                                    size: 16,
                                  ),
                                  onPressed: st.index == 0
                                      ? null
                                      : () => repo.upsertDeal(
                                            d.copyWith(
                                              stage: stages[st.index - 1],
                                            ),
                                          ),
                                ),
                                IconButton(
                                  tooltip: 'Move right',
                                  icon: const Icon(
                                    Icons.chevron_right,
                                    size: 16,
                                  ),
                                  onPressed: st.index == stages.length - 1
                                      ? null
                                      : () => repo.upsertDeal(
                                            d.copyWith(
                                              stage: stages[st.index + 1],
                                            ),
                                          ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _appointments(AppState s) {
    final repo = ref.read(appRepositoryProvider);
    final appts = [...s.appointments]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final cbs = [...s.callbacks]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Appointments (agenda)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        for (final a in appts)
          Card(
            child: ListTile(
              dense: true,
              leading: Icon(
                Icons.event,
                color: a.confirmed
                    ? PowerlineColors.stateConnected
                    : PowerlineColors.stateRinging,
                size: 18,
              ),
              title: Text('${_name(s, a.contactId)} — ${a.kind}'),
              subtitle: Text(
                '${a.startsAt} (${a.timeZone}) · ${a.status.name}${a.confirmed ? ' · confirmed' : ''}\n${a.address ?? a.meetingLink ?? ''}',
                style: const TextStyle(fontSize: 11),
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'confirm':
                      repo.upsertAppointment(a.copyWith(confirmed: true));
                    case 'complete':
                      repo.upsertAppointment(
                        a.copyWith(status: AppointmentStatus.completed),
                      );
                    case 'missed':
                      repo.upsertAppointment(
                        a.copyWith(status: AppointmentStatus.missed),
                      );
                      repo.upsertCallback(
                        CallbackTask(
                          id: 'cb_${a.id}',
                          contactId: a.contactId,
                          campaignId: a.campaignId,
                          dueAt: DateTime.now().add(const Duration(hours: 2)),
                          reason: 'Missed appointment follow-up',
                        ),
                      );
                    case 'reschedule':
                      repo.upsertAppointment(
                        a.copyWith(
                          startsAt: a.startsAt.add(const Duration(days: 1)),
                          status: AppointmentStatus.rescheduled,
                        ),
                      );
                    case 'cancel':
                      repo.upsertAppointment(
                        a.copyWith(status: AppointmentStatus.cancelled),
                      );
                    case 'remind':
                      repo.notify(
                        'appointment',
                        'Reminder queued (demo)',
                        'Day-before reminder for ${_name(s, a.contactId)}',
                      );
                      repo.upsertAppointment(a.copyWith(reminderSent: true));
                  }
                },
                itemBuilder: (c) => const [
                  PopupMenuItem(
                    value: 'confirm',
                    child: Text('Mark confirmed'),
                  ),
                  PopupMenuItem(
                    value: 'remind',
                    child: Text('Send reminder (demo)'),
                  ),
                  PopupMenuItem(
                    value: 'complete',
                    child: Text('Mark completed'),
                  ),
                  PopupMenuItem(
                    value: 'missed',
                    child: Text('Mark missed → callback'),
                  ),
                  PopupMenuItem(
                    value: 'reschedule',
                    child: Text('Reschedule +1 day'),
                  ),
                  PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Text('Callbacks', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final cb in cbs)
          Card(
            child: ListTile(
              dense: true,
              leading: Icon(
                cb.done ? Icons.check_circle : Icons.update,
                size: 18,
              ),
              title: Text(_name(s, cb.contactId)),
              subtitle: Text(
                'due ${cb.dueAt} · ${cb.reason}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: cb.done
                  ? null
                  : FilledButton.tonal(
                      onPressed: () =>
                          repo.upsertCallback(cb.copyWith(done: true)),
                      child: const Text('Done'),
                    ),
            ),
          ),
      ],
    );
  }

  String _name(AppState s, String? contactId) {
    final m = s.contacts.where((c) => c.id == contactId);
    return m.isEmpty ? 'Unknown' : m.first.displayName;
  }
}

class _MiniQueue extends StatelessWidget {
  final String title;
  final List<String> items;
  const _MiniQueue({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        title: Text(
          '$title (${items.length})',
          style: const TextStyle(fontSize: 13),
        ),
        children: [
          if (items.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text('Empty')),
          for (final i in items)
            ListTile(
              dense: true,
              title: Text(i, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
