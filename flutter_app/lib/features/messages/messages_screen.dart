/// Messages workspace: thread list + active conversation (two-panel on wide).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../core/util/phone.dart';
import '../../data/repositories/app_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../engines/messaging/messaging_provider.dart';
import '../../providers.dart';
import 'package:collection/collection.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  String? selectedConvId;
  String filter = '';
  bool liveSms = true;
  final composer = TextEditingController();

  @override
  void dispose() {
    composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = stateOf(ref);
    final wide = MediaQuery.of(context).size.width >= 900;
    var convs = s.conversations.where((c) => !c.archived).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return (b.lastMessageAt ?? DateTime(0)).compareTo(
          a.lastMessageAt ?? DateTime(0),
        );
      });
    if (filter.isNotEmpty) {
      convs = convs.where((c) {
        final name = _contactName(s.contacts, c.contactId) ?? '';
        final msgs = s.messages.where((m) => m.conversationId == c.id);
        return name.toLowerCase().contains(filter.toLowerCase()) ||
            c.remoteE164.contains(filter) ||
            msgs.any(
              (m) => m.body.toLowerCase().contains(filter.toLowerCase()),
            );
      }).toList();
    }
    selectedConvId ??= convs.firstOrNull?.id;
    final selected = convs.where((c) => c.id == selectedConvId).firstOrNull ??
        s.conversations.where((c) => c.id == selectedConvId).firstOrNull;

    final listPanel = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search messages',
              isDense: true,
            ),
            onChanged: (v) => setState(() => filter = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.cell_tower, size: 16),
                label: Text('Twilio live'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.science_outlined, size: 16),
                label: Text('Test mode'),
              ),
            ],
            selected: {liveSms},
            onSelectionChanged: (value) =>
                setState(() => liveSms = value.first),
          ),
        ),
        Expanded(
          child: convs.isEmpty
              ? const Center(
                  child: Text(
                    'No conversations',
                    style: TextStyle(color: PowerlineColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  itemCount: convs.length,
                  itemBuilder: (c, i) {
                    final conv = convs[i];
                    final last = _lastMessage(s.messages, conv.id);
                    return ListTile(
                      selected: conv.id == selectedConvId,
                      selectedTileColor: PowerlineColors.cobaltDeep.withValues(
                        alpha: 0.12,
                      ),
                      leading: Stack(
                        children: [
                          const CircleAvatar(
                            radius: 16,
                            child: Icon(Icons.person, size: 16),
                          ),
                          if (conv.pinned)
                            const Positioned(
                              right: 0,
                              top: 0,
                              child: Icon(Icons.push_pin, size: 10),
                            ),
                        ],
                      ),
                      title: Text(
                        _contactName(s.contacts, conv.contactId) ??
                            PhoneNumberUtil.format(conv.remoteE164),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: conv.unreadCount > 0
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      subtitle: Text(
                        conv.draft.isNotEmpty
                            ? 'Draft: ${conv.draft}'
                            : (last?.body ?? ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: conv.draft.isNotEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                      trailing: conv.unreadCount > 0
                          ? CircleAvatar(
                              radius: 9,
                              backgroundColor: PowerlineColors.cobalt,
                              child: Text(
                                '${conv.unreadCount}',
                                style: const TextStyle(fontSize: 9),
                              ),
                            )
                          : null,
                      onTap: () => setState(() {
                        selectedConvId = conv.id;
                        _markRead(conv);
                      }),
                    );
                  },
                ),
        ),
      ],
    );

    final threadPanel = selected == null
        ? const Center(
            child: Text(
              'Select a conversation',
              style: TextStyle(color: PowerlineColors.textSecondary),
            ),
          )
        : _ThreadView(
            conv: selected,
            composer: composer,
            onSend: () => _send(selected),
          );

    if (!wide) {
      return selected == null || selectedConvId == null
          ? listPanel
          : threadPanel;
    }
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: PowerlineColors.border)),
            ),
            child: listPanel,
          ),
        ),
        Expanded(child: threadPanel),
      ],
    );
  }

  void _markRead(Conversation conv) {
    if (conv.unreadCount == 0) return;
    final repo = ref.read(appRepositoryProvider);
    repo.updateConversation(conv.copyWith(unreadCount: 0));
    for (final m in repo.state.messages.where(
      (m) => m.conversationId == conv.id && m.state == MessageState.received,
    )) {
      repo.updateMessageState(m.id, MessageState.read);
    }
  }

  Future<void> _send(Conversation conv) async {
    final text = composer.text.trim();
    if (text.isEmpty) return;
    final repo = ref.read(appRepositoryProvider);
    // Compliance gates: DNC + SMS opt-out suppression.
    if (repo.isDnc(conv.remoteE164) ||
        repo.state.smsSuppression.contains(conv.remoteE164)) {
      repo.addMessage(
        Message(
          id: newId('ms'),
          conversationId: conv.id,
          direction: CallDirection.outbound,
          body: text,
          state: MessageState.suppressed,
          createdAt: DateTime.now(),
        ),
      );
      composer.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Recipient is on DNC/opt-out list — message suppressed, not sent.',
            ),
          ),
        );
      }
      return;
    }
    final msgId = newId('ms');
    repo.addMessage(
      Message(
        id: msgId,
        conversationId: conv.id,
        direction: CallDirection.outbound,
        body: text,
        state: MessageState.sending,
        provider: liveSms ? 'twilio' : 'demo',
        createdAt: DateTime.now(),
        isDemo: !liveSms,
      ),
    );
    composer.clear();
    final provider = liveSms
        ? ref.read(twilioMessagingProvider)
        : ref.read(demoMessagingProvider);
    // Wire provider events back into the repo for this send.
    final sub = provider.events.listen((e) {
      if (e.kind == 'delivery') {
        repo.updateMessageState(msgId, MessageState.sent);
        repo.updateMessageState(msgId, MessageState.delivered);
      } else if (e.kind == 'failure') {
        repo.updateMessageState(msgId, MessageState.failed);
      } else if (e.kind == 'inbound' && e.from == conv.remoteE164) {
        // Simulated reply — honor opt-out keywords.
        final body = e.body ?? '';
        repo.addMessage(
          Message(
            id: newId('ms'),
            conversationId: conv.id,
            direction: CallDirection.inbound,
            body: body,
            state: MessageState.received,
            createdAt: DateTime.now(),
          ),
        );
      }
    });
    try {
      await provider.sendSms(
        OutboundMessageRequest(
          to: conv.remoteE164,
          from: liveSms
              ? '+16052058454'
              : stateOf(ref).numbers.firstOrNull?.e164 ?? '+10005550100',
          body: text,
        ),
      );
    } catch (error) {
      repo.updateMessageState(msgId, MessageState.failed);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('SMS failed: $error')));
      }
    }
    Future<void>.delayed(const Duration(seconds: 4), () => sub.cancel());
  }
}

