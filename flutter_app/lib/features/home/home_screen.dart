/// Home — PowerLine command center (redesigned).
///
/// A premium 3-column communications dashboard: top bar, primary metrics,
/// then Left (conversations / return queues), Center (dialpad / active call /
/// timeline), Right (provider health / appointments / campaigns / AI / warnings).
library;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../core/util/phone.dart';
import '../../data/repositories/app_repository.dart';
import '../../domain/models/enums.dart';
import '../../providers.dart';
import '../search/search_palette.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final repo = ref.read(appRepositoryProvider);
    final wide = MediaQuery.of(context).size.width >= 1180;

    final today = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;
    final callsToday = s.calls.where((c) => isToday(c.startedAt)).length;
    final missed = s.calls.where((c) => c.missed).length;
    final unread = s.conversations.fold<int>(0, (a, c) => a + c.unreadCount);
    final newVms = s.voicemails.where((v) => !v.read).length;
    final appts = s.appointments
        .where((a) => a.startsAt.isAfter(today) && a.status == AppointmentStatus.scheduled)
        .length;
    final activeAgents = s.agents.length;
    final number = s.numbers.firstOrNull;

    final left = _Column(children: [
      _RecentConversations(),
      _MissedReturnQueue(),
      _VoicemailCallbacks(),
    ]);
    final center = _Column(children: [
      const _QuickDialpad(),
      _ActiveCallPanel(),
      _Timeline(),
    ]);
    final right = _Column(children: [
      _ProviderHealth(),
      _UpcomingAppointments(),
      _CampaignPerformance(),
      _AiActivity(),
      _Warnings(),
    ]);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ---- TOP BAR ----
        _Panel(
          child: Wrap(
            spacing: 18,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Your PowerLine number',
                      style: TextStyle(fontSize: 11, color: PowerlineColors.textSecondary)),
                  Text(
                    number == null
                        ? 'No number yet'
                        : '${PhoneNumberUtil.format(number.e164)} · ${number.label}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const _StatusChip(
                  icon: Icons.cloud_off, label: 'Provider: Demo (simulation)', color: PowerlineColors.stateRinging),
              _AvailabilityChip(repo: repo, value: s.settings['availability'] ?? 'Available'),
              const Spacer(),
              _TopButton(
                  icon: Icons.search,
                  label: 'Search',
                  onTap: () => showSearchPalette(context, ref)),
              _TopButton(
                  icon: Icons.add_comment_outlined,
                  label: 'New message',
                  onTap: () => context.go('/messages')),
              _TopButton(
                  icon: Icons.dialpad, label: 'Dialpad', primary: true, onTap: () => context.go('/dialpad')),
              PopupMenuButton<String>(
                tooltip: 'User menu',
                icon: const CircleAvatar(
                    radius: 15,
                    backgroundColor: PowerlineColors.raised,
                    child: Icon(Icons.person, size: 16)),
                onSelected: (v) {
                  if (v == 'settings') context.go('/settings');
                },
                itemBuilder: (c) => const [
                  PopupMenuItem(value: 'profile', child: Text('AZD Global (demo user)')),
                  PopupMenuItem(value: 'settings', child: Text('Settings')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // ---- PRIMARY METRICS ----
        Wrap(spacing: 12, runSpacing: 12, children: [
          _Metric('Calls today', '$callsToday', Icons.call, PowerlineColors.stateConnected, '/calls'),
          _Metric('Missed calls', '$missed', Icons.phone_missed, PowerlineColors.stateFailed, '/calls'),
          _Metric('Unread messages', '$unread', Icons.chat_bubble_outline, PowerlineColors.cobalt, '/messages'),
          _Metric('New voicemails', '$newVms', Icons.voicemail, PowerlineColors.stateVoicemail, '/voicemail'),
          _Metric('Appointments booked', '$appts', Icons.event_available, PowerlineColors.stateHold, '/campaigns'),
          _Metric('Active AI agents', '$activeAgents', Icons.smart_toy_outlined, PowerlineColors.stateRinging, '/agents'),
        ]),
        const SizedBox(height: 14),
        // ---- 3 COLUMNS ----
        if (wide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: left),
                const SizedBox(width: 14),
                Expanded(flex: 4, child: center),
                const SizedBox(width: 14),
                Expanded(flex: 3, child: right),
              ],
            ),
          )
        else ...[
          center,
          left,
          right,
        ],
      ],
    );
  }
}

// ---------- shared building blocks ----------

