import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powerline/core/theme/theme.dart';
import 'package:powerline/data/local_store.dart';
import 'package:powerline/data/repositories/app_repository.dart';
import 'package:powerline/providers.dart';
import 'package:powerline/features/dialpad/dialpad_screen.dart';
import 'package:powerline/features/contacts/contacts_screen.dart';
import 'package:powerline/features/campaigns/campaigns_screen.dart';
import 'package:powerline/features/agents/agents_screen.dart';
import 'package:powerline/features/analytics/analytics_screen.dart';
import 'package:powerline/features/voicemail/voicemail_screen.dart';
import 'package:powerline/features/integrations/integrations_panel.dart';

Future<ProviderContainer> _seededContainer() async {
  final repo = AppRepository(MemorySnapshotStore());
  await repo.init();
  return ProviderContainer(
    overrides: [
      appRepositoryProvider.overrideWithValue(repo),
      snapshotStoreProvider.overrideWithValue(MemorySnapshotStore()),
    ],
  );
}

Widget _wrap(ProviderContainer c, Widget child) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    theme: powerlineTheme(),
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('Dialpad renders keys, formats input, shows Demo badge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = await _seededContainer();
    await tester.pumpWidget(_wrap(c, const DialpadScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Dialpad'), findsOneWidget);
    expect(find.text('DEMO'), findsWidgets);
    await tester.tap(find.widgetWithText(OutlinedButton, '2'));
    await tester.tap(find.widgetWithText(OutlinedButton, '1'));
    await tester.tap(find.widgetWithText(OutlinedButton, '4'));
    await tester.pump();
    expect(find.textContaining('214'), findsWidgets);
  });

  testWidgets('Contacts list renders seeded contacts', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = await _seededContainer();
    await tester.pumpWidget(_wrap(c, const ContactsScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsWidgets);
    expect(find.text('New'), findsWidgets);
  });

  testWidgets('Campaigns queue tab shows exclusion reasons', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = await _seededContainer();
    await tester.pumpWidget(_wrap(c, const CampaignsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Campaigns'), findsWidgets);
    await tester.tap(find.text('Calling queue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('callable'), findsOneWidget);
  });

  testWidgets('AI agents simulator runs and shows outcome', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = await _seededContainer();
    await tester.pumpWidget(_wrap(c, const AgentsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Run simulation'), findsOneWidget);
    await tester.tap(find.text('Run simulation'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Outcome:'), findsWidgets);
  });

  testWidgets('Analytics screen shows simulated-data badge', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = await _seededContainer();
    await tester.pumpWidget(_wrap(c, const AnalyticsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('SIMULATED DEMO DATA'), findsOneWidget);
    expect(find.text('Calls'), findsWidgets);
  });

  testWidgets('Voicemail inbox renders items and greetings', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = await _seededContainer();
    await tester.pumpWidget(_wrap(c, const VoicemailScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Voicemail'), findsWidgets);
    expect(find.text('Greetings'), findsOneWidget);
  });

  testWidgets('Integrations panel reports honest states', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = await _seededContainer();
    await tester.pumpWidget(_wrap(c, const IntegrationsPanel()));
    await tester.pumpAndSettle();
    expect(find.text('Provider integrations'), findsOneWidget);
    expect(find.textContaining('Not configured'), findsWidgets);
  });
}
