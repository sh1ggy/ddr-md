/// Name: Snippet section test
/// Parent: ChartScroller
/// Description: Picking a snippet with the selector button and scrub control.
library;

import 'package:ddr_md/components/song/notes/chart_models.dart';
import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(painter.showSelector, isFalse);
    expect(painter.feet.keys.every((n) => n.beat <= 4), isTrue);
    expect(painter.footPrev.entries.every((e) =>
        e.key.beat <= 4 && e.value.beat <= 4), isTrue);
    expect(tester.takeException(), isNull);
  });
}
