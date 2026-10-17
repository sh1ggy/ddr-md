/// Name: DdrPaletteTest
/// Description: The cabinet's arrow palettes: band fill through the beat, the
/// pulse, the receptor's beat flash and the freeze rows.
library;

import 'package:ddr_md/components/song/notes/ddr_atlas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tap, receptor and freeze palettes', () {
    // The pulse is palest at its zero crossings and fully saturated a beat on.
    expect(ddrColour(DdrPalette.quarter, 5, 0), 0xfff8c0c0);
    expect(ddrColour(DdrPalette.quarter, 5, 1024), 0xfff80000);
    expect(ddrColour(DdrPalette.sixteenth, 5, 1024), 0xfff8f828);
    // Bands 2–4 fill in one 16th at a time and are all lit on the beat.
    expect(ddrColour(DdrPalette.eighth, 2, 256) >>> 24, 0);
    expect(ddrColour(DdrPalette.eighth, 2, 512), 0xff8080f8);
    expect(ddrColour(DdrPalette.eighth, 4, 512) >>> 24, 0);
    expect(ddrColour(DdrPalette.eighth, 4, 0), 0xff8080f8);
    // Receptors flash for the first 16th of each beat.
    expect(ddrColour(DdrPalette.receptor, 5, 0), 0xff808080);
    expect(ddrColour(DdrPalette.receptor, 5, 256), 0xff202020);
    expect(ddrBand(0x77), 0);
    expect([for (final t in [-0.1, 0.0, 1 / 60, 2 / 60, 3 / 60, 1.0]) ddrFreezeRow(t)],
        [1, 1, 2, 3, 4, 4]);
  });
}
