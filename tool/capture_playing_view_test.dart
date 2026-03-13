import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:van_sole/main.dart';

void main() {
  testWidgets('capture playing view', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const VanSoleApp());
    await tester.pump(const Duration(milliseconds: 120));

    final startButton = find.byKey(const Key('start-campaign-button'));
    await tester.ensureVisible(startButton);
    await tester.tap(startButton, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byType(VanSoleApp),
      matchesGoldenFile('captures/playing_view.png'),
    );
  });
}
