import 'package:ddr_md/models/your_tiers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rungs match the calculated tier and the circle median lands on one',
      () {
    expect(rungsOf(14).length, 20);
    expect(rungsOf(19), [90, 80, 70, 60, 50, 40, 30, 20, 10, 0]);
    expect(onRung(14, 97), 95);
    expect(onRung(19, 95), 90);
    expect(onRung(14, 72), 70);
    final now = DateTime(2026);
    TierPlacement at(int h) => (level: 14, hundredths: h, placedAt: now);
    YourTiers.setCircle({
      'a': {('MAX 300', 'EXPERT'): at(60)},
      'b': {('MAX 300', 'EXPERT'): at(75)},
      'c': {('MAX 300', 'EXPERT'): (level: 15, hundredths: 0, placedAt: now)},
    });
    // Two at level 14 (the third is from when it was 15): between them,
    // rounded down onto a rung.
    expect(YourTiers.circleMedian('MAX 300', 'EXPERT', 14), 65);
    expect(YourTiers.circleMedian('MAX 300', 'CHALLENGE', 14), isNull);
  });
}
