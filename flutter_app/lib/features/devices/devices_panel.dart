/// Device management panel + multi-device ring simulation trigger.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../domain/models/enums.dart';
import '../../providers.dart';

class DevicesPanel extends ConsumerWidget {
  const DevicesPanel({super.key});

  IconData _icon(DeviceType t) => switch (t) {
    DeviceType.windowsDesktop => Icons.desktop_windows,
    DeviceType.macDesktop => Icons.laptop_mac,
    DeviceType.androidPhone => Icons.phone_android,
    DeviceType.iphone => Icons.phone_iphone,
    DeviceType.webSession => Icons.public,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final repo = ref.read(appRepositoryProvider);
    final ring = ref.watch(ringSimProvider);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Text(
              'Devices',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            const DemoBadge(label: 'LOCAL SIMULATION'),
            const Spacer(),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.ring_volume, size: 16),
              label: const Text('Simulate multi-device ring'),
              onPressed: () => ref
                  .read(ringSimProvider.notifier)
                  .simulateRing('+13145550142'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'These are simulated device records. No real remote device is connected. Presence and ring events are generated locally.',
          style: TextStyle(fontSize: 11, color: PowerlineColors.textSecondary),
        ),
        if (ring.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            color: PowerlineColors.raised,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ring simulation events',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final e in ring)
                    Row(
                      children: [
                        Icon(
                          e.status == 'ringing'
                              ? Icons.ring_volume
                              : Icons.check_circle,
                          size: 14,
                          color: e.status == 'ringing'
                              ? PowerlineColors.stateRinging
                              : PowerlineColors.stateConnected,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${e.deviceName}: ${e.status}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  TextButton(
                    onPressed: () =>
                        ref.read(ringSimProvider.notifier).clearEvents(),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        for (final d in s.devices)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_icon(d.type)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  d.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (d.isThisDevice)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Chip(
                                      label: Text(
                                        'This device',
                                        style: TextStyle(fontSize: 9),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                if (d.revoked)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Chip(
                                      label: Text(
                                        'Revoked',
                                        style: TextStyle(fontSize: 9),
                                      ),
                                      backgroundColor:
                                          PowerlineColors.stateFailed,
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              '${d.type.name} · push: ${d.pushStatus} · last active ${_ago(d.lastActive)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: PowerlineColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    children: [
                      _toggle(
                        'Ring',
                        d.ringEnabled,
                        (v) => repo.updateDevice(d.copyWith(ringEnabled: v)),
                      ),
                      _toggle(
                        'Msg notif',
                        d.messageNotifications,
                        (v) => repo.updateDevice(
                          d.copyWith(messageNotifications: v),
                        ),
                      ),
                      _toggle(
                        'VM notif',
                        d.voicemailNotifications,
                        (v) => repo.updateDevice(
                          d.copyWith(voicemailNotifications: v),
                        ),
                      ),
                      if (!d.isThisDevice)
                        TextButton.icon(
                          icon: const Icon(Icons.logout, size: 14),
                          label: Text(
                            d.revoked ? 'Revoked' : 'Revoke / log out',
                          ),
                          onPressed: d.revoked
                              ? null
                              : () => repo.updateDevice(
                                  d.copyWith(revoked: true),
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 11)),
      Switch(value: value, onChanged: onChanged),
    ],
  );

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
