import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/grades.dart' show flareIcon;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only resolved flare ranks have badge art', () {
    for (final reading in [
      '',
      'NONE',
      '0',
      'FLARE NONE',
      'FLARE 0',
      'garbage'
    ]) {
      expect(flareIcon(reading), isNull, reason: reading);
    }
    expect(flareIcon('FLARE 1X'), 'assets/icons/flare_9.png');
    expect(flareIcon('EX'), 'assets/icons/flare_ex.png');
  });

  group('resolveOcrFlare', () {
    test('canonical ranks resolve to themselves', () {
      for (final rank in kFlareRanks) {
        expect(resolveOcrFlare(rank), rank);
      }
    });

    test('accepts digits, lowercase and a FLARE prefix', () {
      expect(resolveOcrFlare('4'), 'IV');
      expect(resolveOcrFlare('9'), 'IX');
      expect(resolveOcrFlare('vii'), 'VII');
      expect(resolveOcrFlare('ex'), 'EX');
      expect(resolveOcrFlare('FLARE IX'), 'IX');
      expect(resolveOcrFlare('FLARE EX'), 'EX');
    });

    test('normalises common glyph confusions', () {
      expect(resolveOcrFlare('1X'), 'IX');
      expect(resolveOcrFlare('V1'), 'VI');
      expect(resolveOcrFlare('lll'), 'III');
      expect(resolveOcrFlare('U1'), 'VI');
      expect(resolveOcrFlare('YII'), 'VII');
      expect(resolveOcrFlare('EK'), 'EX');
      expect(resolveOcrFlare('IK'), 'IX');
    });

    test('strips a misread FLARE prefix', () {
      expect(resolveOcrFlare('FIARE IX'), 'IX');
      expect(resolveOcrFlare('FLARF VII'), 'VII');
    });

    test('one edit from a unique rank still resolves', () {
      expect(resolveOcrFlare('VIIII'), 'VIII');
      expect(resolveOcrFlare('EEX'), 'EX');
    });

    test('ambiguous readings stay unresolved', () {
      // One edit from both IX and EX.
      expect(resolveOcrFlare('X'), null);
      // One edit from both VI and VII.
      expect(resolveOcrFlare('VVI'), null);
      // One edit from both III (stray I) and VIII (V read as I).
      expect(resolveOcrFlare('IIII'), null);
    });

    test('blank, NONE and unreadable values resolve to null', () {
      expect(resolveOcrFlare(''), null);
      expect(resolveOcrFlare('NONE'), null);
      expect(resolveOcrFlare('0'), null);
      expect(resolveOcrFlare('garbage'), null);
      expect(resolveOcrFlare('10'), null);
    });
  });
}
