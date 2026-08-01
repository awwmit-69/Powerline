/// Active call overlay: call controls, notes, script, handoff, disposition.
/// Supports both the local demo engine and live Twilio browser calls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../core/util/phone.dart';
import '../../data/repositories/app_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models2.dart';
import '../../engines/call/call_engine.dart';
import '../../engines/handoff/handoff_machine.dart';
import '../../providers.dart';
import 'package:collection/collection.dart';

class ActiveCallOverlay extends ConsumerStatefulWidget {
  const ActiveCallOverlay({super.key});

  @override
  ConsumerState<ActiveCallOverlay> createState() => _ActiveCallOverlayState();
}

class _ActiveCallOverlayState extends ConsumerState<ActiveCallOverlay> {
  bool showKeypad = false;
  bool showScript = false;

  Color _stateColor(CallState s) => switch (s) {
        CallState.ringing ||
        CallState.dialing ||
        CallState.preparing =>
          PowerlineColors.stateRinging,
        CallState.connected => PowerlineColors.stateConnected,
        CallState.onHold || CallState.transferring => PowerlineColors.stateHold,
        CallState.voicemail => PowerlineColors.stateVoicemail,
        _ => PowerlineColors.stateFailed,
      };

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(callSessionProvider);
    if (session == null) return const SizedBox.shrink();
    final snap = session.snapshot;
    final isLive = session.providerId == 'twilio';
    final ctrl = ref.read(callSessionProvider.notifier);
    final s = stateOf(ref);
    final campaign = session.campaignId == null
        ? null
        : s.campaigns.where((c) => c.id == session.campaignId).firstOrNull;
    final company = session.contact?.companyId == null
        ? null
        : s.companies
            .where((c) => c.id == session.contact!.companyId)
            .firstOrNull;

    if (snap.state.isTerminal) {
      return _TerminalBar(
        snap: snap,
        callId: snap.callId,
        isLive: isLive,
        onDismiss: ctrl.clear,
        color: _stateColor(snap.state),
      );
    }

