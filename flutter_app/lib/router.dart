import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/agents/agents_screen.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/calls/calls_screen.dart';
import 'features/campaigns/campaigns_screen.dart';
import 'features/contacts/contacts_screen.dart';
import 'features/dialpad/dialpad_screen.dart';
import 'features/home/home_screen.dart';
import 'features/messages/messages_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/voicemail/voicemail_screen.dart';
import 'features/workspaces/rep_workspace_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
          GoRoute(
            path: '/workspaces',
            builder: (c, s) => const RepWorkspaceScreen(),
          ),
          GoRoute(path: '/dialpad', builder: (c, s) => const DialpadScreen()),
          GoRoute(path: '/messages', builder: (c, s) => const MessagesScreen()),
          GoRoute(path: '/calls', builder: (c, s) => const CallsScreen()),
          GoRoute(
            path: '/voicemail',
            builder: (c, s) => const VoicemailScreen(),
          ),
          GoRoute(path: '/contacts', builder: (c, s) => const ContactsScreen()),
          GoRoute(
            path: '/campaigns',
            builder: (c, s) => const CampaignsScreen(),
          ),
          GoRoute(path: '/agents', builder: (c, s) => const AgentsScreen()),
          GoRoute(
            path: '/analytics',
            builder: (c, s) => const AnalyticsScreen(),
          ),
          GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
        ],
      ),
    ],
  );
});
