/// Name: Snippet section test
/// Parent: ChartScroller
/// Description: Picking a snippet's section by tapping its first and last rows.
library;

import 'package:ddr_md/components/song/notes/chart_models.dart';
import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping the last row then the first picks the section between',
      (tester) async {
    final chart = ChartSteps(notes: [
      for (int b = 0; b < 8; b++)
        StepNote(beat: b.toDouble(), second: b * 0.5, col: b % 4,
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
            onSectionChanged: (s) => setState(() => picked = s),
          ),
        ),
      ),
    ));
    await tester.pump();

    final field = tester.getRect(find.byType(ChartScroller));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<ChartPainter>()
        .first;
    // The y each row is drawn at, found through the painter's own hit test.
    double yOf(double beat) {
      for (double y = 0; y < field.height; y++) {
        if (painter.rowAt(y, field.size)?.beat == beat) return y;
      }
      fail('row $beat not on screen');
    }

    final first = yOf(0), last = yOf(1);
    await tester.tapAt(Offset(field.center.dx, last));
    await tester.pump(kDoubleTapTimeout);
    expect(picked, isNull);
    await tester.tapAt(Offset(field.center.dx, first));
    await tester.pump(kDoubleTapTimeout);
    expect(picked, (0.0, 1.0));
  });
}
