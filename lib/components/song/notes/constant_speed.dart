/// Name: ConstantSpeed
/// Parent: SongPage and ChartScroller
/// Description: Convert a preferred read speed to a CONSTANT display window.
library;

import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:ddr_md/constants.dart' as constants;

/// The preview's 10 ms CONSTANT step that still meets [preferredReadSpeed].
/// The returned C value reflects the snapped window, which can read slightly
/// faster than the preference.
({int ms, int c}) constantForReadSpeed(int preferredReadSpeed) {
  final speed =
      preferredReadSpeed > 0 ? preferredReadSpeed : constants.chosenReadSpeed;
  const travel = ChartPainter.cabinetTravelArrows * 60 * 1000;
  final ms = ((travel / speed / 10).floor() * 10).clamp(100, 3000);
  return (ms: ms, c: (travel / ms).round());
}
