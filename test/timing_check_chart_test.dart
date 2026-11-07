/// Name: TimingCheckChartTest
/// Parent: TimingCheckChart
/// Description: Checks that the shared painter advances its beat animation
/// while the visual cue follows the round's assigned crossing time.
library;

import 'package:ddr_md/components/settings/timing_check/timing_check_chart.dart';
import 'package:ddr_md/components/settings/timing_check/timing_check_protocol.dart';
import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the preview beat follows the shifted visual crossing',
      (tester) async {
    const shiftMs = 20;
    final playhead = ValueNotifier((firstBeatMs + shiftMs) / 1000);
    addTearDown(playhead.dispose);
    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 375,
        height: 440,
        child: TimingCheckChart(
          playhead: playhead,
          crossingMs: shiftMs,
          constantMs: 600,
        ),
      ),
    ));

    final painter = tester
        .widget<CustomPaint>(find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is ChartPainter))
        .painter! as ChartPainter;
    expect(painter.playing, isTrue);
    expect(painter.showHitEffects, isFalse);
    expect(painter.second, closeTo(firstBeatMs / 1000, 1e-9));
    final first = painter.timing.beatAt(painter.second);

    playhead.value += beatMs / 1000;
    await tester.pump();
    expect(painter.timing.beatAt(painter.second), closeTo(first + 1, 1e-9));
    expect(tester.takeException(), isNull);
  });
}
