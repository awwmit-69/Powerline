/// Maya console: her live calls (recording + transcript), voicemails,
/// upcoming bookings, and her call flow (greeting + script) for admins.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/theme.dart';
import '../../engines/ai/maya_console.dart';

final MayaConsole _console = createMayaConsole();

String _when(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  return t == null ? '' : DateFormat('EEE MMM d, h:mm a').format(t.toLocal());
}

String _length(Object? seconds) {
  final s = (seconds is num) ? seconds.toInt() : int.tryParse('$seconds') ?? 0;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class MayaScreen extends StatelessWidget {
  const MayaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!_console.available) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'The Maya console runs on PowerLine Web, where you are signed in '
            'as an agent. Open PowerLine in your browser to see her calls, '
            'recordings, bookings and call flow.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return const DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.record_voice_over_outlined), text: 'Calls'),
              Tab(icon: Icon(Icons.voicemail), text: 'Voicemail'),
              Tab(icon: Icon(Icons.event_available_outlined), text: 'Bookings'),
              Tab(icon: Icon(Icons.alt_route), text: 'Call flow'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _CallsTab(),
                _VoicemailTab(),
                _BookingsTab(),
                _FlowTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads one console action and shows loading / error / data states.
class _Loader extends StatefulWidget {
  final String action;
  final Widget Function(BuildContext, Map<String, dynamic>, VoidCallback)
  builder;
  const _Loader({required this.action, required this.builder});

  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _console.run(widget.action);
  }

  void _reload() => setState(() => _future = _console.run(widget.action));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${snap.error}'.replaceFirst('Exception: ', ''),
                  style: const TextStyle(color: PowerlineColors.stateFailed),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }
        return widget.builder(context, snap.data ?? const {}, _reload);
      },
    );
  }
}

// ---------------- audio ----------------
class _PlayButton extends StatefulWidget {
  final String action;
  final Map<String, String> fields;
  const _PlayButton({required this.action, required this.fields});

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;
  bool _playing = false;
  String? _url;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      _url ??= await _console.audioUrl(widget.action, widget.fields);
      await _player.play(UrlSource(_url!));
      if (mounted) setState(() => _playing = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _playing ? 'Pause recording' : 'Play recording',
      onPressed: _loading ? null : _toggle,
      icon: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_playing ? Icons.pause_circle : Icons.play_circle),
    );
  }
}

// ---------------- calls ----------------
class _CallsTab extends StatelessWidget {
  const _CallsTab();

  @override
  Widget build(BuildContext context) {
    return _Loader(
      action: 'calls',
      builder: (context, data, reload) {
        final calls = (data['calls'] as List? ?? const []).cast<Map>();
        if (calls.isEmpty) {
          return const Center(child: Text('No Maya calls yet.'));
        }
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: calls.length,
            separatorBuilder: (context, index) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final c = calls[i];
              final ok = c['result'] == 'success';
              return Card(
                child: ListTile(
                  leading: Icon(
                    c['direction'] == 'outbound'
                        ? Icons.call_made
                        : Icons.call_received,
                    color: ok
                        ? PowerlineColors.stateConnected
                        : PowerlineColors.textSecondary,
                  ),
                  title: Text(
                    '${c['title'] ?? ''}'.isEmpty
                        ? 'Maya call'
                        : '${c['title']}',
                  ),
                  subtitle: Text(
                    '${_when(c['started'] as String?)} · ${_length(c['seconds'])}',
                  ),
                  trailing: _PlayButton(
                    action: 'call_audio',
                    fields: {'id': '${c['id']}'},
                  ),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _CallDetail(id: '${c['id']}'),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _CallDetail extends StatelessWidget {
  final String id;
  const _CallDetail({required this.id});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _console.run('call', {'id': id}),
          builder: (context, snap) {
            if (!snap.hasData) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: snap.hasError
                      ? Text('${snap.error}')
                      : const CircularProgressIndicator(),
                ),
              );
            }
            final d = snap.data!;
            final collected = (d['collected'] as Map? ?? const {});
            final transcript = (d['transcript'] as List? ?? const [])
                .cast<Map>();
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${d['caller'] ?? ''}'.isEmpty
                            ? 'Maya call'
                            : '${d['caller']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (d['has_audio'] == true)
                      _PlayButton(action: 'call_audio', fields: {'id': id}),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  '${_when(d['started'] as String?)} · ${_length(d['seconds'])} · ${d['result'] ?? ''}',
                  style: const TextStyle(color: PowerlineColors.textSecondary),
                ),
                if ('${d['summary'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('${d['summary']}'),
                ],
                if (collected.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in collected.entries)
                        Chip(label: Text('${e.key}: ${e.value}')),
                    ],
                  ),
                ],
                const Divider(height: 28),
                for (final t in transcript)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${t['who']}: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: t['who'] == 'Maya'
                                  ? PowerlineColors.violet
                                  : PowerlineColors.cyan,
                            ),
                          ),
                          TextSpan(text: '${t['text']}'),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------- voicemail ----------------
