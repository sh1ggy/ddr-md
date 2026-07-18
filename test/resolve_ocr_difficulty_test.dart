import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A typical full singles spread: BEGINNER 5, BASIC 8, DIFFICULT 12,
  // EXPERT 16, CHALLENGE 18.
  final full = Difficulty(
      beginner: 5, easy: 8, medium: 12, hard: 16, challenge: 18);

  group('resolveOcrDifficulty', () {
    test('exact in-game names resolve to themselves', () {
      expect(resolveOcrDifficulty('BEGINNER', full), 'BEGINNER');
      expect(resolveOcrDifficulty('BASIC', full), 'BASIC');
      expect(resolveOcrDifficulty('DIFFICULT', full), 'DIFFICULT');
      expect(resolveOcrDifficulty('EXPERT', full), 'EXPERT');
      expect(resolveOcrDifficulty('CHALLENGE', full), 'CHALLENGE');
    });

    test('cropped name with a level resolves via both signals', () {
      expect(resolveOcrDifficulty('ert 16', full), 'EXPERT');
      expect(resolveOcrDifficulty('XPERT 16', full), 'EXPERT');
      expect(resolveOcrDifficulty('ifficult 12', full), 'DIFFICULT');
    });

    test('near-exact name beats a level pointing at another chart', () {
      // The word is much harder to misread than the small level digits.
      expect(resolveOcrDifficulty('EXPER 12', full), 'EXPERT');
    });

    test('a level matching exactly one chart resolves on its own', () {
      expect(resolveOcrDifficulty('16', full), 'EXPERT');
      expect(resolveOcrDifficulty('ert 12', full), 'DIFFICULT');
    });

    test('a shared level is tie-broken by the name', () {
      final shared = Difficulty(medium: 12, hard: 14, challenge: 14);
      expect(resolveOcrDifficulty('ert 14', shared), 'EXPERT');
      expect(resolveOcrDifficulty('lenge 14', shared), 'CHALLENGE');
      // Level alone can't pick between the two.
      expect(resolveOcrDifficulty('14', shared), null);
    });

    test('never resolves to a chart the song does not have', () {
      final noExpert = Difficulty(beginner: 5, easy: 8, medium: 12);
      expect(resolveOcrDifficulty('EXPERT 16', noExpert), isNot('EXPERT'));
    });

    test('garbage and empty readings resolve to null', () {
      expect(resolveOcrDifficulty('', full), null);
      expect(resolveOcrDifficulty('qzw 99', full), null);
      expect(resolveOcrDifficulty('EXPERT', Difficulty()), null);
    });
  });

  group('resolveOcrDifficulty note-count fallback', () {
    // Step counts for the same spread of charts.
    final counts = Difficulty(
        beginner: 80, easy: 150, medium: 280, hard: 420, challenge: 560);

    test('an unusable reading resolves via the judged step count', () {
      expect(
          resolveOcrDifficulty('', full, notecounts: counts, totalNotes: 420),
          'EXPERT');
      expect(
          resolveOcrDifficulty('qzw', full, notecounts: counts, totalNotes: 280),
          'DIFFICULT');
    });

    test('tolerance is inclusive at ±5 and no further', () {
      expect(
          resolveOcrDifficulty('', full, notecounts: counts, totalNotes: 425),
          'EXPERT');
      expect(
          resolveOcrDifficulty('', full, notecounts: counts, totalNotes: 415),
          'EXPERT');
      expect(
          resolveOcrDifficulty('', full, notecounts: counts, totalNotes: 426),
          null);
    });

    test('a total near several charts stays unresolved', () {
      final close = Difficulty(hard: 420, challenge: 424);
      expect(
          resolveOcrDifficulty('',
              Difficulty(hard: 16, challenge: 18),
              notecounts: close, totalNotes: 422),
          null);
    });

    test('note count breaks a shared-level tie when the name cannot', () {
      final shared = Difficulty(medium: 12, hard: 14, challenge: 14);
      final sharedCounts = Difficulty(medium: 280, hard: 400, challenge: 500);
      expect(
          resolveOcrDifficulty('14', shared,
              notecounts: sharedCounts, totalNotes: 500),
          'CHALLENGE');
    });

    test('name and level evidence still outrank the note count', () {
      // Note count points at CHALLENGE, but the near-exact name wins…
      expect(
          resolveOcrDifficulty('EXPERT', full,
              notecounts: counts, totalNotes: 560),
          'EXPERT');
      // …and so does a unique level match.
      expect(
          resolveOcrDifficulty('12', full, notecounts: counts, totalNotes: 560),
          'DIFFICULT');
    });
  });
}
