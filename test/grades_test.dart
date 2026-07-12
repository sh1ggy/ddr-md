import 'package:ddr_md/grades.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calcScore', () {
    test('all Marvelous hits the exact 1,000,000 cap, even when N ∤ 10^6', () {
      expect(calcScore(marvelous: 333, perfect: 0, great: 0, good: 0, miss: 0),
          1000000);
      expect(
          calcScore(
              marvelous: 300, perfect: 0, great: 0, good: 0, miss: 0, ok: 33),
          1000000);
    });

    test('uses the DDR A formula, not SuperNOVA2', () {
      // 100 notes -> SC = 10,000. One Great = 3/5*SC - 10 = 5,990
      // (SuperNOVA2 would give SC/2 - 10 = 4,990).
      expect(calcScore(marvelous: 99, perfect: 0, great: 1, good: 0, miss: 0),
          995990);
      // One Good = SC/5 - 10 = 1,990 (SuperNOVA2: 0).
      expect(calcScore(marvelous: 99, perfect: 0, great: 0, good: 1, miss: 0),
          991990);
      expect(calcScore(marvelous: 99, perfect: 1, great: 0, good: 0, miss: 0),
          999990);
      expect(calcScore(marvelous: 99, perfect: 0, great: 0, good: 0, miss: 1),
          990000);
    });

    test('result is a multiple of 10 and never negative', () {
      final s = calcScore(marvelous: 1, perfect: 1, great: 1, good: 1, miss: 3);
      expect(s % 10, 0);
      expect(calcScore(marvelous: 0, perfect: 0, great: 0, good: 100, miss: 0),
          199000);
      expect(calcScore(marvelous: 0, perfect: 0, great: 0, good: 0, miss: 50),
          0);
    });
  });

  group('gradeForScore', () {
    test('inclusive lower bounds', () {
      expect(gradeForScore(1000000), Grade.aaa);
      expect(gradeForScore(990000), Grade.aaa);
      expect(gradeForScore(989990), Grade.aaPlus);
      expect(gradeForScore(950000), Grade.aaPlus);
      expect(gradeForScore(900000), Grade.aa);
      expect(gradeForScore(890000), Grade.aaMinus);
      expect(gradeForScore(889990), Grade.aPlus);
      expect(gradeForScore(550000), Grade.dPlus);
      expect(gradeForScore(549990), Grade.d);
      expect(gradeForScore(0), Grade.d);
    });

    test('a fail is E regardless of score', () {
      expect(gradeForScore(995000, failed: true), Grade.e);
    });
  });

  test('calcExScore weights 3/2/1', () {
    expect(calcExScore(marvelous: 10, perfect: 5, great: 2, ok: 3), 51);
  });

  group('fullComboTier', () {
    test('tiers and their icons', () {
      expect(fullComboTier(marvelous: 5, perfect: 0, great: 0, good: 0, miss: 0),
          FullComboTier.mfc);
      expect(fullComboTier(marvelous: 5, perfect: 1, great: 0, good: 0, miss: 0),
          FullComboTier.pfc);
      expect(fullComboTier(marvelous: 5, perfect: 0, great: 1, good: 0, miss: 0),
          FullComboTier.gfc);
      expect(fullComboTier(marvelous: 5, perfect: 0, great: 0, good: 1, miss: 0),
          FullComboTier.fc);
      expect(fullComboTier(marvelous: 5, perfect: 0, great: 0, good: 0, miss: 1),
          FullComboTier.none);
      // An NG breaks every tier, even all-Marvelous steps.
      expect(
          fullComboTier(
              marvelous: 5, perfect: 0, great: 0, good: 0, miss: 0, ng: 1),
          FullComboTier.none);
    });
  });

  group('icons', () {
    test('grade art where it exists, null below B+ and for A-', () {
      expect(gradeIcon(Grade.aaa), 'assets/icons/rank_aaa.png');
      expect(gradeIcon(Grade.aaPlus), 'assets/icons/rank_aa_p.png');
      expect(gradeIcon(Grade.aa), 'assets/icons/rank_aa.png');
      expect(gradeIcon(Grade.aaMinus), 'assets/icons/rank_aa_m.png');
      expect(gradeIcon(Grade.aPlus), 'assets/icons/rank_a_p.png');
      expect(gradeIcon(Grade.a), 'assets/icons/rank_a.png');
      expect(gradeIcon(Grade.bPlus), 'assets/icons/rank_b_p.png');
      expect(gradeIcon(Grade.e), 'assets/icons/rank_e.png');
      expect(gradeIcon(Grade.aMinus), null);
      expect(gradeIcon(Grade.b), null);
      expect(gradeIcon(Grade.d), null);
    });

    test('full-combo lamps', () {
      expect(fullComboIcon(FullComboTier.mfc), 'assets/icons/cl_marv.png');
      expect(fullComboIcon(FullComboTier.pfc), 'assets/icons/cl_perf.png');
      expect(fullComboIcon(FullComboTier.gfc), 'assets/icons/cl_great.png');
      expect(fullComboIcon(FullComboTier.fc), 'assets/icons/cl_good.png');
      expect(fullComboIcon(FullComboTier.none), null);
    });

    test('flare accepts roman numerals, digits, EX and NONE', () {
      expect(flareIcon('IX'), 'assets/icons/flare_9.png');
      expect(flareIcon('i'), 'assets/icons/flare_1.png');
      expect(flareIcon('4'), 'assets/icons/flare_4.png');
      expect(flareIcon('EX'), 'assets/icons/flare_ex.png');
      expect(flareIcon('NONE'), 'assets/icons/icon_0.png');
      expect(flareIcon(''), 'assets/icons/icon_0.png');
      expect(flareIcon('garbage'), null);
    });

    test('flare correlates raw OCR readings', () {
      expect(flareIcon('FLARE IX'), 'assets/icons/flare_9.png');
      expect(flareIcon('FLARE EX'), 'assets/icons/flare_ex.png');
      // Common OCR confusions of I: the digit 1 and the letter l.
      expect(flareIcon('1X'), 'assets/icons/flare_9.png');
      expect(flareIcon('V1'), 'assets/icons/flare_6.png');
      expect(flareIcon('lll'), 'assets/icons/flare_3.png');
      expect(flareIcon(' vii '), 'assets/icons/flare_7.png');
    });
  });
}
