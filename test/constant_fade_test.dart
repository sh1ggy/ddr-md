/// Name: ConstantFadeTest
/// Description: CONSTANT fades an arrow in over a fixed 200ms centred on the
/// display time, independent of how long the display time is.
library;

import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fade runs from display time +100ms to -100ms', () {
    for (final ms in [300.0, 1000.0, 2500.0]) {
      final s = ms / 1000;
      expect(ChartPainter.constantAlpha(ms, s + 0.15), 0);
      expect(ChartPainter.constantAlpha(ms, s + 0.1), 0);
      expect(ChartPainter.constantAlpha(ms, s), closeTo(0.5, 1e-9));
      expect(ChartPainter.constantAlpha(ms, s - 0.1), 1);
      expect(ChartPainter.constantAlpha(ms, 0), 1);
    }
  });
}
