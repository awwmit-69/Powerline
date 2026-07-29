import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/models/models2.dart';
import '../../providers.dart';

enum _RepView { roofing, data }

class RepWorkspaceScreen extends ConsumerStatefulWidget {
  const RepWorkspaceScreen({super.key});

  @override
  ConsumerState<RepWorkspaceScreen> createState() => _RepWorkspaceScreenState();
}

class _RepWorkspaceScreenState extends ConsumerState<RepWorkspaceScreen> {
  _RepView view = _RepView.roofing;

  @override
  Widget build(BuildContext context) {
    final state = stateOf(ref);
    final roofing = view == _RepView.roofing;
    final campaigns = state.campaigns.where((campaign) {
      final haystack =
          '${campaign.name} ${campaign.industry} ${campaign.offer}'.toLowerCase();
      return roofing
          ? haystack.contains('roof') || haystack.contains('restoration')
          : haystack.contains('data') ||
              haystack.contains('owner') ||
              haystack.contains('lead');
    }).toList();
    final campaignIds = campaigns.map((campaign) => campaign.id).toSet();
    final calls = state.calls
        .where((call) => call.campaignId == null ||
            campaignIds.isEmpty ||
            campaignIds.contains(call.campaignId))
        .toList();
    final deals = state.deals
        .where((deal) =>
            deal.campaignId == null || campaignIds.contains(deal.campaignId))
        .toList();
    final appointments = state.appointments
        .where((appointment) =>
            appointment.campaignId == null ||
            campaignIds.contains(appointment.campaignId))
        .toList();
    final answered = calls.where((call) => call.answeredAt != null).length;
    final aiCalls =
        calls.where((call) => call.agentKind == AgentKind.ai).length;
    final pipeline = deals.fold<double>(0, (sum, deal) => sum + deal.value);
    final conversations = [...state.conversations]
      ..sort((a, b) => (b.lastMessageAt ?? DateTime(0))
          .compareTo(a.lastMessageAt ?? DateTime(0)));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rep Command Center',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'One view for the work that makes the rep money today.',
                    style: TextStyle(color: PowerlineColors.textSecondary),
                  ),
                ],
              ),
            ),
            SegmentedButton<_RepView>(
              segments: const [
                ButtonSegment(
                  value: _RepView.roofing,
                  icon: Icon(Icons.roofing),
                  label: Text('Roofing Rep'),
                ),
                ButtonSegment(
                  value: _RepView.data,
                  icon: Icon(Icons.dataset_outlined),
                  label: Text('Data Rep'),
                ),
              ],
              selected: {view},
              onSelectionChanged: (value) =>
                  setState(() => view = value.first),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric('Calls', calls.length, Icons.call_outlined),
            _Metric('Answered', answered, Icons.phone_in_talk_outlined),
            _Metric('AI calls', aiCalls, Icons.smart_toy_outlined),
            _Metric(
              roofing ? 'Inspections' : 'Qualified buyers',
              roofing
                  ? appointments.length
                  : deals
                      .where((deal) => deal.stage != PipelineStage.newLead)
                      .length,
              roofing ? Icons.event_available : Icons.verified_outlined,
            ),
            _MoneyMetric('Open pipeline', pipeline),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1050;
            final queue = _QueuePanel(
              roofing: roofing,
              calls: calls,
              appointments: appointments,
              deals: deals,
              contacts: state.contacts,
            );
            final activity = _ActivityPanel(
              conversations: conversations.take(8).toList(),
              messages: state.messages,
              contacts: state.contacts,
            );
            final playbook = _PlaybookPanel(roofing: roofing);
            if (!wide) {
              return Column(
                children: [
                  queue,
                  const SizedBox(height: 12),
                  activity,
                  const SizedBox(height: 12),
                  playbook,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: queue),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: activity),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: playbook),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PowerlineColors.panel,
          border: Border.all(color: PowerlineColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  const _Metric(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 176,
        child: _Panel(
          child: Row(
            children: [
              Icon(icon, color: PowerlineColors.cobalt),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: PowerlineColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _MoneyMetric extends StatelessWidget {
  final String label;
  final double value;
  const _MoneyMetric(this.label, this.value);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 205,
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\$${value.toStringAsFixed(0)}',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: PowerlineColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}

class _QueuePanel extends StatelessWidget {
  final bool roofing;
  final List<CallRecord> calls;
  final List<Appointment> appointments;
  final List<PipelineDeal> deals;
  final List<Contact> contacts;
  const _QueuePanel({
    required this.roofing,
    required this.calls,
    required this.appointments,
    required this.deals,
    required this.contacts,
  });

  @override
  Widget build(BuildContext context) {
    final recent = [...calls]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            roofing ? 'Inspection & callback queue' : 'Buyer follow-up queue',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            roofing
                ? '${appointments.length} inspections · ${calls.where((c) => c.missed).length} missed calls'
                : '${deals.length} active opportunities · ${calls.where((c) => c.disposition == 'callback').length} callbacks',
            style: const TextStyle(
              fontSize: 12,
              color: PowerlineColors.textSecondary,
            ),
          ),
          const Divider(height: 24),
          for (final call in recent.take(8))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                call.missed ? Icons.phone_missed : Icons.call_made,
                size: 18,
                color: call.missed
                    ? PowerlineColors.stateFailed
                    : PowerlineColors.stateConnected,
              ),
              title: Text(
                contacts
                        .firstWhereOrNull((c) => c.id == call.contactId)
                        ?.displayName ??
                    call.remoteE164,
              ),
              subtitle: Text(
                '${call.disposition ?? call.finalState.name} · ${call.durationSeconds}s'
                '${call.agentKind == AgentKind.ai ? ' · AI' : ''}',
              ),
              trailing: IconButton(
                tooltip: 'Open dialpad',
                onPressed: () => context.go('/dialpad'),
                icon: const Icon(Icons.call_outlined, size: 17),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  final List<Conversation> conversations;
  final List<Message> messages;
  final List<Contact> contacts;
  const _ActivityPanel({
    required this.conversations,
    required this.messages,
    required this.contacts,
  });

  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent messages',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/messages'),
                  child: const Text('Open inbox'),
                ),
              ],
            ),
            for (final conversation in conversations)
              Builder(
                builder: (context) {
                  final last = messages
                      .where((m) => m.conversationId == conversation.id)
                      .sortedBy((m) => m.createdAt)
                      .lastOrNull;
                  final name = contacts
                          .firstWhereOrNull(
                            (c) => c.id == conversation.contactId,
                          )
                          ?.displayName ??
                      conversation.remoteE164;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.chat_bubble_outline, size: 17),
                    title: Text(name, maxLines: 1),
                    subtitle: Text(
                      last?.body ?? 'No messages yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: conversation.unreadCount == 0
                        ? null
                        : CircleAvatar(
                            radius: 10,
                            child: Text(
                              '${conversation.unreadCount}',
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                  );
                },
              ),
          ],
        ),
      );
}

class _PlaybookPanel extends StatelessWidget {
  final bool roofing;
  const _PlaybookPanel({required this.roofing});

  @override
  Widget build(BuildContext context) {
    final actions = roofing
        ? const [
            ('Call new storm leads', 'Lead with the free inspection.'),
            ('Return missed calls', 'Missed inbound calls close fastest.'),
            ('Confirm tomorrow', 'Text every booked homeowner.'),
            ('Escalate hot leads', 'Hand off insurance and damage questions.'),
          ]
        : const [
            ('Qualify the buyer', 'Industry, geography, volume, and use case.'),
            ('Prove the records', 'Show fields, recency, and suppression.'),
            ('Price the batch', '25k+, 60k+, and 105k+ tiers.'),
            ('Book the next order', 'Never end without volume and delivery date.'),
          ];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            roofing ? 'Roofing rep playbook' : 'TruuOwner data rep playbook',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final action in actions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(
                Icons.check_circle_outline,
                color: PowerlineColors.cobalt,
                size: 18,
              ),
              title: Text(action.$1),
              subtitle: Text(action.$2),
            ),
          const Divider(),
          FilledButton.icon(
            onPressed: () => context.go('/agents'),
            icon: const Icon(Icons.smart_toy_outlined, size: 17),
            label: const Text('Open AI callers'),
          ),
        ],
      ),
    );
  }
}
