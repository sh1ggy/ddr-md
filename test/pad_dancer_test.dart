import 'dart:math' as math;

import 'package:ddr_md/components/song/notes/dancing_feet.dart';
import 'package:ddr_md/components/song/notes/pad_dancer.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MINIMAL lands inside the panels and keeps the shoulders still', () {
    const l = 0, d = 1, u = 2, r = 3;
    // Staircases, both crossovers, a jack and a jump, at 16ths of 150 BPM.
    final cols = [l, d, u, r, u, d, l, d, r, d, l, u, r, u, l, l, d, r];
    final notes = [
      for (int i = 0; i < cols.length; i++)
        StepNote(
            beat: i / 4, second: i * 0.1, col: cols[i], type: StepType.tap),
      const StepNote(beat: 5, second: 2.0, col: l, type: StepType.tap),
      const StepNote(beat: 5, second: 2.0, col: r, type: StepType.tap),
    ];
    final stances = analyseParity(notes, Modes.singles).stances;
    final times = [for (var t = 0.0; t < 2.4; t += 1 / 60) t];

    double sway(DancerForm form) {
      final s = padDancerTrace(stances, notes, 4, form, times: times).shoulders;
      final xs = [for (final p in s) p.$1], zs = [for (final p in s) p.$3];
      return math.max(xs.reduce(math.max) - xs.reduce(math.min),
          zs.reduce(math.max) - zs.reduce(math.min));
    }

    for (final (col, dx, dz)
        in padDancerTrace(stances, notes, 4, DancerForm.minimal).landings) {
      final inward = switch (col) { l => dx, r => -dx, d => dz, _ => -dz };
      expect(inward, greaterThan(0), reason: 'column $col at ($dx, $dz)');
      expect(math.max(dx.abs(), dz.abs()), lessThan(0.5));
    }
    expect(sway(DancerForm.minimal), lessThan(0.05));
    expect(sway(DancerForm.minimal), lessThan(sway(DancerForm.standard) / 3));
  });
}
