/// Responsive shell: navigation rail + call overlays on desktop, bottom
/// navigation on narrow screens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../domain/models/enums.dart';
import '../../providers.dart';
import '../call/active_call_screen.dart';
import '../call/incoming_call_screen.dart';
import '../search/search_palette.dart';

const _navItems = [
  ('/home', Icons.dashboard_outlined, 'Home'),
  ('/dialpad', Icons.dialpad, 'Dialpad'),
  ('/messages', Icons.chat_bubble_outline, 'Messages'),
  ('/calls', Icons.call_outlined, 'Calls'),
  ('/voicemail', Icons.voicemail, 'Voicemail'),
  ('/contacts', Icons.people_outline, 'Contacts'),
  ('/campaigns', Icons.campaign_outlined, 'Campaigns'),
  ('/agents', Icons.smart_toy_outlined, 'AI Agents'),
  ('/analytics', Icons.insights_outlined, 'Analytics'),
  ('/settings', Icons.settings_outlined, 'Settings'),
];

class AppShell extends ConsumerWidget {
  final String location;
  final Widget child;
  const AppShell({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(callSessionProvider);
    final wide = MediaQuery.of(context).size.width >= 900;
    final index =
        _navItems.indexWhere((i) => location.startsWith(i.$1)).clamp(0, 9);

    final body = Stack(
      children: [
        child,
        if (session != null &&
            session.snapshot.direction == CallDirection.inbound &&
            session.snapshot.state == CallState.ringing)
          const IncomingCallOverlay(),
        if (session != null &&
            !(session.snapshot.direction == CallDirection.inbound &&
                session.snapshot.state == CallState.ringing))
          const ActiveCallOverlay(),
      ],
    );

    if (!wide) {
      return Scaffold(
        appBar: AppBar(
          title: const PowerlineWordmark(size: 16),
          actions: [
            IconButton(
              tooltip: 'Search (Ctrl+K)',
              icon: const Icon(Icons.search),
              onPressed: () => showSearchPalette(context, ref),
            ),
          ],
        ),
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index.clamp(0, 4),
          onDestinationSelected: (i) => context.go(_navItems[i].$1),
          destinations: [
            for (final item in _navItems.take(5))
              NavigationDestination(icon: Icon(item.$2), label: item.$3),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            children: [
              const DrawerHeader(child: PowerlineWordmark()),
              for (final item in _navItems)
                ListTile(
                  leading: Icon(item.$2),
                  title: Text(item.$3),
                  selected: location.startsWith(item.$1),
                  onTap: () {
                    Navigator.pop(context);
                    context.go(item.$1);
                  },
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 216,
            decoration: const BoxDecoration(
              color: PowerlineColors.panel,
              border: Border(right: BorderSide(color: PowerlineColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: PowerlineWordmark(size: 17),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('Search   Ctrl+K'),
                    onPressed: () => showSearchPalette(context, ref),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (var i = 0; i < _navItems.length; i++)
                        _NavTile(
                          icon: _navItems[i].$2,
                          label: _navItems[i].$3,
                          selected: i == index,
                          onTap: () => context.go(_navItems[i].$1),
                        ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: DemoBadge(label: 'DEMO MODE — no live telecom'),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? PowerlineColors.cobaltDeep.withValues(alpha: 0.18)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? PowerlineColors.cobalt
                    : PowerlineColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? PowerlineColors.textPrimary
                      : PowerlineColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
