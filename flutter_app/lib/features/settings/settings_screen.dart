/// Settings: profile, defaults, devices, routing, business hours, numbers,
/// integrations, compliance (SMS/E911), backup/restore/export, demo reset.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../core/util/phone.dart';
import '../../providers.dart';
import '../devices/devices_panel.dart';
import '../integrations/integrations_panel.dart';
import 'package:collection/collection.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String section = 'general';

  static const sections = [
    ('general', Icons.tune, 'General'),
    ('numbers', Icons.tag, 'Phone numbers'),
    ('devices', Icons.devices, 'Devices'),
    ('routing', Icons.alt_route, 'Routing & hours'),
    ('integrations', Icons.extension, 'Integrations'),
    ('compliance', Icons.policy_outlined, 'Compliance & E911'),
    ('data', Icons.storage, 'Backup & data'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 210,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: PowerlineColors.border)),
            ),
            child: ListView(
              children: [
                for (final s in sections)
                  ListTile(
                    dense: true,
                    selected: section == s.$1,
                    leading: Icon(s.$2, size: 18),
                    title: Text(s.$3),
                    onTap: () => setState(() => section = s.$1),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: switch (section) {
            'numbers' => const _NumbersPanel(),
            'devices' => const DevicesPanel(),
            'routing' => const _RoutingPanel(),
            'integrations' => const IntegrationsPanel(),
            'compliance' => const _CompliancePanel(),
            'data' => const _DataPanel(),
            _ => const _GeneralPanel(),
          },
        ),
      ],
    );
  }
}

class _GeneralPanel extends ConsumerWidget {
  const _GeneralPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final repo = ref.read(appRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'General',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                TextFormField(
                  initialValue: s.settings['companyName'] ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Company profile name',
                  ),
                  onFieldSubmitted: (v) => repo.setSetting('companyName', v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: s.settings['defaultCountry'] ?? 'US',
                  decoration: const InputDecoration(
                    labelText: 'Default country',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'US', child: Text('United States')),
                  ],
                  onChanged: (v) =>
                      repo.setSetting('defaultCountry', v ?? 'US'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue:
                      s.settings['defaultTimeZone'] ?? 'America/Chicago',
                  decoration: const InputDecoration(
                    labelText: 'Default time zone',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'America/New_York',
                      child: Text('Eastern'),
                    ),
                    DropdownMenuItem(
                      value: 'America/Chicago',
                      child: Text('Central'),
                    ),
                    DropdownMenuItem(
                      value: 'America/Denver',
                      child: Text('Mountain'),
                    ),
                    DropdownMenuItem(
                      value: 'America/Los_Angeles',
                      child: Text('Pacific'),
                    ),
                  ],
                  onChanged: (v) => repo.setSetting(
                    'defaultTimeZone',
                    v ?? 'America/Chicago',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue:
                      s.settings['defaultCallerId'] ??
                      s.numbers.firstOrNull?.id,
                  decoration: const InputDecoration(
                    labelText: 'Default caller ID',
                  ),
                  items: [
                    for (final n in s.numbers)
                      DropdownMenuItem(
                        value: n.id,
                        child: Text('${n.label} (${n.e164})'),
                      ),
                  ],
                  onChanged: (v) => repo.setSetting('defaultCallerId', v ?? ''),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            title: const Text('Ring this device for inbound calls'),
            value:
                s.devices
                    .where((d) => d.isThisDevice)
                    .firstOrNull
                    ?.ringEnabled ??
                true,
            onChanged: (v) {
              final d = s.devices.where((d) => d.isThisDevice).firstOrNull;
              if (d != null) repo.updateDevice(d.copyWith(ringEnabled: v));
            },
          ),
        ),
      ],
    );
  }
}

