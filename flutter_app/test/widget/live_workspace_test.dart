import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powerline/features/live/live_screen.dart';

void main() {
  testWidgets('desktop workspace offers browser audio without fake calls',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LiveScreen()));
    expect(find.text('Open calling workspace'), findsOneWidget);
    expect(find.text('Send SMS'), findsNothing);
    expect(find.text('Ready to receive calls'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
