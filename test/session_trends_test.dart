import 'package:ddr_md/components/session/pad_check.dart';
import 'package:ddr_md/components/session/session_summary.dart';
import 'package:ddr_md/components/session/session_trends_page.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/pad_rating.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/session_trends.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const cab = Cabinet(1, 1, 'Arcade', '');

TrendPlay play(String chart, DateTime at, int score,
        {PadSide side = PadSide.p1, int level = 15}) =>
    TrendPlay(
        RecentPlay(
            konamiId: chart,
            title: chart,
            song: chart,
            mode: Modes.singles,
            difficulty: 'EXPERT',
            playedAt: at,
            score: score),
        venueId: 1,
        cabinetId: 1,
        side: side,
        visitKey: '${at.month}-${at.day}',
        level: level);

TrendSources sources(List<TrendPlay> plays,
        {List<PadRating> ratings = const []}) =>
    (
      plays: plays,
      model: ScoreModel(
          [for (final p in plays.reversed) p.play], [], (_, __, ___) => 15),
      cabinets: {1: cab},
      ratings: ratings,
      gains: const [],
      goals: const {},
    );

// Mondays of three weeks running, then a 2P week.
final plays = [
  play('a', DateTime(2026, 10, 12, 18), 900000),
  play('b', DateTime(2026, 10, 12, 18), 950000, level: 16),
  play('a', DateTime(2026, 10, 19, 18), 920000),
  play('b', DateTime(2026, 10, 19, 18), 940000, level: 16),
  play('a', DateTime(2026, 10, 27, 18), 905000, side: PadSide.p2),
];

void main() {
  test('weeks read against the usual, with upscores, levels and side lamps',
      () {
    final h = TrendHistory(
        sources(plays, ratings: [
          PadRating(
              sessionId: 's',
              cabinet: cab,
              side: PadSide.p1,
              lamp: ClearLamp.gfc,
              sessionAt: DateTime(2026, 10, 19, 17)),
        ]),
        const TrendFilter());
    final w = TrendWindow.containing(DateTime(2026, 10, 21));
    final week = h.week(w);
    expect(w.start, DateTime(2026, 10, 19));
    // a: +20k on 900k, b: −10k on 950k, equal weight.
    expect(week.gap, closeTo(5000, 1));
    expect(week.levels, {15: closeTo(20000, 1), 16: closeTo(-10000, 1)});
    expect(week.upscores, 1);
    expect(week.biggest?.gain, 20000);
    expect(week.days.first, closeTo(5000, 1));
    // First week has nothing to compare against.
    expect(h.week(w.shift(-1)).gap, null);
    final span = h.span(w.shift(1));
    final sides = h.sides(span);
    expect(sides.map((s) => (s.id, s.weeks)), [
      ((1, PadSide.p1), 1),
      ((1, PadSide.p2), 1),
    ]);
    expect(h.lamp((1, PadSide.p1), w), ClearLamp.gfc);
    expect(h.lamp((1, PadSide.p1), w.shift(1)), null);
    expect(sideRead([-1000, -5000, -9000], [null, ClearLamp.gfc, null]),
        startsWith('Sliding for three weeks'));
  });

  testWidgets('weeks browse by arrow and bar, sides expand with their lamps',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: floorPopTheme(Brightness.dark),
        home: SessionTrendsView(
            now: DateTime(2026, 10, 28),
            sources: sources(plays, ratings: [
              PadRating(
                  sessionId: 's',
                  cabinet: cab,
                  side: PadSide.p1,
                  lamp: ClearLamp.pfc,
                  sessionAt: DateTime(2026, 10, 19, 17)),
            ]))));
    await tester.pumpAndSettle();
    expect(find.text('Oct 26 – Nov 1'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_right_rounded))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    expect(find.text('Oct 19–25'), findsOneWidget);
    expect(find.bySemanticsLabel('+5.0k vs your usual'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Oct 12–18')));
    await tester.pumpAndSettle();
    expect(find.text('2 weeks ago'), findsOneWidget);
    await tester.fling(find.byType(ListView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Oct 19–25'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('BY LEVEL'), 200);
    expect(find.byWidgetPredicate((w) => w is LevelNumber && w.level == 16),
        findsWidgets);
    await tester.scrollUntilVisible(find.text('Arcade · P1'), -200);
    await tester.tap(find.text('Arcade · P1'));
    await tester.pumpAndSettle();
    expect(find.byType(LampTag), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trend-mode')));
    await tester.pumpAndSettle();
    expect(find.text('No week before to compare'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}
