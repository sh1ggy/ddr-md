import 'package:ddr_md/components/settings/development_page.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_lab_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'development hub opens the permanent lab without an experiment flag',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DevelopmentToolsTile())));
    await tester.tap(find.text('Development'));
    await tester.pumpAndSettle();
    expect(find.text('Seeded score combinations'), findsOneWidget);
    await tester.tap(find.text('Jacket edition lab'));
    await tester.pumpAndSettle();
    expect(find.byType(EditionLabPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('leaving a lab that never captured timings releases cleanly',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditionLabPage()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
