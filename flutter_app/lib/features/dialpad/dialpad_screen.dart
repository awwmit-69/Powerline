/// Dialpad: formatting, contact lookup, caller-ID selection, demo call /
/// external dialer / copy, simulate-inbound helper.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/theme.dart';
import '../../core/util/phone.dart';
import '../../data/repositories/app_repository.dart';
import '../../domain/models/models.dart';
import '../../providers.dart';
import 'package:collection/collection.dart';

class DialpadScreen extends ConsumerStatefulWidget {
  const DialpadScreen({super.key});

  @override
  ConsumerState<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends ConsumerState<DialpadScreen> {
  String digits = '';
  String? callerIdNumberId;
  String mode = 'demo'; // demo | external

  void _append(String d) => setState(() => digits += d);
  void _backspace() => setState(
    () => digits = digits.isEmpty ? '' : digits.substring(0, digits.length - 1),
  );

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() => digits += data!.text!.replaceAll(RegExp(r'[^\d+*#]'), ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = stateOf(ref);
    final normalized = PhoneNumberUtil.normalize(digits);
    final matches = digits.length >= 3
        ? s.contacts
              .where(
                (c) =>
                    c.phones.any(
                      (p) =>
                          p.e164.contains(digits.replaceAll(RegExp(r'\D'), '')),
                    ) ||
                    c.displayName.toLowerCase().contains(digits.toLowerCase()),
              )
              .take(4)
              .toList()
        : <Contact>[];
    final recents = s.calls
        .take(5)
        .map((c) => c.remoteE164)
        .toSet()
        .take(4)
        .toList();
    callerIdNumberId ??=
        s.settings['defaultCallerId'] ?? s.numbers.firstOrNull?.id;

    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Dialpad',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Row(
                        children: [
                          const DemoBadge(),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Demo provider: local simulation only',
                            child: Icon(
                              Icons.circle,
                              size: 10,
                              color: PowerlineColors.stateRinging,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: PowerlineColors.raised,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            digits.isEmpty
                                ? 'Enter number'
                                : PhoneNumberUtil.formatPartial(digits),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: digits.isEmpty
                                  ? PowerlineColors.textSecondary
                                  : PowerlineColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Paste',
                          onPressed: _paste,
                          icon: const Icon(Icons.paste, size: 18),
                        ),
                        IconButton(
                          tooltip: 'Backspace',
                          onPressed: _backspace,
                          icon: const Icon(Icons.backspace_outlined, size: 18),
                        ),
                      ],
                    ),
                  ),
                  if (matches.isNotEmpty)
                    Column(
                      children: [
                        for (final m in matches)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_outline, size: 18),
                            title: Text(m.displayName),
                            subtitle: Text(
                              m.primaryPhone == null
                                  ? ''
                                  : PhoneNumberUtil.format(m.primaryPhone!),
                            ),
                            onTap: () => setState(
                              () => digits = m.primaryPhone ?? digits,
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  for (final row in const [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                    ['*', '0', '#'],
                  ])
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final key in row)
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: SizedBox(
                              width: 72,
                              height: 56,
                              child: OutlinedButton(
                                onPressed: () => _append(key),
                                child: Text(
                                  key,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: callerIdNumberId,
                          decoration: const InputDecoration(
                            labelText: 'Caller ID (outbound number)',
                            isDense: true,
                          ),
                          items: [
                            for (final n in s.numbers)
                              DropdownMenuItem(
                                value: n.id,
                                child: Text(
                                  '${n.label} ${PhoneNumberUtil.format(n.e164)}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => callerIdNumberId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'demo', label: Text('Demo')),
                          ButtonSegment(
                            value: 'external',
                            label: Text('OS dialer'),
                          ),
                        ],
                        selected: {mode},
                        onSelectionChanged: (v) =>
                            setState(() => mode = v.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: PowerlineColors.stateConnected,
                          minimumSize: const Size(140, 48),
                        ),
                        onPressed: normalized == null
                            ? null
                            : () => _call(normalized),
                        icon: const Icon(Icons.call),
                        label: Text(mode == 'demo' ? 'Demo call' : 'OS dialer'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: normalized == null
                            ? null
                            : () {
                                ref
                                    .read(appRepositoryProvider)
                                    .ensureConversation(normalized);
                                context.go('/messages');
                              },
                        icon: const Icon(Icons.message_outlined, size: 16),
                        label: const Text('Message'),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: 'Copy number',
                        onPressed: normalized == null
                            ? null
                            : () {
                                Clipboard.setData(
                                  ClipboardData(text: normalized),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Number copied'),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.copy, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Add contact',
                        onPressed: normalized == null
                            ? null
                            : () => _addContact(normalized),
                        icon: const Icon(Icons.person_add_alt, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (recents.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: [
                        const Text(
                          'Recent:',
                          style: TextStyle(
                            color: PowerlineColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        for (final r in recents)
                          ActionChip(
                            label: Text(
                              PhoneNumberUtil.format(r),
                              style: const TextStyle(fontSize: 11),
                            ),
                            onPressed: () => setState(
                              () => digits = r.replaceFirst('+1', ''),
                            ),
                          ),
                      ],
                    ),
                  const Divider(height: 24),
                  OutlinedButton.icon(
                    onPressed: () => ref
                        .read(callSessionProvider.notifier)
                        .simulateInbound('+13145550142'),
                    icon: const Icon(Icons.phone_callback_outlined, size: 16),
                    label: const Text('Simulate incoming demo call'),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Demo mode: calls are simulated locally. No real person is contacted. '
                    'Emergency calls are NOT possible.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: PowerlineColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _call(String e164) async {
    if (mode == 'external') {
      final uri = Uri.parse('tel:$e164');
      try {
        final ok = await canLaunchUrl(uri) && await launchUrl(uri);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No OS telephone handler available — number copied instead.',
              ),
            ),
          );
          await Clipboard.setData(ClipboardData(text: e164));
        }
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: e164));
      }
      return;
    }
    await ref
        .read(callSessionProvider.notifier)
        .placeDemoCall(e164, fromNumberId: callerIdNumberId);
  }

  void _addContact(String e164) {
    final repo = ref.read(appRepositoryProvider);
    final now = DateTime.now();
    repo.upsertContact(
      Contact(
        id: newId('ct'),
        firstName: 'New',
        lastName: 'Contact',
        phones: [PhoneEntry(label: 'mobile', e164: e164)],
        createdAt: now,
        updatedAt: now,
      ),
      op: 'create',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact created — edit in Contacts tab')),
    );
  }
}
