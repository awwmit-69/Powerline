import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/theme.dart';
import 'features/search/search_palette.dart';
import 'router.dart';

class PowerlineApp extends ConsumerWidget {
  const PowerlineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'PowerLine',
      debugShowCheckedModeBanner: false,
      theme: powerlineTheme(),
      routerConfig: router,
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
            const OpenSearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK):
            const OpenSearchIntent(),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyD,
        ): const GoRouteIntent(
          '/dialpad',
        ),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyM):
            const GoRouteIntent('/messages'),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyC,
        ): const GoRouteIntent(
          '/contacts',
        ),
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyV,
        ): const GoRouteIntent(
          '/voicemail',
        ),
      },
      builder: (context, child) =>
          GlobalActions(child: child ?? const SizedBox()),
    );
  }
}

class OpenSearchIntent extends Intent {
  const OpenSearchIntent();
}

class GoRouteIntent extends Intent {
  final String route;
  const GoRouteIntent(this.route);
}

class GlobalActions extends ConsumerWidget {
  final Widget child;
  const GlobalActions({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Actions(
      actions: {
        OpenSearchIntent: CallbackAction<OpenSearchIntent>(
          onInvoke: (_) {
            showSearchPalette(context, ref);
            return null;
          },
        ),
        GoRouteIntent: CallbackAction<GoRouteIntent>(
          onInvoke: (intent) {
            ref.read(routerProvider).go(intent.route);
            return null;
          },
        ),
      },
      child: child,
    );
  }
}
