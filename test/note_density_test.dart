/// Name: NoteDensityTest
/// Description: Steps are binned by time and colour; jumps and mines don't inflate them.
library;

import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/models/note_density.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

StepNote _note(double beat, double second, {int col = 0, StepType? type}) =>
    StepNote(beat: beat, second: second, col: col, type: type ?? StepType.tap);

void main() {
  test('counts a jump once, skips mines and splits by colour', () {
    QuantColors.arcadeMode = false;
    final d = NoteDensity.of([
      _note(0, 0),
      _note(0, 0, col: 3),
      _note(0.5, 0.25),
      _note(0.75, 0.375, type: StepType.mine),
      _note(4, 2),
    ], 4, binCount: 2);
    expect(d.bins[0][kDensityColours.indexOf(QuantColors.quarter)], 1);
    expect(d.bins[0][kDensityColours.indexOf(QuantColors.eighth)], 1);
    expect(d.bins[1][kDensityColours.indexOf(QuantColors.quarter)], 1);
    expect(d.rate(0), 1);
  });
}
