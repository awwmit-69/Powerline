/// Incoming demo-call overlay with answer/decline/voicemail + multi-device
/// ring simulation display.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../core/util/phone.dart';
import '../../providers.dart';
import 'package:collection/collection.dart';

class IncomingCallOverlay extends ConsumerStatefulWidget {
  const IncomingCallOverlay({super.key});

  @override
  ConsumerState<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = ref.read(callSessionProvider);
      if (session != null) {
        ref.read(ringSimProvider.notifier).simulateRing(session.snapshot.remoteE164);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(callSessionProvider);
    if (session == null) return const SizedBox.shrink();
    final ctrl = ref.read(callSessionProvider.notifier);
    final ringEvents = ref.watch(ringSimProvider);
    final s = stateOf(ref);
    final number = s.numbers.firstOrNull;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        alignment: Alignment.center,
        child: Card(
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DemoBadge(label: 'SIMULATED INCOMING CALL'),
                const SizedBox(height: 14),
                CircleAvatar(
                  radius: 34,
                  backgroundColor: PowerlineColors.raised,
                  child: Icon(
                    session.contact == null ? Icons.person_off_outlined : Icons.person,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  session.contact?.displayName ?? 'Unknown caller',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                Text(PhoneNumberUtil.format(session.snapshot.remoteE164),
                    style: const TextStyle(color: PowerlineColors.textSecondary)),
                if (number != null)
                  Text('to ${number.label} ${PhoneNumberUtil.format(number.e164)} · ring group: Sales',
                      style: const TextStyle(
                          fontSize: 11, color: PowerlineColors.textSecondary)),
                const SizedBox(height: 12),
                if (ringEvents.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Multi-device ring (simulated):',
                        style: TextStyle(fontSize: 11, color: PowerlineColors.textSecondary)),
                  ),
                  for (final e in ringEvents)
                    Row(children: [
                      Icon(
                        e.status == 'ringing' ? Icons.ring_volume : Icons.smartphone,
                        size: 12,
                        color: e.status == 'ringing'
                            ? PowerlineColors.stateRinging
                            : PowerlineColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text('${e.deviceName}: ${e.status}',
                          style: const TextStyle(fontSize: 11)),
                    ]),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundBtn(
                      color: PowerlineColors.stateFailed,
                      icon: Icons.call_end,
                      label: 'Decline',
                      onTap: () {
                        ref.read(ringSimProvider.notifier).clearEvents();
                        ctrl.reject();
                      },
                    ),
                    _RoundBtn(
                      color: PowerlineColors.stateVoicemail,
                      icon: Icons.voicemail,
                      label: 'Voicemail',
                      onTap: () {
                        ref.read(ringSimProvider.notifier).clearEvents();
                        ctrl.sendToVoicemail();
                      },
                    ),
                    _RoundBtn(
                      color: PowerlineColors.stateConnected,
                      icon: Icons.call,
                      label: 'Answer',
                      onTap: () {
                        ref.read(ringSimProvider.notifier).clearEvents();
                        ctrl.accept();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RoundBtn({required this.color, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(16), child: Icon(icon, size: 24)),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);
  }
}