    return Positioned(
      right: 16,
      bottom: 16,
      child: Card(
        elevation: 8,
        child: Container(
          width: 400,
          constraints: const BoxConstraints(maxHeight: 560),
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (isLive)
                      const Chip(
                        avatar: Icon(Icons.cloud_done, size: 14),
                        label: Text('TWILIO LIVE'),
                        visualDensity: VisualDensity.compact,
                      )
                    else
                      const DemoBadge(label: 'DEMO CALL'),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _stateColor(snap.state).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        snap.state.name.toUpperCase(),
                        style: TextStyle(
                          color: _stateColor(snap.state),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  session.contact?.displayName ?? 'Unknown caller',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  PhoneNumberUtil.format(snap.remoteE164),
                  style: const TextStyle(color: PowerlineColors.textSecondary),
                ),
                if (company != null)
                  Text(
                    company.name,
                    style: const TextStyle(
                      color: PowerlineColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                Text(
                  '${snap.direction == CallDirection.inbound ? 'Inbound' : 'Outbound'} · '
                  'via ${isLive ? '+1 605-205-8454' : (s.numbers.firstOrNull?.label ?? 'demo number')} · '
                  'provider: ${isLive ? 'Twilio Voice' : 'Demo'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: PowerlineColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                _CallTimer(snap: snap),
                Row(
                  children: [
                    const Icon(
                      Icons.network_check,
                      size: 12,
                      color: PowerlineColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isLive
                          ? 'Live encrypted browser audio'
                          : 'Quality: n/a (simulated)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: PowerlineColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    if (snap.recording)
                      const Text(
                        'REC (marker only)',
                        style: TextStyle(
                          fontSize: 11,
                          color: PowerlineColors.stateFailed,
                        ),
                      ),
                  ],
                ),
                const Divider(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _Ctl(
                      icon: snap.muted ? Icons.mic_off : Icons.mic,
                      label: snap.muted ? 'Unmute' : 'Mute',
                      active: snap.muted,
                      onTap: () => ctrl.toggleMute(),
                    ),
                    _Ctl(
                      icon: snap.onHold ? Icons.play_arrow : Icons.pause,
                      label: snap.onHold ? 'Resume' : 'Hold',
                      active: snap.onHold,
                      onTap: isLive
                          ? null
                          : () => snap.onHold ? ctrl.resume() : ctrl.hold(),
                      disabledNote: isLive ? 'not enabled on trial' : null,
                    ),
                    _Ctl(
                      icon: Icons.dialpad,
                      label: 'Keypad',
                      active: showKeypad,
                      onTap: () => setState(() => showKeypad = !showKeypad),
                    ),
                    const _Ctl(
                      icon: Icons.volume_up,
                      label: 'Speaker',
                      disabledNote: 'placeholder',
                    ),
                    _Ctl(
                      icon: Icons.phone_forwarded,
                      label: 'Transfer',
                      onTap: isLive
                          ? null
                          : () => ctrl.transfer('ring-group:sales'),
                      disabledNote: isLive ? 'not enabled on trial' : null,
                    ),
                    const _Ctl(
                      icon: Icons.group_add,
                      label: 'Add',
                      disabledNote: 'demo marker',
                    ),
                    _Ctl(
                      icon: snap.recording
                          ? Icons.stop_circle
                          : Icons.fiber_manual_record,
                      label: snap.recording ? 'Stop rec' : 'Record',
                      onTap: isLive
                          ? null
                          : () => snap.recording
                              ? ref
                                  .read(demoCallEngineProvider)
                                  .stopRecording(snap.callId)
                              : ref
                                  .read(demoCallEngineProvider)
                                  .startRecording(snap.callId),
                      disabledNote: isLive ? 'not enabled on trial' : null,
                    ),
                    _Ctl(
                      icon: Icons.smart_toy_outlined,
                      label: 'AI handoff',
                      onTap: () => _handoffToAi(session),
                    ),
                  ],
                ),
                if (showKeypad)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (final k in '123456789*0#'.split(''))
                          SizedBox(
                            width: 52,
                            child: TextButton(
                              onPressed: () => ctrl.dtmf(k),
                              child: Text(k),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Call notes',
                    isDense: true,
                    hintText: 'Notes saved to the call record',
                  ),
                  minLines: 1,
                  maxLines: 3,
                  onChanged: ctrl.setNotes,
                ),
                const SizedBox(height: 8),
                if (campaign != null) ...[
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Campaign: ${campaign.name}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    initiallyExpanded: showScript,
                    onExpansionChanged: (v) => setState(() => showScript = v),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Script:\n${campaign.callScript}\n',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      for (final o in campaign.objectionLibrary.entries)
                        ListTile(
                          dense: true,
                          title: Text(
                            '"${o.key}"',
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            o.value,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ],
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _schedule(
                        context,
                        isAppointment: true,
                        session: session,
                      ),
                      icon: const Icon(Icons.event, size: 14),
                      label: const Text('Appointment'),
                    ),
                    TextButton.icon(
                      onPressed: () => _schedule(
                        context,
                        isAppointment: false,
                        session: session,
                      ),
                      icon: const Icon(Icons.update, size: 14),
                      label: const Text('Callback'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: PowerlineColors.stateFailed,
                        ),
                        onPressed: () => ctrl.end(),
                        icon: const Icon(Icons.call_end),
                        label: const Text('End call'),
                      ),
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

  void _handoffToAi(CallSession session) {
    final machine = session.handoff;
    if (machine.fire(
      HandoffTrigger.humanHandsToAi,
      reason: 'operator chose AI handoff',
    )) {
      machine.fire(HandoffTrigger.aiTransferComplete);
      ref.read(callSessionProvider.notifier).recordHandoff(
            HandoffKind.humanToAi,
            'operator chose AI handoff',
            'human:you',
            'ai:Demo AI Agent',
          );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Simulated: call handed to AI agent (recorded as handoff event)',
          ),
        ),
      );
    }
  }

  void _schedule(
    BuildContext context, {
    required bool isAppointment,
    required CallSession session,
  }) {
    final repo = ref.read(appRepositoryProvider);
    final contactId = session.contact?.id;
    if (contactId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No matched contact — add the contact first'),
        ),
      );
      return;
    }
    if (isAppointment) {
      repo.upsertAppointment(
        Appointment(
          id: newId('ap'),
          contactId: contactId,
          campaignId: session.campaignId,
          startsAt: DateTime.now().add(const Duration(days: 1)),
          kind: 'follow-up',
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Appointment created for tomorrow (edit in Campaigns)'),
        ),
      );
    } else {
      repo.upsertCallback(
        CallbackTask(
          id: newId('cb'),
          contactId: contactId,
          campaignId: session.campaignId,
          dueAt: DateTime.now().add(const Duration(hours: 4)),
          reason: 'Requested during call',
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Callback scheduled in 4 hours')),
      );
    }
  }
}

class _CallTimer extends StatefulWidget {
  final ActiveCallSnapshot snap;
  const _CallTimer({required this.snap});

  @override
  State<_CallTimer> createState() => _CallTimerState();
}

class _CallTimerState extends State<_CallTimer> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final snap = widget.snap;
        final ref0 = snap.connectedAt ?? snap.startedAt;
        final d = DateTime.now().difference(ref0);
        final label = snap.connectedAt == null ? 'Ringing' : 'Connected';
        String two(int n) => n.toString().padLeft(2, '0');
        return Text(
          '$label ${two(d.inMinutes)}:${two(d.inSeconds % 60)}',
          style: const TextStyle(
            fontSize: 12,
            color: PowerlineColors.textSecondary,
          ),
        );
      },
    );
  }
}

