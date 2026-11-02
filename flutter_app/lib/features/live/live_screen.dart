import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'live_client.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});
  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final _client = createLiveClient();
  final _to = TextEditingController();
  final _body = TextEditingController();
  final _digits = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _poll;
  Map<String, dynamic>? _session;
  Map<String, dynamic> _provider = {};
  List<Map<String, dynamic>> _numbers = [], _messages = [], _calls = [], _users = [];
  String? _number;
  String _status = 'Calling is disconnected';
  String? _error;
  bool _busy = false, _refreshing = false, _ready = false;
  bool _active = false, _incoming = false, _muted = false;
  DateTime? _connectedAt;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    _subscription = _client.events.listen((event) {
      if (!mounted) return;
      setState(() {
        if (event['type'] == 'error') _error = event['message']?.toString();
        if (event['type'] == 'registration') {
          _ready = event['state'] == 'ready';
          _status = _ready ? 'Ready to receive calls' : 'Calling is disconnected';
        }
        if (event['type'] == 'call') {
          final state = event['state'].toString();
          _status = '${event['remote']} · $state';
          _incoming = state == 'incoming';
          _active = const ['incoming', 'dialing', 'ringing', 'connected'].contains(state);
          if (state == 'connected') _connectedAt ??= DateTime.now();
          if (!_active) {
            _connectedAt = null;
            _muted = false;
          }
        }
      });
    });
    _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  List<Map<String, dynamic>> _rows(Object? value) =>
      (value as List? ?? []).map((row) => Map<String, dynamic>.from(row as Map)).toList();

  Future<void> _perform(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await operation(); } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _perform(() async {
    final session = await _client.request('GET', '/api/session');
    final numbers = await _client.request('GET', '/api/numbers');
    final provider = await _client.request('GET', '/api/provider/status');
    final users = session['role'] == 'admin'
        ? await _client.request('GET', '/api/users') : <String, dynamic>{};
    if (!mounted) return;
    setState(() {
      _session = session;
      _numbers = _rows(numbers['numbers']);
      _provider = provider;
      _users = _rows(users['users']);
      if (!_numbers.any((n) => n['id'] == _number)) {
        _number = _numbers.isEmpty ? null : _numbers.first['id'].toString();
      }
    });
    await _refresh();
  });

  Future<void> _refresh() async {
    final number = _number;
    if (!kIsWeb || number == null || _refreshing || _session == null) return;
    _refreshing = true;
    try {
      final query = Uri(queryParameters: {'number_id': number}).query;
      final selected = _numbers.firstWhere((n) => n['id'] == number);
      final messages = selected['sms'] == 1
          ? await _client.request('GET', '/api/messages?$query') : <String, dynamic>{};
      final calls = selected['voice'] == 1
          ? await _client.request('GET', '/api/calls?$query') : <String, dynamic>{};
      if (!mounted || number != _number) return;
      setState(() { _messages = _rows(messages['messages']); _calls = _rows(calls['calls']); });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally { _refreshing = false; }
  }

  Future<void> _send() => _perform(() async {
    final result = await _client.request('POST', '/api/messages', {
      'number_id': _number, 'to': _to.text.trim(), 'body': _body.text,
    });
    if (!mounted) return;
    _body.clear();
    setState(() => _status = 'Message ${result['status']} · awaiting delivery receipt');
    await _refresh();
  });

  Future<void> _editUser(Map<String, dynamic> user) async {
    final email = TextEditingController(
      text: user['active'] == 1 ? user['email'].toString() : '',
    );
    final activate = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Configure ${user['id']}'),
      content: TextField(controller: email, keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Individual login email')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Activate account')),
      ],
    ));
    final address = email.text.trim();
    email.dispose();
    if (activate != true || !mounted) return;
    await _perform(() async {
      await _client.request('PATCH', '/api/users', {
        'id': user['id'], 'email': address, 'role': user['role'], 'active': true,
      });
      final result = await _client.request('GET', '/api/users');
      if (mounted) setState(() => _users = _rows(result['users']));
    });
  }

  Future<void> _permission(Map<String, dynamic> user, bool grant) => _perform(() async {
    await _client.request('POST', '/api/permissions', {
      'user_id': user['id'], 'number_id': _number, 'grant': grant,
    });
    if (mounted) setState(() => _status = '${user['id']} ${grant ? 'assigned to' : 'removed from'} selected line');
  });

  void _control(String action, [Object? value]) {
    try {
      _client.control(action, value);
      if (action == 'mute') setState(() => _muted = value == true);
    } catch (error) { setState(() => _error = error.toString()); }
  }

  Future<void> _open() async {
    final url = kIsWeb ? Uri.base : Uri.parse(const String.fromEnvironment(
      'POWERLINE_APP_URL', defaultValue: 'https://powerline.azdglobal.com/#/live',
    ));
    if (!await launchUrl(url, mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self') && mounted) {
      setState(() => _error = 'Could not open the protected workspace.');
    }
  }

  @override
  void dispose() {
    _poll?.cancel(); _subscription?.cancel(); _client.dispose();
    _to.dispose(); _body.dispose(); _digits.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _provider['enabled'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('POWERLINE'), actions: [
        if (kIsWeb) IconButton(onPressed: _busy ? null : _load,
          tooltip: 'Refresh workspace', icon: const Icon(Icons.refresh)),
      ]),
      body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text('Calls & messages', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(_session == null ? 'Sign in to your private workspace.' : '${_session!['email']} · ${_session!['role']}'),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (!kIsWeb) ...[
            const SizedBox(height: 24),
            const Text('Twilio audio on Windows uses the protected browser workspace. Open it in Edge or Chrome; you can install it as a desktop app. Native Windows audio is not implemented.'),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _open, icon: const Icon(Icons.open_in_browser), label: const Text('Open calling workspace')),
          ] else if (_session == null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: _open, child: const Text('Reload sign-in')),
          ] else ...[
            const SizedBox(height: 20),
            if (!enabled) const Text('Telecom is disabled until Twilio configuration and approved testing are complete.'),
            if (_numbers.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No active numbers assigned. Your administrator must connect an owned Twilio number.')),
            DropdownButtonFormField<String>(initialValue: _number,
              decoration: const InputDecoration(labelText: 'Your outgoing line'),
              items: [for (final n in _numbers) DropdownMenuItem(value: n['id'].toString(), child: Text(n['e164'].toString()))],
              onChanged: _active ? null : (value) {setState(() { _number = value; _messages = []; _calls = []; }); _refresh();}),
            const SizedBox(height: 16),
            TextField(controller: _to, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Recipient', hintText: '+1…')),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              OutlinedButton(onPressed: _busy || !enabled || _ready || _provider['voice_configured'] != true ? null : () => _perform(() async {await _client.initialize();}), child: const Text('Connect calling')),
              FilledButton.icon(onPressed: _busy || !_ready || _active || _number == null ? null : () => _perform(() => _client.call(_number!, _to.text.trim())), icon: const Icon(Icons.call), label: const Text('Call')),
              if (_incoming) FilledButton(onPressed: () => _control('answer'), child: const Text('Answer')),
              if (_incoming) OutlinedButton(onPressed: () => _control('reject'), child: const Text('Reject')),
              if (_active) OutlinedButton(onPressed: () => _control('hangup'), child: const Text('Hang up')),
              if (_active) OutlinedButton(onPressed: () => _control('mute', !_muted), child: Text(_muted ? 'Unmute' : 'Mute')),
            ]),
            const SizedBox(height: 12), Text(_status),
            if (_connectedAt != null) StreamBuilder<int>(stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
              builder: (context, snapshot) => Text('Duration: ${DateTime.now().difference(_connectedAt!).inSeconds}s')),
            if (_active) Row(children: [Expanded(child: TextField(controller: _digits,
              decoration: const InputDecoration(labelText: 'Keypad digits (0–9, * and #)'))),
              TextButton(onPressed: () => _control('digits', _digits.text), child: const Text('Send digits'))]),
            const SizedBox(height: 12),
            const Text('Emergency calling is unavailable. Calls are not recorded.'),
            const Divider(height: 32),
            TextField(controller: _body, maxLines: 3, maxLength: 1600,
              decoration: const InputDecoration(labelText: 'SMS message')),
            FilledButton.icon(onPressed: _busy || !enabled || _number == null || _provider['sms_configured'] != true ? null : _send,
              icon: const Icon(Icons.send), label: const Text('Send SMS')),
            const SizedBox(height: 24),
            Text('Messages', style: Theme.of(context).textTheme.titleLarge),
            if (_messages.isEmpty) const Text('No server messages for this line.'),
            for (final m in _messages) ListTile(title: Text(m['body'].toString()),
              subtitle: Text('${m['remote']} · ${m['direction']} · ${m['status']}')),
            const Divider(height: 32),
            Text('Call history', style: Theme.of(context).textTheme.titleLarge),
            if (_calls.isEmpty) const Text('No server call history for this line.'),
            for (final call in _calls) ListTile(title: Text(call['remote'].toString()),
              subtitle: Text('${call['direction']} · ${call['status']} · ${call['duration']}s')),
            if (_session!['role'] == 'admin') ...[
              const Divider(height: 32),
              Text('Team logins', style: Theme.of(context).textTheme.titleLarge),
              for (final user in _users) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${user['id']} · ${user['role']} · ${user['active'] == 1 ? user['email'] : 'Awaiting email'}'),
                  if (user['id'] != _session!['id']) Wrap(spacing: 8, children: [
                    TextButton(onPressed: _busy ? null : () => _editUser(user), child: const Text('Set login email')),
                    TextButton(onPressed: _busy || _number == null ? null : () => _permission(user, true), child: const Text('Assign selected line')),
                    TextButton(onPressed: _busy || _number == null ? null : () => _permission(user, false), child: const Text('Remove line access')),
                  ]),
                ],
              ))),
            ],
          ],
        ]),
      )),
    );
  }
}
