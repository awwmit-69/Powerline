/// Call history with filters and CSV export.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../core/util/phone.dart';
import '../../domain/models/enums.dart';
import '../../providers.dart';
import 'package:collection/collection.dart';

class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  String filter = 'all';
  String search = '';

  @override
  Widget build(BuildContext context) {
    final s = stateOf(ref);
    var calls = [...s.calls]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    calls = switch (filter) {
      'inbound' => calls.where((c) => c.direction == CallDirection.inbound).toList(),
      'outbound' => calls.where((c) => c.direction == CallDirection.outbound).toList(),
      'missed' => calls.where((c) => c.missed).toList(),
      'voicemail' => calls.where((c) => c.finalState == CallState.voicemail).toList(),
      'ai' => calls.where((c) => c.agentKind == AgentKind.ai).toList(),
      'campaign' => calls.where((c) => c.campaignId != null).toList(),
      'failed' => calls.where((c) => c.finalState == CallState.failed).toList(),
      _ => calls,
    };
    if (search.isNotEmpty) {
      calls = calls.where((c) {
        final name = s.contacts.where((x) => x.id == c.contactId).firstOrNull?.displayName ?? '';
        return c.remoteE164.contains(search) ||
            name.toLowerCase().contains(search.toLowerCase());
      }).toList();
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Text('Call History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in const [
                  'all', 'inbound', 'outbound', 'missed', 'voicemail', 'ai', 'campaign', 'failed'
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: filter == f,
                      onSelected: (_) => setState(() => filter = f),
                    ),
                  ),
              ]),
            ),
          ),
          SizedBox(
            width: 200,
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 16),
                  hintText: 'Name or number',
                  isDense: true),
              onChanged: (v) => setState(() => search = v),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _export(calls),
            icon: const Icon(Icons.download, size: 14),
            label: const Text('Export'),
          ),
        ]),
      ),
      Expanded(
        child: calls.isEmpty
            ? const Center(child: Text('No calls match'))
            : ListView.builder(
                itemCount: calls.length,
                itemBuilder: (c, i) {
                  final call = calls[i];
                  final name = s.contacts
                      .where((x) => x.id == call.contactId)
                      .firstOrNull
                      ?.displayName;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      call.missed
                          ? Icons.phone_missed
                          : call.direction == CallDirection.inbound
                              ? Icons.call_received
                              : Icons.call_made,
                      size: 18,
                      color: call.missed
                          ? PowerlineColors.stateFailed
                          : PowerlineColors.stateConnected,
                    ),
                    title: Row(children: [
                      Text(name ?? PhoneNumberUtil.format(call.remoteE164)),
                      const SizedBox(width: 6),
                      if (call.agentKind == AgentKind.ai)
                        const Chip(
                            label: Text('AI', style: TextStyle(fontSize: 9)),
                            visualDensity: VisualDensity.compact),
                      if (call.isDemo) const DemoBadge(),
                    ]),
                    subtitle: Text(
                      '${call.startedAt.month}/${call.startedAt.day} '
                      '${call.startedAt.hour.toString().padLeft(2, '0')}:${call.startedAt.minute.toString().padLeft(2, '0')}'
                      ' · ${call.durationSeconds}s · ${call.disposition ?? call.finalState.name}'
                      '${call.handoffEventIds.isNotEmpty ? ' · handoff' : ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Call back (demo)',
                        icon: const Icon(Icons.call_outlined, size: 16),
                        onPressed: () => ref
                            .read(callSessionProvider.notifier)
                            .placeDemoCall(call.remoteE164),
                      ),
                      IconButton(
                        tooltip: 'Message',
                        icon: const Icon(Icons.message_outlined, size: 16),
                        onPressed: () => ref
                            .read(appRepositoryProvider)
                            .ensureConversation(call.remoteE164),
                      ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  Future<void> _export(List calls) async {
    final rows = StringBuffer(
        'id,direction,remoteE164,startedAt,durationSeconds,disposition,agentKind,provider,demo\n');
    for (final c in calls) {
      rows.writeln(
          '${c.id},${c.direction.name},${c.remoteE164},${c.startedAt.toIso8601String()},${c.durationSeconds},${c.disposition ?? ''},${c.agentKind.name},${c.provider},${c.isDemo}');
    }
    final loc = await getSaveLocation(suggestedName: 'powerline_calls.csv');
    if (loc == null) return;
    await File(loc.path).writeAsString(rows.toString(), encoding: utf8);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exported to ${loc.path}')));
    }
  }
}