class _VoicemailTab extends StatelessWidget {
  const _VoicemailTab();

  @override
  Widget build(BuildContext context) {
    return _Loader(
      action: 'voicemails',
      builder: (context, data, reload) {
        final items = (data['voicemails'] as List? ?? const []).cast<Map>();
        if (items.isEmpty) return const Center(child: Text('No recordings.'));
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final v in items)
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.voicemail,
                    color: PowerlineColors.stateVoicemail,
                  ),
                  title: Text(_when(v['started']?.toString())),
                  subtitle: Text(_length(v['seconds'])),
                  trailing: _PlayButton(
                    action: 'voicemail_audio',
                    fields: {'sid': '${v['sid']}'},
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------- bookings ----------------
class _BookingsTab extends StatelessWidget {
  const _BookingsTab();

  @override
  Widget build(BuildContext context) {
    return _Loader(
      action: 'bookings',
      builder: (context, data, reload) {
        final items = (data['bookings'] as List? ?? const []).cast<Map>();
        if (items.isEmpty) {
          return const Center(child: Text('No upcoming appointments.'));
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final b in items)
              Card(
                child: ListTile(
                  leading: Icon(
                    b['status'] == 'confirmed'
                        ? Icons.verified
                        : Icons.event_outlined,
                    color: b['status'] == 'confirmed'
                        ? PowerlineColors.stateConnected
                        : PowerlineColors.stateRinging,
                  ),
                  title: Text('${b['label']} · ${b['name'] ?? ''}'),
                  subtitle: Text(
                    [
                      b['service'],
                      b['phone'],
                      b['address'],
                      b['status'],
                    ].where((x) => '${x ?? ''}'.isNotEmpty).join(' · '),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------- call flow ----------------
class _FlowTab extends StatelessWidget {
  const _FlowTab();

  @override
  Widget build(BuildContext context) {
    return _Loader(
      action: 'flow_get',
      builder: (context, data, reload) => _FlowEditor(data: data),
    );
  }
}

class _FlowEditor extends StatefulWidget {
  final Map<String, dynamic> data;
  const _FlowEditor({required this.data});

  @override
  State<_FlowEditor> createState() => _FlowEditorState();
}

class _FlowEditorState extends State<_FlowEditor> {
  late final TextEditingController _greeting = TextEditingController(
    text: '${widget.data['first_message'] ?? ''}',
  );
  late final TextEditingController _script = TextEditingController(
    text: '${widget.data['prompt'] ?? ''}',
  );
  bool _saving = false;

  @override
  void dispose() {
    _greeting.dispose();
    _script.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _console.run('flow_set', {
        'first_message': _greeting.text,
        'prompt': _script.text,
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Saved. Maya uses it on her next call.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.data['can_edit'] == true;
    final switches = (widget.data['switches'] as Map? ?? const {});
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in switches.entries)
              Chip(
                avatar: Icon(
                  e.value == false ? Icons.toggle_off : Icons.toggle_on,
                  color: e.value == false
                      ? PowerlineColors.textSecondary
                      : PowerlineColors.stateConnected,
                ),
                label: Text('${e.key.toString().replaceAll('_', ' ')}: ${e.value}'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Switches and hours are server settings (Twilio Functions environment).',
          style: TextStyle(color: PowerlineColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _greeting,
          enabled: canEdit,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Greeting (first thing Maya says)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _script,
          enabled: canEdit,
          minLines: 16,
          maxLines: 40,
          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Call flow script (Maya follows this on every call)',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: canEdit
              ? FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save call flow'),
                )
              : const Text('Only admins can change Maya\'s call flow.'),
        ),
      ],
    );
  }
}
