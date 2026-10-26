import 'package:ddr_md/components/song/scores/art_badge.dart';
import 'package:ddr_md/components/songlist/flare_card.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/db_models.dart' show ClearLamp;
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a 1,000,000 score keeps the badges in line', (tester) async {
    Widget row(Key key, int? score) => ChartBestBadges((
          score: score,
          grade: Grade.aaa,
          lamp: ClearLamp.values.last,
          flare: 'IX'
        ), key: key, ink: 12, height: 20, score: true);
    const million = Key('million'), lower = Key('lower'), none = Key('none');
    await tester.pumpWidget(MaterialApp(
      theme: floorPopTheme(Brightness.dark),
      home: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row(million, 1000000),
        row(lower, 987650),
        row(none, null),
      ]),
    ));
    final widths = [
      for (final k in [million, lower, none])
        tester.getSize(find.byKey(k)).width
    ];
    expect(widths.toSet(), hasLength(1));
    // The million fits its slot, clear of the grade badge.
    final grade = find.descendant(
        of: find.byKey(million), matching: find.byType(CardBadge));
    expect(tester.getRect(find.text('1,000,000')).right,
        lessThanOrEqualTo(tester.getRect(grade.first).left));
    expect(tester.takeException(), isNull);
  });
}
