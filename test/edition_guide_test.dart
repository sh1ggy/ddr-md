/// Name: Edition guide tests
/// Parent: EditionGuidePage
/// Description: Direct layer controls update the infographic on phone and desktop.
library;

import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_guide.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_artwork_picker.dart';
import 'package:ddr_md/grades.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(390, 800), const Size(1100, 800)]) {
    testWidgets('interactive infographic at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
          const MaterialApp(home: EditionGuidePage(editable: true)));
      expect(find.byType(JacketEdition), findsNWidgets(4));
      final grade = find.ancestor(
          of: find.text('Grade / surface'),
          matching:
              find.byWidgetPredicate((w) => w is DropdownButtonFormField));
      await tester.ensureVisible(grade);
      await tester.tap(grade);
      await tester.pumpAndSettle();
      await tester.tap(find.text('B+').last);
      await tester.pumpAndSettle();
      for (final card
          in tester.widgetList<JacketEdition>(find.byType(JacketEdition))) {
        expect(card.facts.grade, Grade.bPlus);
      }
      final precision = find.ancestor(
          of: find.text('Precision / frame upgrade'),
          matching:
              find.byWidgetPredicate((w) => w is DropdownButtonFormField));
      await tester.ensureVisible(precision);
      await tester.tap(precision);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SDP').last);
      await tester.pumpAndSettle();
      expect(find.text('SDP · pearly platinum'), findsOneWidget);
      final chip = find.widgetWithText(FilterChip, 'finish');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byType(JacketEdition), findsNWidgets(3));
      final jacket = find.byType(EditionArtworkPicker);
      await tester.ensureVisible(jacket);
      await tester.tap(jacket);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Neutral test jacket').last);
      await tester.pumpAndSettle();
      expect(find.byType(EditionGuidePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
