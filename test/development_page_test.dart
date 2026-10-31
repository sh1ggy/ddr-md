import 'package:ddr_md/components/settings/development_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('development hub lists its tools without an experiment flag',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DevelopmentToolsTile())));
    await tester.tap(find.text('Development'));
    await tester.pumpAndSettle();
    expect(find.text('Seeded score combinations'), findsOneWidget);
    expect(find.text('Frame timing lab'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
