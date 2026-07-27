/// Voicemail inbox with playback, transcripts, greetings management.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../core/util/phone.dart';
import '../../domain/models/models.dart';
import '../../providers.dart';
import 'package:collection/collection.dart';

class VoicemailScreen extends ConsumerStatefulWidget {
  const VoicemailScreen({super.key});

  @override
  ConsumerState<VoicemailScreen> createState() => _VoicemailScreenState();
}

class _VoicemailScreenState extends ConsumerState<VoicemailScreen> {
  final player = AudioPlayer();
  String? playingId;
  double speed = 1.0;
  String transcriptFilter = '';

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(Voicemail vm) async {
    if (playingId == vm.id) {
      await player.pause();
      setState(() => playingId = null);
      return;
    }
    try {
      await player.stop();
      await player.setPlaybackRate(speed);
      await player.play(AssetSource(vm.audioAsset.replaceFirst('assets/', '')));
      setState(() => playingId = vm.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Audio playback unavailable on this platform — transcript shown.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = stateOf(ref);
    var vms = s.voicemails.where((v) => !v.archived).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (transcriptFilter.isNotEmpty) {
      vms = vms
          .where(
            (v) =>
                v.transcript.toLowerCase().contains(
                      transcriptFilter.toLowerCase(),
                    ) ||
                v.remoteE164.contains(transcriptFilter),
          )
          .toList();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          final playing = vms.where((v) => v.id == playingId).firstOrNull;
          if (playing != null) _togglePlay(playing);
        },
      },
      child: Focus(
        autofocus: true,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Text(
                  'Voicemail',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                const DemoBadge(),
                const Spacer(),
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 16),
                      hintText: 'Search transcripts',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => transcriptFilter = v),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<double>(
                  value: speed,
                  items: const [
                    DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                    DropdownMenuItem(value: 1.0, child: Text('1x')),
                    DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                    DropdownMenuItem(value: 2.0, child: Text('2x')),
                  ],
                  onChanged: (v) {
                    setState(() => speed = v ?? 1.0);
                    player.setPlaybackRate(speed);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (vms.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No voicemails')),
                ),
              ),
            for (final vm in vms)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: () => _togglePlay(vm),
                            icon: Icon(
                              playingId == vm.id
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _callerName(ref, vm.remoteE164) ??
                                      PhoneNumberUtil.format(vm.remoteE164),
                                  style: TextStyle(
                                    fontWeight: vm.read
                                        ? FontWeight.w400
                                        : FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${vm.createdAt.month}/${vm.createdAt.day} '
                                  '${vm.createdAt.hour.toString().padLeft(2, '0')}:${vm.createdAt.minute.toString().padLeft(2, '0')}'
                                  ' · ${vm.durationSeconds}s · demo audio',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: PowerlineColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!vm.read)
                            const Icon(
                              Icons.fiber_new,
                              color: PowerlineColors.cobalt,
                            ),
                          PopupMenuButton<String>(
                            onSelected: (a) => _action(a, vm),
                            itemBuilder: (c) => [
                              PopupMenuItem(
                                value: 'read',
                                child: Text(
                                  vm.read ? 'Mark unread' : 'Mark read',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'call',
                                child: Text('Call back (demo)'),
                              ),
                              const PopupMenuItem(
                                value: 'msg',
                                child: Text('Message caller'),
                              ),
                              const PopupMenuItem(
                                value: 'contact',
                                child: Text('Add contact'),
                              ),
                              const PopupMenuItem(
                                value: 'transcribe',
                                child: Text('Transcribe (demo)'),
                              ),
                              const PopupMenuItem(
                                value: 'archive',
                                child: Text('Archive'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete…'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (vm.transcript.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: PowerlineColors.raised,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vm.transcript,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Simulated transcript · confidence ${(vm.transcriptConfidence * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: PowerlineColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Greetings',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    for (final g in const [
                      ('Business hours greeting', 'default'),
                      ('After-hours greeting', 'default'),
                      ('Unavailable greeting', 'default'),
                    ])
                      ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.record_voice_over_outlined,
                          size: 18,
                        ),
                        title: Text(g.$1),
                        subtitle: Text('Using ${g.$2} demo greeting'),
                        trailing: TextButton(
                          onPressed: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Greeting recording requires a live provider + microphone flow (not in demo).',
                              ),
                            ),
                          ),
                          child: const Text('Change'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _callerName(WidgetRef ref, String e164) {
    final s = stateOf(ref);
    final m = s.contacts.where((c) => c.phones.any((p) => p.e164 == e164));
    return m.isEmpty ? null : m.first.displayName;
  }

  Future<void> _action(String a, Voicemail vm) async {
    final repo = ref.read(appRepositoryProvider);
    switch (a) {
      case 'read':
        repo.updateVoicemail(vm.copyWith(read: !vm.read));
      case 'call':
        await ref
            .read(callSessionProvider.notifier)
            .placeDemoCall(vm.remoteE164);
      case 'msg':
        repo.ensureConversation(vm.remoteE164);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thread ready in Messages tab')),
          );
        }
      case 'contact':
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Use Contacts tab -> New to add this number'),
            ),
          );
        }
      case 'transcribe':
        final tp = ref.read(transcriptionProvider);
        final r = await tp.transcribe('${vm.audioAsset}#${vm.id}');
        repo.updateVoicemail(
          vm.copyWith(transcript: r.text, transcriptConfidence: r.confidence),
        );
      case 'archive':
        repo.updateVoicemail(vm.copyWith(archived: true));
      case 'delete':
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: const Text('Delete voicemail?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  repo.updateVoicemail(vm.copyWith(archived: true));
                  Navigator.pop(dctx);
                },
                child: const Text('Delete'),
              ),
            ],
          ),
        );
    }
  }
}