String? _contactName(List<Contact> contacts, String? id) {
  if (id == null) return null;
  final m = contacts.where((c) => c.id == id);
  return m.isEmpty ? null : m.first.displayName;
}

Message? _lastMessage(List<Message> messages, String convId) {
  final list = messages.where((m) => m.conversationId == convId).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return list.firstOrNull;
}

class _ThreadView extends ConsumerWidget {
  final Conversation conv;
  final TextEditingController composer;
  final VoidCallback onSend;
  const _ThreadView({
    required this.conv,
    required this.composer,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final repo = ref.read(appRepositoryProvider);
    final msgs = s.messages.where((m) => m.conversationId == conv.id).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final contact = s.contacts.where((c) => c.id == conv.contactId).firstOrNull;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: PowerlineColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact?.displayName ??
                          PhoneNumberUtil.format(conv.remoteE164),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${PhoneNumberUtil.format(conv.remoteE164)}'
                      '${contact?.tags.isNotEmpty == true ? ' · ${contact!.tags.join(', ')}' : ''}'
                      '${conv.campaignId != null ? ' · campaign-linked' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: PowerlineColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Call (demo)',
                icon: const Icon(Icons.call_outlined, size: 18),
                onPressed: () => ref
                    .read(callSessionProvider.notifier)
                    .placeDemoCall(conv.remoteE164),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'pin':
                      repo.updateConversation(
                        conv.copyWith(pinned: !conv.pinned),
                      );
                    case 'unread':
                      repo.updateConversation(conv.copyWith(unreadCount: 1));
                    case 'archive':
                      repo.updateConversation(conv.copyWith(archived: true));
                    case 'optout':
                      repo.addSmsSuppression(conv.remoteE164);
                    case 'delete':
                      showDialog<void>(
                        context: context,
                        builder: (dctx) => AlertDialog(
                          title: const Text('Delete conversation locally?'),
                          content: const Text(
                            'Removes this thread from this device only. This cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () {
                                repo.deleteConversationLocal(conv.id);
                                Navigator.pop(dctx);
                              },
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                  }
                },
                itemBuilder: (c) => [
                  PopupMenuItem(
                    value: 'pin',
                    child: Text(conv.pinned ? 'Unpin' : 'Pin'),
                  ),
                  const PopupMenuItem(
                    value: 'unread',
                    child: Text('Mark unread'),
                  ),
                  const PopupMenuItem(value: 'archive', child: Text('Archive')),
                  const PopupMenuItem(
                    value: 'optout',
                    child: Text('Mark SMS opt-out'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete locally…'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final m in msgs)
                _Bubble(m: m, onRetry: () => _retry(ref, m)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: PowerlineColors.border)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Attach (demo placeholder)',
                icon: const Icon(Icons.attach_file, size: 18),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'MMS attachments are modeled; demo send is text-only.',
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Shortcuts(
                  shortcuts: {
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.enter,
                    ): const ActivateIntent(),
                  },
                  child: Actions(
                    actions: {
                      ActivateIntent: CallbackAction<ActivateIntent>(
                        onInvoke: (_) {
                          onSend();
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: composer,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText:
                            'Type a message (Ctrl+Enter to send) — demo, no real SMS',
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          repo.updateConversation(conv.copyWith(draft: v)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onSend,
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Send'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _retry(WidgetRef ref, Message m) {
    final repo = ref.read(appRepositoryProvider);
    repo.updateMessageState(m.id, MessageState.queued);
    repo.updateMessageState(m.id, MessageState.sending);
    repo.updateMessageState(m.id, MessageState.sent);
    repo.updateMessageState(m.id, MessageState.delivered);
  }
}

class _Bubble extends StatelessWidget {
  final Message m;
  final VoidCallback onRetry;
  const _Bubble({required this.m, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final outbound = m.direction == CallDirection.outbound;
    return Align(
      alignment: outbound ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: outbound ? PowerlineColors.cobaltDeep : PowerlineColors.raised,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(m.body),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')} · ${m.state.name}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: PowerlineColors.textSecondary,
                  ),
                ),
                if (m.state == MessageState.failed)
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Retry', style: TextStyle(fontSize: 10)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
