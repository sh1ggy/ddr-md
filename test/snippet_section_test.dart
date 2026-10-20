/// Name: Snippet section test
/// Parent: ChartScroller
/// Description: Picking a snippet with the selector button and scrub control.
library;

import 'dart:math';

import 'package:ddr_md/components/snippets/snippet_feed_page.dart';
import 'package:ddr_md/components/song/notes/chart_models.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await SpriteNoteskin.tryLoad();
  });
  testWidgets('trim selection opens with handles and minimal actions',
      (tester) async {
    final chart = ChartSteps(notes: [
      for (int b = 0; b < 8; b++)
        StepNote(
            beat: b.toDouble(),
            second: b * 0.5,
            col: b % 4,
            type: StepType.tap),
    ]);
    BeatRange? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ChartScroller(
            steps: chart,
            mode: Modes.singles,
            songLength: 10,
            chartBpm: 120,
            bpms: [Bpm(st: 0, ed: 10, val: 120)],
            section: picked,
            pickSection: true,
            showFootGuide: true,
            showFootTrails: true,
            onSectionChanged: (s) => setState(() => picked = s),
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.pump();
    expect(picked, (0.0, 4.0));
    expect(find.textContaining(RegExp(r'^START')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^END')), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<ChartPainter>()
        .first;
    expect(painter.section, (0.0, 2.0));
    expect(painter.feet.keys.every((n) => n.beat <= 4), isTrue);
    expect(
        painter.footPrev.entries
            .every((e) => e.key.beat <= 4 && e.value.beat <= 4),
        isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('selection band includes the final freeze tail', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ChartScroller(
      steps: ChartSteps(notes: [
        StepNote(beat: 160, second: 96, col: 0, type: StepType.tap),
        StepNote(
            beat: 168,
            second: 101.5,
            col: 2,
            type: StepType.hold,
            endBeat: 172,
            endSecond: 106.3),
      ]),
      mode: Modes.singles,
      songLength: 106.3,
      chartBpm: 100,
      section: (160, 168),
    ))));
    await tester.pump();
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<ChartPainter>()
        .first;
    expect(painter.section, (96.0, 101.5));
    expect(painter.sectionTail, 106.3);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('feed page plays only while active, header hidden',
      (tester) async {
    Widget page(bool active) => MaterialApp(
        home: Scaffold(
            body: ChartScroller(
                steps: ChartSteps(notes: [
                  for (int b = 0; b < 16; b++)
                    StepNote(
                        beat: b.toDouble(),
                        second: b * 0.5,
                        col: b % 4,
                        type: StepType.tap),
                ]),
                mode: Modes.singles,
                songLength: 10,
                chartBpm: 120,
                bpms: [Bpm(st: 0, ed: 10, val: 120)],
                section: (4.0, 8.0),
                feedActive: active,
                headerBuilder: (_, __) => const Text('HEADER'))));
    ChartPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<ChartPainter>()
        .first;
    double headerOpacity() => tester
        .widget<AnimatedOpacity>(find
            .ancestor(
                of: find.text('HEADER'), matching: find.byType(AnimatedOpacity))
            .first)
        .opacity;

    await tester.pumpWidget(page(false));
    await tester.pump();
    expect(painter().playing, isFalse);
    expect(headerOpacity(), 0);
    await tester.pumpWidget(page(true));
    await tester.pump();
    expect(painter().playing, isTrue);
    expect(headerOpacity(), 0);
    // Scrubbing stays inside the loop: a two-beat run-up from beat 4 (1 s) to
    // half a beat past beat 8 (4.25 s).
    await tester.dragFrom(const Offset(200, 100), const Offset(0, 3000));
    await tester.pump(const Duration(seconds: 1));
    expect(painter().playhead.value, closeTo(1.0, 1e-6));
    await tester.dragFrom(const Offset(200, 500), const Offset(0, -3000));
    await tester.pump(const Duration(seconds: 1));
    expect(painter().playhead.value, closeTo(4.25, 1e-6));
    await tester.pumpWidget(page(false));
    await tester.pump();
    expect(painter().playing, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  });
  test('shuffle skips recent snippets and alternates songs', () {
    final pool = [
      for (int i = 0; i < 6; i++)
        Snippet(
            createdAt: '',
            song: 'song${i % 3}',
            mode: Modes.singles,
            difficulty: 'hard',
            chartHash: '',
            startBeat: 0,
            endBeat: 4)
    ];
    final random = Random(1);
    final dealt = <Snippet>[];
    for (int i = 0; i < 300; i++) {
      dealt.add(dealSnippet(pool, dealt, random));
    }
    for (int i = 1; i < dealt.length; i++) {
      expect(dealt[i].song, isNot(dealt[i - 1].song));
      for (int back = 1; back <= 3 && back <= i; back++) {
        expect(dealt[i].id, isNot(dealt[i - back].id));
      }
    }
    expect(dealt.map((s) => s.id).toSet(), hasLength(6));
  });
}