class _Column extends StatelessWidget {
  final List<Widget> children;
  const _Column({required this.children});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in children)
            Padding(padding: const EdgeInsets.only(bottom: 14), child: c),
        ],
      );
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: PowerlineColors.panel,
          border: Border.all(color: PowerlineColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

class _CardTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;
  const _CardTitle(this.title, this.icon, {this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 16, color: PowerlineColors.cobalt),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
      );
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatusChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: PowerlineColors.raised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PowerlineColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      );
}

class _AvailabilityChip extends StatelessWidget {
  final AppRepository repo;
  final String value;
  const _AvailabilityChip({required this.repo, required this.value});
  @override
  Widget build(BuildContext context) {
    final color = value == 'Available'
        ? PowerlineColors.stateConnected
        : value == 'Away'
            ? PowerlineColors.stateRinging
            : PowerlineColors.stateFailed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: PowerlineColors.raised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PowerlineColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: PowerlineColors.raised,
          items: const ['Available', 'Away', 'Do not disturb']
              .map((v) => DropdownMenuItem(
                    value: v,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.circle, size: 9),
                      const SizedBox(width: 6),
                      Text(v, style: const TextStyle(fontSize: 12)),
                    ]),
                  ))
              .toList(),
          selectedItemBuilder: (c) => const ['Available', 'Away', 'Do not disturb']
              .map((v) => Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(width: 4),
                    Icon(Icons.circle, size: 9, color: color),
                    const SizedBox(width: 6),
                    Text(v, style: const TextStyle(fontSize: 12)),
                  ]))
              .toList(),
          onChanged: (v) => repo.setSetting('availability', v ?? 'Available'),
        ),
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _TopButton({required this.icon, required this.label, this.primary = false, required this.onTap});
  @override
  Widget build(BuildContext context) => primary
      ? FilledButton.icon(
          onPressed: onTap, icon: Icon(icon, size: 15), label: Text(label))
      : OutlinedButton.icon(
          onPressed: onTap, icon: Icon(icon, size: 15), label: Text(label));
}

class _Metric extends ConsumerWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String route;
  const _Metric(this.label, this.value, this.icon, this.color, this.route);
  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
        width: 186,
        child: InkWell(
          onTap: () => context.go(route),
          borderRadius: BorderRadius.circular(12),
          child: _Panel(
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: PowerlineColors.textSecondary)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

// ---------- LEFT COLUMN ----------

class _RecentConversations extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final convs = [...s.conversations]
      ..sort((a, b) => (b.lastMessageAt ?? DateTime(0)).compareTo(a.lastMessageAt ?? DateTime(0)));
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle('Recent conversations', Icons.chat_outlined,
            trailing: _More(onTap: () => context.go('/messages'))),
        if (convs.isEmpty) const _Empty('No conversations yet'),
        for (final c in convs.take(5))
          _Row(
            title: _contactName(s, c.contactId) ?? PhoneNumberUtil.format(c.remoteE164),
            subtitle: _lastBody(s, c.id),
            badge: c.unreadCount > 0 ? '${c.unreadCount}' : null,
            onTap: () => context.go('/messages'),
          ),
      ]),
    );
  }
}

class _MissedReturnQueue extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final missed = s.calls.where((c) => c.missed).take(5).toList();
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle('Missed-call return queue', Icons.phone_missed),
        if (missed.isEmpty) const _Empty('No missed calls'),
        for (final c in missed)
          _Row(
            title: _contactName(s, c.contactId) ?? PhoneNumberUtil.format(c.remoteE164),
            subtitle: '${c.startedAt.month}/${c.startedAt.day} · ${c.direction.name}',
            trailingIcon: Icons.call,
            onTap: () => ref.read(callSessionProvider.notifier).placeDemoCall(c.remoteE164),
          ),
      ]),
    );
  }
}

class _VoicemailCallbacks extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final vms = s.voicemails.where((v) => !v.read).take(5).toList();
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle('Voicemail callbacks', Icons.voicemail,
            trailing: _More(onTap: () => context.go('/voicemail'))),
        if (vms.isEmpty) const _Empty('No new voicemails'),
        for (final v in vms)
          _Row(
            title: _contactByPhone(s, v.remoteE164) ?? PhoneNumberUtil.format(v.remoteE164),
            subtitle: v.transcript.isEmpty ? '${v.durationSeconds}s voicemail' : v.transcript,
            trailingIcon: Icons.call,
            onTap: () => ref.read(callSessionProvider.notifier).placeDemoCall(v.remoteE164),
          ),
      ]),
    );
  }
}

// ---------- CENTER COLUMN ----------

class _QuickDialpad extends ConsumerStatefulWidget {
  const _QuickDialpad();
  @override
  ConsumerState<_QuickDialpad> createState() => _QuickDialpadState();
}

