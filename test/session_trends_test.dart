import 'package:ddr_md/components/session/session_summary.dart';
import 'package:ddr_md/components/session/session_trends_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/session_trends.dart';
import 'package:ddr_md/models/visit_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TrendPlay play(String chart, int day, int? score,
    {double? variation,
    bool failed = false,
    int? venue = 1,
    int? cabinet = 1,
    PadSide? side = PadSide.p1,
    int level = 15,
    Modes mode = Modes.singles}) {
  final at = DateTime(2026, 10, day, 18);
  return TrendPlay(
      RecentPlay(
          konamiId: chart,
          title: chart,
          song: chart,
          mode: mode,
          difficulty: 'EXPERT',
          playedAt: at,
          score: score,
          failed: failed),
      timing: variation == null
          ? null
          : TimingPlay(
              playedAt: at.toIso8601String(),
              cabinetId: cabinet ?? 1,
              side: side ?? PadSide.p1,
              song: chart,
              mode: mode,
              difficulty: 'hard',
              songOffsetMs: 0,
              syncUsedMs: 0,
              averageMs: 0,
              variationMs: variation),
      venueId: venue,
      cabinetId: cabinet,
      side: side,
      visitKey: '$day',
      level: level);
}

void main() {
  final window =
      TrendWindow.containing(DateTime(2026, 10, 28), TrendRange.week);
  test(
      'calendar windows have stable boundaries, exact navigation and leap months',
      () {
    expect(window.start, DateTime(2026, 10, 26));
    expect(window.contains(window.start), true);
    expect(window.contains(window.end), false);
    expect(window.shift(-1).end, window.start);
    for (final d in [
      DateTime(2026, 1, 1),
      DateTime(2026, 10, 28),
      DateTime(2024, 2, 29)
    ]) {
      final fortnight = TrendWindow.containing(d, TrendRange.fortnight);
      expect(fortnight.start.weekday, DateTime.monday);
      expect(fortnight.days, 14);
      expect(fortnight.contains(d), true);
      expect(fortnight.shift(1).shift(-1).start, fortnight.start);
    }
    final feb = TrendWindow.containing(DateTime(2024, 2, 29), TrendRange.month);
    expect(feb.days, 29);
    expect(feb.shift(1).start, DateTime(2024, 3));
    expect(feb.shift(-2).start, DateTime(2023, 12));
  });

  test('comparison uses common charts equally despite play mix and new charts',
      () {
    final all = [
      play('easy', 20, 980000),
      play('hard', 20, 800000),
      for (var i = 0; i < 8; i++) play('easy', 27, 990000),
      play('hard', 27, 810000),
      play('new', 27, 1000000)
    ];
    final s =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.score);
    expect(s.comparison, 10000);
    expect(s.comparedCharts, 2);
    expect(s.samples[1].value, 10000);
    expect(s.samples[0].value, null);
    expect(s.goodSets, 1);
    expect(s.ratedSets, 1);
  });

  test(
      'timing improvement is positive with flat score and excludes missing timing',
      () {
    final all = [
      play('a', 20, 900000, variation: 25),
      play('a', 27, 900000, variation: 20),
      play('b', 27, 999000)
    ];
    final score =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.score);
    final timing =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.timing);
    expect(score.comparison, 0);
    expect(timing.comparison, closeTo(5, .001));
    expect(timing.samples[1].value, closeTo(20, .001));
    expect(timing.comparedCharts, 1);
  });

  test('all focus and location filters apply to history and current plays', () {
    final all = [
      play('a', 20, 900000),
      play('a', 27, 910000),
      play('a', 27, 990000, cabinet: 2, side: PadSide.p2),
      play('b', 27, 700000, level: 16),
      play('a', 27, 500000, venue: null, cabinet: null, side: null),
      play('a', 27, 600000, mode: Modes.doubles)
    ];
    final s = summarizeTrends(
        all,
        window,
        TrendFilter(
            mode: Modes.singles,
            level: 15,
            chart: all.first.chart,
            venueId: 1,
            cabinetId: 1,
            side: PadSide.p1),
        TrendMetric.score);
    expect(s.current.length, 1);
    expect(s.comparison, 10000);
  });

  test(
      'fails, missing scores and unseen charts do not become zero or good sets',
      () {
    final all = [
      play('a', 20, 900000),
      play('a', 27, 100000, failed: true),
      play('a', 28, null),
      play('new', 28, 1000000)
    ];
    final s =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.score);
    expect(s.comparison, null);
    expect(s.ratedSets, 0);
    expect(s.goodSets, 0);
    expect(s.samples.every((s) => s.value == null), true);
  });

  test('the baseline is frozen before the window and excludes future plays',
      () {
    final all = [
      play('a', 10, 880000),
      play('a', 20, 900000),
      play('a', 27, 910000),
      play('a', 28, 930000),
      play('a', 36, 1000000)
    ];
    final s =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.score);
    expect(s.samples[1].value, 20000);
    expect(s.samples[2].value, 40000);
    expect(s.comparison, 20000);
  });

  test(
      'first month shows repeated charts from their first day without inventing previous history',
      () {
    final all = [
      play('a', 5, 880000),
      play('a', 5, 900000),
      play('a', 28, 910000),
      play('new', 28, 990000)
    ];
    final s = summarizeTrends(
        all,
        TrendWindow.containing(DateTime(2026, 10, 28), TrendRange.month),
        const TrendFilter(),
        TrendMetric.score);
    expect(s.samples[4].value, 0);
    expect(s.samples[27].value, 20000);
    expect(s.comparison, null);
    expect(s.ratedSets, 0);
    expect(s.samples[0].value, null);
  });

  test(
      'reconciliation counts timing-only and synced plays once, with cab and side',
      () {
    final p = play('a', 27, 900000, variation: 22);
    final timingOnly = play('b', 27, null, variation: 19).timing!;
    final visit = Visit(
        session: PlaySession('s', const Venue(1, 'Arcade'),
            DateTime(2026, 10, 27, 17), DateTime(2026, 10, 27, 20)),
        plays: [p.play],
        start: DateTime(2026, 10, 27),
        end: DateTime(2026, 10, 28));
    final result = trendPlays([
      visit
    ], {
      's': [p.timing!, timingOnly]
    }, {}, ScoreModel([p.play], [], (_, __, ___) => 15));
    expect(result.length, 2);
    expect(result.where((p) => p.play.score != null).length, 1);
    expect(
        result.every((p) =>
            p.timing != null && p.cabinetId == 1 && p.side == PadSide.p1),
        true);
    expect(result.map((p) => p.chart).toSet().length, 2);
  });

  testWidgets('phone layout switches ranges, timing, periods and chart focus',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: floorPopTheme(Brightness.dark),
        home: Scaffold(
            body: SessionTrendsView(now: DateTime(2026, 10, 28), plays: [
          play('A long chart title to check wrapping on a small phone', 20,
              900000,
              variation: 25),
          play('A long chart title to check wrapping on a small phone', 27,
              910000,
              variation: 20),
        ]))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    expect(find.text('10000 pts better'), findsOneWidget);
    await tester.tap(find.text('Fortnight'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timing variation'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous period'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('All charts'), 250);
    await tester.tap(find.text('All charts'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'long chart');
    await tester.pumpAndSettle();
    await tester.tap(
        find.text('A long chart title to check wrapping on a small phone'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    await tester.scrollUntilVisible(find.text('Reset filters'), 200);
    expect(find.text('Reset filters'), findsOneWidget);
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });
}
