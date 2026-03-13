// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:van_sole/main.dart';

void main() {
  testWidgets('shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const VanSoleApp());
    await tester.pump();

    expect(find.text('Van Solè'), findsWidgets);
    expect(find.text('CONTROL PANEL'), findsOneWidget);
    expect(find.text('RADAR / SPEED'), findsOneWidget);
    expect(find.text('Campaign'), findsOneWidget);
  });

  testWidgets('title session can start campaign', (WidgetTester tester) async {
    await tester.pumpWidget(const VanSoleApp());
    await tester.pump();

    final startButton = find.byKey(const Key('start-campaign-button'));
    expect(find.text('VAN SOLÈ'), findsWidgets);
    expect(startButton, findsOneWidget);

    await tester.ensureVisible(startButton);
    await tester.tap(startButton, warnIfMissed: false);
    await tester.pump();

    expect(startButton, findsNothing);
    expect(find.byKey(const Key('flight-surface')), findsOneWidget);
  });
}
