import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  try {
    await container.read(appRepositoryProvider).init();
  } catch (_) {
    // Non-fatal: continue to render even if persistence is unavailable (e.g. web).
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PowerlineApp(),
    ),
  );
}