class _Ctl extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final String? disabledNote;
  const _Ctl({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
    this.disabledNote,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          style: IconButton.styleFrom(
            backgroundColor:
                active ? PowerlineColors.cobaltDeep : PowerlineColors.raised,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
    return disabledNote == null
        ? btn
        : Tooltip(message: disabledNote!, child: btn);
  }
}

class _TerminalBar extends ConsumerStatefulWidget {
  final ActiveCallSnapshot snap;
  final String callId;
  final bool isLive;
  final VoidCallback onDismiss;
  final Color color;
  const _TerminalBar({
    required this.snap,
    required this.callId,
    required this.isLive,
    required this.onDismiss,
    required this.color,
  });

  @override
  ConsumerState<_TerminalBar> createState() => _TerminalBarState();
}

class _TerminalBarState extends ConsumerState<_TerminalBar> {
  static const _dispositions = <String>[
    'Connected',
    'No Answer',
    'Voicemail',
    'Callback',
    'Not Interested',
    'Appointment Confirmed',
  ];
  String? _selected;

  void _apply(String disposition) {
    final repo = ref.read(appRepositoryProvider);
    final existing =
        repo.state.calls.firstWhereOrNull((c) => c.id == widget.callId);
    if (existing != null) {
      repo.updateCall(existing.copyWith(disposition: disposition));
    }
    setState(() => _selected = disposition);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isLive ? 'Call ended' : 'Demo call ended';
    return Positioned(
      right: 16,
      bottom: 16,
      child: Card(
        elevation: 8,
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.call_end, size: 16, color: widget.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$label · ${widget.snap.state.name}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Saved to Call History. Set a disposition:',
                style: TextStyle(
                  fontSize: 11,
                  color: PowerlineColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in _dispositions)
                    ChoiceChip(
                      label: Text(d, style: const TextStyle(fontSize: 11)),
                      selected: _selected == d,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _apply(d),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onDismiss,
                  child: Text(
                    _selected == null
                        ? 'Skip & back to dialer'
                        : 'Back to dialer',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