class _QuickDialpadState extends ConsumerState<_QuickDialpad> {
  String digits = '';
  @override
  Widget build(BuildContext context) {
    final normalized = PhoneNumberUtil.normalize(digits);
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle('Quick dialpad', Icons.dialpad,
            trailing: const DemoBadge(label: 'DEMO')),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
              color: PowerlineColors.raised, borderRadius: BorderRadius.circular(8)),
          child: Text(digits.isEmpty ? 'Enter number' : PhoneNumberUtil.formatPartial(digits),
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: digits.isEmpty ? PowerlineColors.textSecondary : PowerlineColors.textPrimary)),
        ),
        const SizedBox(height: 8),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['*', '0', '#'],
        ])
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final k in row)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      onPressed: () => setState(() => digits += k),
                      child: Text(k, style: const TextStyle(fontSize: 17)),
                    ),
                  ),
                ),
              ),
          ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: PowerlineColors.stateConnected),
              onPressed: normalized == null
                  ? null
                  : () => ref.read(callSessionProvider.notifier).placeDemoCall(normalized),
              icon: const Icon(Icons.call, size: 16),
              label: const Text('Demo call'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => setState(() => digits = digits.isEmpty ? '' : digits.substring(0, digits.length - 1)),
            icon: const Icon(Icons.backspace_outlined, size: 18),
          ),
        ]),
      ]),
    );
  }
}

class _ActiveCallPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(callSessionProvider);
    final s = stateOf(ref);
    final lastCall = s.calls.firstOrNull;
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle('Active / recent call', Icons.phone_in_talk_outlined),
        if (session != null)
          Row(children: [
            const Icon(Icons.circle, size: 10, color: PowerlineColors.stateConnected),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${session.contact?.displayName ?? PhoneNumberUtil.format(session.snapshot.remoteE164)} · ${session.snapshot.state.name}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ])
        else if (lastCall != null)
          _Row(
            title: _contactName(s, lastCall.contactId) ?? PhoneNumberUtil.format(lastCall.remoteE164),
            subtitle:
                'Last call · ${lastCall.disposition ?? lastCall.finalState.name} · ${lastCall.durationSeconds}s',
            trailingIcon: Icons.call,
            onTap: () => ref.read(callSessionProvider.notifier).placeDemoCall(lastCall.remoteE164),
          )
        else
          const _Empty('No recent calls'),
      ]),
    );
  }
}

class _Timeline extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final today = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;
    final events = <(DateTime, IconData, String, Color)>[];
    for (final c in s.calls.where((c) => isToday(c.startedAt))) {
      events.add((
        c.startedAt,
        c.missed ? Icons.phone_missed : Icons.call,
        '${c.direction.name} call · ${c.disposition ?? c.finalState.name}',
        c.missed ? PowerlineColors.stateFailed : PowerlineColors.stateConnected,
      ));
    }
    for (final m in s.messages.where((m) => isToday(m.createdAt)).take(10)) {
      events.add((m.createdAt, Icons.chat_bubble_outline, '${m.direction.name} message',
          PowerlineColors.cobalt));
    }
    events.sort((a, b) => b.$1.compareTo(a.$1));
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle("Today's communication timeline", Icons.timeline),
        if (events.isEmpty) const _Empty('Nothing today yet'),
        for (final e in events.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(
                width: 44,
                child: Text(
                    '${e.$1.hour.toString().padLeft(2, '0')}:${e.$1.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 11, color: PowerlineColors.textSecondary)),
              ),
              Icon(e.$2, size: 14, color: e.$4),
              const SizedBox(width: 8),
              Expanded(child: Text(e.$3, style: const TextStyle(fontSize: 12))),
            ]),
          ),
      ]),
    );
  }
}

// ---------- RIGHT COLUMN ----------

class _ProviderHealth extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final byState = <ProviderState, int>{};
    for (final i in s.integrations) {
      byState[i.state] = (byState[i.state] ?? 0) + 1;
    }
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle('Provider health', Icons.health_and_safety_outlined,
            trailing: _More(onTap: () => context.go('/settings'))),
        _kv('Active (demo)', '${byState[ProviderState.activeDemo] ?? 0}', PowerlineColors.stateConnected),
        _kv('Configured', '${byState[ProviderState.configured] ?? 0}', PowerlineColors.stateHold),
        _kv('Not configured', '${byState[ProviderState.notConfigured] ?? 0}', PowerlineColors.stateRinging),
        _kv('Errors', '${byState[ProviderState.error] ?? 0}', PowerlineColors.stateFailed),
        const SizedBox(height: 6),
        const Text('No live telecom connected — all traffic simulated.',
            style: TextStyle(fontSize: 11, color: PowerlineColors.textSecondary)),
      ]),
    );
  }
}

