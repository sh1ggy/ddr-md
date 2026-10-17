import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flash grows over the first half, then fades at full size', () {
    // Scales are multiples of the arrow.
    expect(noteFlashCurve(0).$1, closeTo(noteFlashStartScale, 1e-9));
    expect(noteFlashCurve(0).$2, 1.0);
    expect(noteFlashCurve(0.5).$1, closeTo(noteFlashPeakScale, 1e-9));
    expect(noteFlashCurve(0.5).$2, closeTo(1.0, 1e-9));
    // peak is reached at the halfway point, then held — no growth while fading
    expect(noteFlashCurve(0.75).$1, closeTo(noteFlashPeakScale, 1e-9));
    expect(noteFlashCurve(0.75).$2, closeTo(0.5, 1e-9));
    expect(noteFlashCurve(1).$2, closeTo(0.0, 1e-9));
    // clamped outside 0..1
    expect(noteFlashCurve(1.4).$2, 0.0);
    expect(noteFlashCurve(-1).$1, closeTo(noteFlashStartScale, 1e-9));
  });

  test('receptor press is 88 of 96 px, back to full in four 20 ms steps', () {
    expect(receptorRecoilCurve(0), closeTo(88 / 96, 1e-9));
    expect(receptorRecoilCurve(0.25), closeTo(90 / 96, 1e-9));
    expect(receptorRecoilCurve(0.99), closeTo(94 / 96, 1e-9));
    expect(receptorRecoilCurve(1), 1.0);
  });
}
