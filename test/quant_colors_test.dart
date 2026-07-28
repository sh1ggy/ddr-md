/// Name: QuantColorsTest
/// Description: Arcade-style quantisation colouring — the cabinet's coarser
/// palette collapses everything below 16ths to green.
library;

import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => QuantColors.arcadeMode = false);

  test('arcade mode keeps 4th/8th/16th and greens the rest', () {
    QuantColors.arcadeMode = false;
    expect(QuantColors.forBeat(1 / 3), QuantColors.twelfth);
    expect(QuantColors.forBeat(1 / 6), QuantColors.twentyfourth);
    expect(QuantColors.forBeat(0.125), QuantColors.thirtysecond);

    QuantColors.arcadeMode = true;
    expect(QuantColors.forBeat(0.0), QuantColors.quarter);
    expect(QuantColors.forBeat(0.5), QuantColors.eighth);
    expect(QuantColors.forBeat(0.25), QuantColors.sixteenth);
    expect(QuantColors.forBeat(1 / 3), QuantColors.other);
    expect(QuantColors.forBeat(1 / 6), QuantColors.other);
    expect(QuantColors.forBeat(0.125), QuantColors.other);
  });
}
