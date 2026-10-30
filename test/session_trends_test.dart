import 'package:ddr_md/components/session/session_summary.dart';
import 'package:ddr_md/components/session/session_trends_page.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
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
    int? level = 15,
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

  test('comparison balances shared levels despite changing chart and play mix',
      () {
    final all = [
      play('earlier-easy', 20, 980000, level: 14),
      play('earlier-hard', 20, 800000, level: 17),
      for (var i = 0; i < 8; i++) play('new-easy', 27, 990000, level: 14),
      play('new-hard', 27, 810000, level: 17),
      play('new-level', 27, 1000000, level: 18)
    ];
    final s =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.score);
    expect(s.comparison, 10000);
    expect(s.levels.map((l) => l.label), ['SP 14', 'SP 17']);
    expect(s.average, 973000);
    expect(s.observations, 10);
    expect(s.samples[1].value, 973000);
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
      play('b', 27, 999000, level: 17)
    ];
    final score =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.score);
    final timing =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.timing);
    expect(score.comparison, 0);
    expect(timing.comparison, closeTo(5, .001));
    expect(timing.samples[1].value, closeTo(20, .001));
    expect(timing.levels.length, 1);
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

  test('fails and unknown levels stay out of relative comparisons', () {
    final all = [
      play('a', 20, 900000),
      play('a', 27, 100000, failed: true),
      play('a', 28, null),
      play('new', 28, 1000000, level: null)
    ];
    final s =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.score);
    expect(s.comparison, null);
    expect(s.ratedSets, 0);
    expect(s.goodSets, 0);
    expect(s.samples[1].value, null);
    expect(s.samples[2].value, 1000000);
    expect(s.observations, 1);
  });

  test('daily averages and comparisons exclude plays beyond the period', () {
    final all = [
      play('a', 10, 880000),
      play('a', 20, 900000),
      play('a', 27, 910000),
      play('a', 28, 930000),
      play('a', 36, 1000000)
    ];
    final s =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.score);
    expect(s.samples[1].value, 910000);
    expect(s.samples[2].value, 930000);
    expect(s.comparison, 20000);
  });

  test('first month shows real scores without inventing previous history', () {
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
    expect(s.samples[4].value, 890000);
    expect(s.samples[27].value, 950000);
    expect(s.comparison, null);
    expect(s.ratedSets, 0);
    expect(s.samples[0].value, null);
  });

  test('different songs at the same level compare, without mixing SP and DP',
      () {
    final all = [
      play('old-sp', 20, 900000),
      play('new-sp', 27, 910000),
      play('old-dp', 20, 700000, mode: Modes.doubles),
      play('new-dp', 27, 720000, mode: Modes.doubles),
      play('new-16', 27, 999000, level: 16)
    ];
    final s =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.score);
    expect(s.levels.map((l) => l.label), ['SP 15', 'DP 15']);
    expect(s.comparison, 15000);
    expect(s.comparedPrevious, 800000);
    expect(s.comparedCurrent, 815000);
    expect(s.goodSets, 1);
  });

  test('single day and sparse data keep real averages separate from the change',
      () {
    final all = [
      play('old-a', 20, 950000),
      play('old-b', 20, 970000, level: 16),
      play('new-a', 27, 926485),
      play('new-b', 27, 946485, level: 16)
    ];
    final s =
        summarizeTrends(all, window, const TrendFilter(), TrendMetric.score);
    expect(s.average, 936485);
    expect(s.comparison, -23515);
    expect(s.samples[1].value, 936485);
    expect(s.samples.where((s) => s.value != null).length, 1);
    expect(s.levels.length, 2);
  });

  test('all-negative chart bounds include zero before choosing a tick interval',
      () {
    final axis = TrendAxis.forValues([-10517.0],
        minimumPadding: 1000, includeZero: true);
    expect(axis.min, lessThanOrEqualTo(-10517));
    expect(axis.max, 0);
    expect(axis.step, greaterThanOrEqualTo(2000));
    expect((axis.max - axis.min) / axis.step, lessThanOrEqualTo(6));
    for (final values in [
      [0.0],
      [1000000.0],
      [936485.0],
      [0.01, 0.02],
      [-23515.0, -100.0]
    ]) {
      final axis = TrendAxis.forValues(values);
      expect(axis.max, greaterThan(axis.min));
      expect(axis.step.isFinite, true);
      expect((axis.max - axis.min) / axis.step, lessThanOrEqualTo(6));
    }
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

  testWidgets('arrows browse periods and swiping leaves the period unchanged',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: floorPopTheme(Brightness.dark),
        home: Scaffold(
            body: SessionTrendsView(now: DateTime(2026, 10, 28), plays: [
          play('old', 20, 950000),
          play('new', 27, 926485),
        ]))));
    await tester.pumpAndSettle();
    final plot = find.byKey(const ValueKey('trend-plot'));
    final previous =
        find.widgetWithIcon(IconButton, Icons.chevron_left_rounded);
    final next = find.widgetWithIcon(IconButton, Icons.chevron_right_rounded);
    expect(find.text('Oct 26 – Nov 1'), findsOneWidget);
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    expect(tester.getSize(previous).width, greaterThanOrEqualTo(48));
    await tester.drag(plot, const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(find.text('Oct 26 – Nov 1'), findsOneWidget);
    await tester.drag(plot, const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(find.text('Oct 26 – Nov 1'), findsOneWidget);
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('Oct 19–25'), findsOneWidget);
    expect(tester.widget<IconButton>(next).onPressed, isNotNull);
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('Oct 12–18'), findsOneWidget);
    // Browsing also works when the period has no plays.
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('Oct 5–11'), findsOneWidget);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Oct 12–18'), findsOneWidget);
    await tester.tap(find.text('Back to this week'));
    await tester.pumpAndSettle();
    expect(find.text('Oct 26 – Nov 1'), findsOneWidget);
    await tester.tap(find.text('Fortnight'));
    await tester.pumpAndSettle();
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('Oct 5–18'), findsOneWidget);
    await tester.tap(find.text('Back to this fortnight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.text('October'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('September'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('Monthly view'), findsNothing);
    expect(tester.takeException(), null);
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
    expect(find.bySemanticsLabel('Average score: 910,000'), findsOneWidget);
    expect(find.text('+10,000 pts vs previous week'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trend-day-1')));
    await tester.pumpAndSettle();
    expect(find.text('DAY DETAIL'), findsOneWidget);
    await tester.tap(find.text('Period summary'));
    await tester.pumpAndSettle();
    expect(find.text('AVERAGE'), findsOneWidget);
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
    expect(find.text('Back to this week'), findsOneWidget);
    await tester.tap(find.text('Back to this week'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trend-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All charts'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'long chart');
    await tester.pumpAndSettle();
    await tester.tap(
        find.text('A long chart title to check wrapping on a small phone'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Filters (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trend-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('All plays'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('filter edits are applied together and dismissal discards edits',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: floorPopTheme(Brightness.light),
      home: Scaffold(
          body: SessionTrendsView(now: DateTime(2026, 10, 28), plays: [
        play('single', 27, 900000),
        play('double', 27, 800000, mode: Modes.doubles),
      ])),
    ));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Average score: 850,000'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trend-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SP'));
    await tester.pumpAndSettle();
    // Back dismisses the sheet, preserving the applied filter.
    Navigator.of(tester.element(find.text('Apply filters'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('All plays'), findsOneWidget);
    expect(find.bySemanticsLabel('Average score: 850,000'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trend-filters')));
    await tester.pumpAndSettle();
    expect(find.text('All modes'), findsOneWidget);
    final modeTarget = find
        .ancestor(of: find.text('DP'), matching: find.byType(InkWell))
        .first;
    final modeRect = tester.getRect(modeTarget);
    expect(modeRect.height, 48);
    await tester.tapAt(modeRect.topRight + const Offset(-3, 3));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Filters (1)'), findsOneWidget);
    expect(find.bySemanticsLabel('Average score: 800,000'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous period'));
    await tester.pumpAndSettle();
    expect(find.text('Filters (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tracked chart owns its level and clearing restores all levels',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: floorPopTheme(Brightness.dark),
      home: Scaffold(
          body: SessionTrendsView(
        now: DateTime(2026, 10, 28),
        plays: [
          play('First chart', 27, 900000, level: 15),
          play('Second chart', 27, 800000, level: 16),
        ],
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trend-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    // Level choices use the same numerals as the chart results.
    expect(find.byWidgetPredicate((w) => w is LevelNumber && w.level == 15),
        findsWidgets);
    await tester.tap(
        find.byWidgetPredicate((w) => w is LevelNumber && w.level == 15).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All charts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First chart'));
    await tester.pumpAndSettle();
    expect(find.text('Set by selected chart'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.text('Level'),
            matching: find.byType(DropdownButtonFormField<int>)),
        findsNothing);
    expect(find.byWidgetPredicate((w) => w is LevelNumber && w.level == 15),
        findsOneWidget);

    // The chart's automatic level must not restrict the next chart choice.
    await tester.tap(find.text('First chart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second chart'));
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is LevelNumber && w.level == 16),
        findsOneWidget);
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Filters (1)'), findsOneWidget);
    expect(find.bySemanticsLabel('Average score: 800,000'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('trend-filters')));
    await tester.pumpAndSettle();
    expect(find.text('Set by selected chart'), findsOneWidget);
    await tester.tap(find.text('Second chart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All charts'));
    await tester.pumpAndSettle();
    expect(find.text('Set by selected chart'), findsNothing);
    expect(find.text('All levels'), findsOneWidget);
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('All plays'), findsOneWidget);
    expect(find.bySemanticsLabel('Average score: 850,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date header handles a year boundary on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: floorPopTheme(Brightness.dark),
      home: Scaffold(
          body: SessionTrendsView(
        now: DateTime(2027, 1, 1),
        plays: const [],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Dec 28 – Jan 3'), findsOneWidget);
    expect(find.text('This week · 2026–2027'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trend-filters')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Both sides'), 150,
        scrollable: find.byType(Scrollable).last);
    final sideTarget = find
        .ancestor(of: find.text('1P'), matching: find.byType(InkWell))
        .first;
    final sideRect = tester.getRect(sideTarget);
    expect(sideRect.height, 48);
    await tester.tapAt(sideRect.bottomLeft + const Offset(3, -3));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('Filters (1)'), findsOneWidget);
  });
}