class _UpcomingAppointments extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final appts = [...s.appointments]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle('Upcoming appointments', Icons.event_available,
            trailing: _More(onTap: () => context.go('/campaigns'))),
        if (appts.isEmpty) const _Empty('None scheduled'),
        for (final a in appts.take(4))
          _Row(
            title: '${_contactName(s, a.contactId) ?? 'Contact'} · ${a.kind}',
            subtitle: '${a.startsAt.month}/${a.startsAt.day} ${a.startsAt.hour}:00'
                '${a.confirmed ? ' · confirmed' : ''}',
          ),
      ]),
    );
  }
}

class _CampaignPerformance extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle('Campaign performance', Icons.campaign_outlined,
            trailing: _More(onTap: () => context.go('/campaigns'))),
        for (final cp in s.campaigns.take(4))
          Builder(builder: (context) {
            final cpCalls = s.calls.where((c) => c.campaignId == cp.id).length;
            final set = s.calls.where((c) => c.campaignId == cp.id && c.disposition == 'appointment-set').length;
            return _Row(title: cp.name, subtitle: '$cpCalls calls · $set appts · ${cp.status.name}');
          }),
        if (s.campaigns.isEmpty) const _Empty('No campaigns'),
      ]),
    );
  }
}

class _AiActivity extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final aiCalls = s.calls.where((c) => c.agentKind == AgentKind.ai).length;
    final handoffs = s.handoffs.length;
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle('AI-agent activity', Icons.smart_toy_outlined,
            trailing: _More(onTap: () => context.go('/agents'))),
        _kv('Agents (test mode)', '${s.agents.length}', PowerlineColors.stateHold),
        _kv('AI calls handled', '$aiCalls', PowerlineColors.cobalt),
        _kv('Human handoffs', '$handoffs', PowerlineColors.stateRinging),
      ]),
    );
  }
}

class _Warnings extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final warns = s.notifications.where((n) => !n.read).take(4).toList();
    final integErrors = s.integrations.where((i) => i.state == ProviderState.error).toList();
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle('Important warnings', Icons.warning_amber),
        if (warns.isEmpty && integErrors.isEmpty) const _Empty('All clear'),
        for (final w in warns)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 14, color: PowerlineColors.stateRinging),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(w.body, style: const TextStyle(fontSize: 11, color: PowerlineColors.textSecondary)),
                ]),
              ),
            ]),
          ),
        for (final e in integErrors)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.error_outline, size: 14, color: PowerlineColors.stateFailed),
              const SizedBox(width: 8),
              Expanded(child: Text('${e.provider}: ${e.lastError ?? 'error'}', style: const TextStyle(fontSize: 12))),
            ]),
          ),
      ]),
    );
  }
}

// ---------- small helpers ----------

class _Row extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? badge;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  const _Row({required this.title, required this.subtitle, this.badge, this.trailingIcon, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: PowerlineColors.textSecondary)),
              ]),
            ),
            if (badge != null)
              CircleAvatar(radius: 9, backgroundColor: PowerlineColors.cobalt, child: Text(badge!, style: const TextStyle(fontSize: 9))),
            if (trailingIcon != null)
              Icon(trailingIcon, size: 16, color: PowerlineColors.textSecondary),
          ]),
        ),
      );
}

class _More extends StatelessWidget {
  final VoidCallback onTap;
  const _More({required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: const Text('View all',
            style: TextStyle(fontSize: 11, color: PowerlineColors.cobalt)),
      );
}

class _Empty extends StatelessWidget {
  final String label;
  const _Empty(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(label, style: const TextStyle(fontSize: 12, color: PowerlineColors.textSecondary)),
      );
}

Widget _kv(String k, String v, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(Icons.circle, size: 9, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(k, style: const TextStyle(fontSize: 12))),
        Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );

String? _contactByPhone(AppState s, String phone) {
  final m = s.contacts.where((c) => c.phones.any((p) => p.e164 == phone)).firstOrNull;
  return m?.displayName;
}

String? _contactName(AppState s, String? contactId) {
  if (contactId == null) return null;
  final m = s.contacts.where((c) => c.id == contactId).firstOrNull;
  return m?.displayName;
}

String _lastBody(AppState s, String convId) {
  final msgs = s.messages.where((m) => m.conversationId == convId).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return msgs.firstOrNull?.body ?? '';
}
