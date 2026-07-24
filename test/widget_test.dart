import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:brarchive/main.dart';

void main() {
  testWidgets('Timer displays initial zero and start button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BrarchiveApp());

    expect(find.text('00:00:00.00'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('Tapping start button changes state to running', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BrarchiveApp());

    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(find.text('Pause'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
  });
}