class _NumbersPanel extends ConsumerWidget {
  const _NumbersPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Text(
              'Phone numbers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            FilledButton.tonal(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Number search/purchase/porting requires a live telephony provider. Demo numbers are fictional.',
                  ),
                ),
              ),
              child: const Text('Search / purchase (requires provider)'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'These are fictional demo numbers in the reserved 555 range. No real number has been provisioned.',
          style: TextStyle(fontSize: 11, color: PowerlineColors.textSecondary),
        ),
        const SizedBox(height: 10),
        for (final n in s.numbers)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${n.label}  ·  ${PhoneNumberUtil.format(n.e164)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      const DemoBadge(),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _cap('Voice', n.voiceEnabled),
                      _cap('SMS', n.smsEnabled),
                      _cap('MMS', n.mmsEnabled),
                      _cap('Fax', false),
                      Chip(
                        label: Text(
                          'E911: ${n.e911Status}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      Chip(
                        label: Text(
                          'CNAM: ${n.cnamStatus}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      Chip(
                        label: Text(
                          'A2P/10DLC: ${n.a2pStatus}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      Chip(
                        label: Text(
                          'Toll-free: ${n.tollFreeStatus}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      Chip(
                        label: Text(
                          'Provider: ${n.provider}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Port / release / E911 / caller-ID / SMS-registration actions are unavailable until a live provider is connected.',
                    style: TextStyle(
                      fontSize: 10,
                      color: PowerlineColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _cap(String label, bool on) => Chip(
    avatar: Icon(
      on ? Icons.check : Icons.close,
      size: 12,
      color: on ? PowerlineColors.stateConnected : PowerlineColors.stateFailed,
    ),
    label: Text(label, style: const TextStyle(fontSize: 10)),
  );
}

class _RoutingPanel extends ConsumerWidget {
  const _RoutingPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Routing & business hours',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Routing rules (priority order)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final r in s.routingRules)
                  ListTile(
                    dense: true,
                    leading: Text(
                      '${r.priority}',
                      style: const TextStyle(
                        color: PowerlineColors.textSecondary,
                      ),
                    ),
                    title: Text(r.name),
                    subtitle: Text(
                      '${r.strategy.name}${r.businessHoursOnly ? ' · business-hours only, after-hours → ${r.afterHoursAction}' : ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_circle_outline, size: 16),
                  label: const Text('Test routing now (simulator)'),
                  onPressed: () async {
                    await ref
                        .read(ringSimProvider.notifier)
                        .simulateRing('+15005550142');
                    final events = ref.read(ringSimProvider);
                    if (!context.mounted) return;
                    showDialog<void>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Routing simulation result'),
                        content: Text(
                          events
                              .map((e) => '${e.deviceName}: ${e.status}')
                              .join('\n'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(d),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Business hours (${s.businessHours.timeZone})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final day in const [
                  (1, 'Mon'),
                  (2, 'Tue'),
                  (3, 'Wed'),
                  (4, 'Thu'),
                  (5, 'Fri'),
                  (6, 'Sat'),
                  (7, 'Sun'),
                ])
                  Row(
                    children: [
                      SizedBox(width: 44, child: Text(day.$2)),
                      Text(
                        (s.businessHours.weekly[day.$1] ?? const [])
                                .map((w) => '${w[0]}:00–${w[1]}:00')
                                .join(', ')
                                .replaceFirst('', '')
                                .isEmpty
                            ? 'Closed'
                            : (s.businessHours.weekly[day.$1] ?? const [])
                                  .map((w) => '${w[0]}:00–${w[1]}:00')
                                  .join(', '),
                        style: const TextStyle(
                          color: PowerlineColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Text(
                  'After hours → ${s.businessHours.afterHoursBehavior}. Holidays: ${s.businessHours.holidays.isEmpty ? 'none configured' : s.businessHours.holidays.join(', ')}.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: PowerlineColors.textSecondary,
                  ),
                ),
                Text(
                  'Currently ${s.businessHours.isOpenAt(DateTime.now()) ? 'OPEN' : 'CLOSED'} (device-local approximation)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CompliancePanel extends ConsumerWidget {
  const _CompliancePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final repo = ref.read(appRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Compliance & E911',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Card(
          color: PowerlineColors.stateFailed.withValues(alpha: 0.08),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.emergency, color: PowerlineColors.stateFailed),
                    SizedBox(width: 8),
                    Text(
                      'E911 — READ CAREFULLY',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  '• Powerline demo mode CANNOT place emergency calls. Do not rely on it for 911.\n'
                  '• Live deployments must configure and validate an E911 address per number where legally required.\n'
                  '• No emergency address is configured. Status: not-configured / not-validated.\n'
                  '• Emergency calling is never simulated.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SMS compliance (A2P 10DLC / toll-free)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                _kv(
                  'Brand registration',
                  'not-submitted (requires live provider)',
                ),
                _kv('10DLC campaign', 'not-submitted (requires live provider)'),
                _kv(
                  'Toll-free verification',
                  'not-submitted (requires live provider)',
                ),
                _kv(
                  'Campaign use case',
                  'customer care + appointment reminders (draft)',
                ),
                _kv('Opt-in method', 'verbal + web form (draft, unverified)'),
                _kv(
                  'Opt-out keywords',
                  'STOP, UNSUBSCRIBE, CANCEL, END, QUIT (enforced locally)',
                ),
                _kv('Help keywords', 'HELP, INFO'),
                _kv(
                  'Sample message',
                  'Hi {firstName}, reminder about your inspection {date}. Reply STOP to opt out.',
                ),
                _kv(
                  'Privacy policy / Terms',
                  'placeholder links — set before live use',
                ),
                const SizedBox(height: 6),
                const Text(
                  'Nothing has been submitted to any registry. These are local drafts only.',
                  style: TextStyle(
                    fontSize: 11,
                    color: PowerlineColors.stateRinging,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suppression & DNC (${s.dnc.length} DNC, ${s.smsSuppression.length} SMS opt-outs)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final d in s.dnc.take(10))
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.block,
                      size: 14,
                      color: PowerlineColors.stateFailed,
                    ),
                    title: Text(PhoneNumberUtil.format(d.e164)),
                    subtitle: Text(
                      '${d.reason} · source: ${d.source}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Add number to DNC (E.164)',
                          isDense: true,
                        ),
                        onSubmitted: (v) {
                          final e = PhoneNumberUtil.normalize(v);
                          if (e != null) repo.addDnc(e, reason: 'manual entry');
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Legal notices',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  '• You are responsible for lawful calling and messaging (TCPA, TSR, state law).\n'
                  '• DNC and SMS opt-outs must be honored — Powerline enforces them locally.\n'
                  '• AI calling may require disclosure and/or consent in your jurisdiction.\n'
                  '• Call-recording consent laws vary by state; recording here is a demo marker only.\n'
                  '• Carrier and provider acceptable-use rules apply to live traffic.\n'
                  '• Nothing in this app is legal advice; no compliance guarantees are made.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 190,
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 11,
              color: PowerlineColors.textSecondary,
            ),
          ),
        ),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}

class _DataPanel extends ConsumerWidget {
  const _DataPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(appRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Backup & data',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Back up local database'),
                subtitle: const Text(
                  'Creates a timestamped JSON snapshot next to the live data file.',
                ),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    final path = await repo.backup();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Backup written: $path')),
                      );
                    }
                  },
                  child: const Text('Back up'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Exports'),
                subtitle: const Text(
                  'Contacts and Calls export from their tabs. Messages/voicemail/appointments/audit exports share the same CSV writer.',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reset demo data'),
                subtitle: const Text(
                  'Restores the original fictional seed. Your edits are lost.',
                ),
                trailing: OutlinedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Reset demo data?'),
                      content: const Text(
                        'All local changes will be replaced by fresh demo data.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () async {
                            await repo.resetDemoData();
                            if (d.mounted) Navigator.pop(d);
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Reset'),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_forever,
                  color: PowerlineColors.stateFailed,
                ),
                title: const Text('Delete all local data'),
                trailing: OutlinedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Delete ALL local data?'),
                      content: const Text(
                        'This wipes the local store. This cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: PowerlineColors.stateFailed,
                          ),
                          onPressed: () async {
                            await repo.deleteAllData();
                            if (d.mounted) Navigator.pop(d);
                          },
                          child: const Text('Delete everything'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
