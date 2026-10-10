/// Name: PatternModelTest
/// Description: Footwork counting rules on hand-footed rows.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

const _l = ParityFoot.left, _r = ParityFoot.right;

void main() {
  test('full crossover and three fast doublesteps on 8ths at 150', () {
    // L-D-L-D-R puts the left foot across the right foot's last panel after
    // starting on its own side. Three later same-foot moves change panels.
    final feet = [
      (0, _l), (1, _r), (0, _l), (1, _r), (3, _l), //
      (1, _l), (0, _l), (2, _r), (1, _r),
    ];
    final rows = [
      for (final (i, (col, foot)) in feet.indexed)
        FootedRow(i * 0.2, i * 0.5, {col: foot}),
    ];
    final out = countFootwork(rows, Modes.singles);
    expect(out.count(Pattern.crossover), 1);
    expect(out.fullCrossovers, 1);
    expect(out.count(Pattern.footswitch), 0);
    expect(out.count(Pattern.jack), 0);
    expect(out.count(Pattern.doublestep), 3);
  });
}
