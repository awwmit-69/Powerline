/// Analytics dashboard — clearly labelled simulated demo data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logic/analytics.dart';
import '../../core/theme/theme.dart';
import '../../providers.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final a = computeAnalytics(
      calls: s.calls,
      messages: s.messages,
      voicemails: s.voicemails,
      appointments: s.appointments,
      handoffs: s.handoffs,
      dnc: s.dnc,
    );
    String pct(double v) => '${(v * 100).toStringAsFixed(0)}%';

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: const [
        Text('Analytics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        SizedBox(width: 8),
        DemoBadge(label: 'SIMULATED DEMO DATA'),
      ]),
      const SizedBox(height: 4),
      const Text(
        'All figures below derive from local demo records. Live analytics require a connected provider.',
        style: TextStyle(fontSize: 12, color: PowerlineColors.textSecondary),
      ),
      const SizedBox(height: 14),
      _Section(title: 'Calls', metrics: [
        ('Attempted', '${a.callsAttempted}'),
        ('Answered', '${a.callsAnswered}'),
        ('Missed', '${a.missedCalls}'),
        ('Avg duration', '${a.avgCallDurationSeconds.toStringAsFixed(0)}s'),
        ('Inbound', '${a.inboundCalls}'),
        ('Outbound', '${a.outboundCalls}'),
      ]),
      _Section(title: 'Messaging', metrics: [
        ('Sent', '${a.messagesSent}'),
        ('Received', '${a.messagesReceived}'),
        ('Delivery rate', pct(a.deliveryRate)),
        ('Response rate', pct(a.responseRate)),
      ]),
      _Section(title: 'Voicemail & appointments', metrics: [
        ('Voicemails', '${a.voicemails}'),
        ('Appointments booked', '${a.appointmentsBooked}'),
        ('Confirmed', '${a.appointmentsConfirmed}'),
      ]),
      _Section(title: 'AI & handoffs', metrics: [
        ('AI calls', '${a.aiCalls}'),
        ('Human calls', '${a.humanCalls}'),
        ('Handoffs', '${a.handoffCount}'),
        ('AI resolution rate', pct(a.aiResolutionRate)),
      ]),
      _Section(title: 'Compliance', metrics: [
        ('DNC records', '${a.dncCount}'),
        ('SMS suppressions', '${s.smsSuppression.length}'),
      ]),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Per-campaign performance (demo)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final cp in s.campaigns)
              Builder(builder: (context) {
                final cpCalls = s.calls.where((c) => c.campaignId == cp.id).toList();
                final appts = cpCalls.where((c) => c.disposition == 'appointment-set').length;
                return ListTile(
                  dense: true,
                  title: Text(cp.name),
                  subtitle: Text(
                      '${cpCalls.length} calls · $appts appointments · status ${cp.status.name}',
                      style: const TextStyle(fontSize: 11)),
                );
              }),
            const Divider(),
            const Text('Per-number performance (demo)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            for (final n in s.numbers)
              ListTile(
                dense: true,
                title: Text('${n.label} (${n.e164})'),
                subtitle: Text(
                    '${s.calls.where((c) => c.powerlineNumberId == n.id).length} calls',
                    style: const TextStyle(fontSize: 11)),
              ),
          ]),
        ),
      ),
    ]);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<(String, String)> metrics;
  const _Section({required this.title, required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 24, runSpacing: 12, children: [
              for (final m in metrics)
                SizedBox(
                  width: 140,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.$2,
                        style:
                            const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Text(m.$1,
                        style: const TextStyle(
                            fontSize: 11, color: PowerlineColors.textSecondary)),
                  ]),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
