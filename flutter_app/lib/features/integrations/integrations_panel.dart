/// Provider integrations panel. Honest state reporting; write-only secrets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models2.dart';
import '../../providers.dart';

class IntegrationsPanel extends ConsumerWidget {
  const IntegrationsPanel({super.key});

  Color _stateColor(ProviderState s) => switch (s) {
    ProviderState.activeDemo => PowerlineColors.stateConnected,
    ProviderState.configured => PowerlineColors.stateHold,
    ProviderState.error => PowerlineColors.stateFailed,
    ProviderState.disabled => PowerlineColors.textSecondary,
    ProviderState.notConfigured => PowerlineColors.stateRinging,
  };

  String _stateLabel(ProviderState s) => switch (s) {
    ProviderState.activeDemo => 'Active (demo)',
    ProviderState.configured => 'Configured',
    ProviderState.error => 'Error',
    ProviderState.disabled => 'Disabled',
    ProviderState.notConfigured => 'Not configured',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final categories = [
      'telephony',
      'messaging',
      'ai',
      'transcription',
      'calendar',
      'crm',
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Provider integrations',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Secrets are write-only: once saved, only field names are shown, never values. Mock/demo providers are never presented as live.',
          style: TextStyle(fontSize: 11, color: PowerlineColors.textSecondary),
        ),
        const SizedBox(height: 10),
        for (final cat in categories) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              cat.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: PowerlineColors.textSecondary,
              ),
            ),
          ),
          for (final card in s.integrations.where((i) => i.category == cat))
            _IntegrationCardView(
              card: card,
              color: _stateColor(card.state),
              label: _stateLabel(card.state),
            ),
        ],
      ],
    );
  }
}

class _IntegrationCardView extends ConsumerWidget {
  final IntegrationCard card;
  final Color color;
  final String label;
  const _IntegrationCardView({
    required this.card,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(appRepositoryProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: color),
                const SizedBox(width: 8),
                Text(
                  card.provider,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Chip(label: Text(label, style: const TextStyle(fontSize: 10))),
                const Spacer(),
                if (card.state == ProviderState.notConfigured ||
                    card.state == ProviderState.error)
                  TextButton(
                    onPressed: () => _configure(context, ref),
                    child: const Text('Configure'),
                  ),
                if (card.configuredFieldNames.isNotEmpty ||
                    card.state == ProviderState.activeDemo)
                  TextButton(
                    onPressed: () => _test(context, repo),
                    child: const Text('Test connection'),
                  ),
              ],
            ),
            if (card.capabilities.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Capabilities: ${card.capabilities.join(', ')}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            if (card.missingCapabilities.isNotEmpty)
              Text(
                'Missing: ${card.missingCapabilities.join(', ')}',
                style: const TextStyle(
                  fontSize: 11,
                  color: PowerlineColors.stateRinging,
                ),
              ),
            if (card.configFields.isNotEmpty)
              Text(
                'Config fields: ${card.configFields.join(', ')}',
                style: const TextStyle(
                  fontSize: 11,
                  color: PowerlineColors.textSecondary,
                ),
              ),
            if (card.configuredFieldNames.isNotEmpty)
              Text(
                'Configured (secret) fields: ${card.configuredFieldNames.join(', ')} — values hidden',
                style: const TextStyle(
                  fontSize: 11,
                  color: PowerlineColors.textSecondary,
                ),
              ),
            if (card.lastError != null)
              Text(
                'Last error: ${card.lastError}',
                style: const TextStyle(
                  fontSize: 11,
                  color: PowerlineColors.stateFailed,
                ),
              ),
            if (card.lastTestAt != null)
              Text(
                'Last test: ${card.lastTestResult ?? 'n/a'} at ${card.lastTestAt}',
                style: const TextStyle(
                  fontSize: 11,
                  color: PowerlineColors.textSecondary,
                ),
              ),
            const Text(
              'Docs: (placeholder link — see PROVIDER_ADAPTERS.md)',
              style: TextStyle(
                fontSize: 10,
                color: PowerlineColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _configure(BuildContext context, WidgetRef ref) {
    final repo = ref.read(appRepositoryProvider);
    final controllers = {
      for (final f in card.configFields) f: TextEditingController(),
    };
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Configure ${card.provider}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Values are stored write-only in this demo (only field names are retained). '
                'A real deployment would use secure storage.',
                style: TextStyle(
                  fontSize: 11,
                  color: PowerlineColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              for (final f in card.configFields)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: TextField(
                    controller: controllers[f],
                    obscureText: true,
                    decoration: InputDecoration(labelText: f, isDense: true),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final provided = controllers.entries
                  .where((e) => e.value.text.isNotEmpty)
                  .map((e) => e.key)
                  .toList();
              // Store ONLY field names — never the secret values.
              repo.updateIntegration(
                card.copyWith(
                  state: provided.isEmpty
                      ? ProviderState.notConfigured
                      : ProviderState.configured,
                  configuredFieldNames: provided,
                  lastError: null,
                ),
              );
              Navigator.pop(d);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _test(BuildContext context, repo) {
    // Honest: demo providers report demo-active; mock providers cannot truly connect.
    final isDemo = card.state == ProviderState.activeDemo;
    repo.updateIntegration(
      card.copyWith(
        lastTestAt: DateTime.now(),
        lastTestResult: isDemo
            ? 'demo provider active (local simulation)'
            : 'mock adapter — no live endpoint to reach',
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isDemo
              ? '${card.provider}: demo provider active (simulated).'
              : '${card.provider}: mock adapter — cannot reach a live endpoint without real credentials.',
        ),
      ),
    );
  }
}
