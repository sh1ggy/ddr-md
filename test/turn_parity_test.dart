import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// A TURN mod moves the arrows under the player's feet, so the footing must be
/// solved on the turned chart. These pin the two things that made the old
/// solve-once approach wrong, and the one hazard the fix introduces.
void main() {
  const mirror = [3, 2, 1, 0];

  List<StepNote> stream(List<int> cols) => [
        for (int i = 0; i < cols.length; i++)
          StepNote(
              beat: i.toDouble(),
              second: i * 0.5,
              col: cols[i],
              type: StepType.tap),
      ];

  List<StepNote> turned(List<StepNote> notes) => [
        for (final n in notes)
          StepNote(
              beat: n.beat,
              second: n.second,
              col: mirror[n.col],
              type: n.type),
      ];

  test('mirroring a one-sided crossover run changes the footing', () {
    // A run that crosses over on the LEFT side only. Mirrored, the crossovers
    // land on the right instead, so the feet that dance it must differ — that
    // difference is the whole reason the solve has to see the turn.
    final source = stream([0, 1, 0, 2, 0, 1, 0, 2]);
    final mirroredNotes = turned(source);
    final plain = FootAssigner.analyse(source, Modes.singles);
    final mirrored = FootAssigner.analyse(mirroredNotes, Modes.singles);

    final plainFeet = [for (final n in source) plain.feet[n]];
    expect(plainFeet.contains(null), isFalse, reason: 'every note takes a foot');

    // Same chart geometry reflected: the solve should not return the identical
    // foot sequence, because the crossovers now sit on the other side.
    final mirroredFeet = [for (final n in mirroredNotes) mirrored.feet[n]];
    expect(mirroredFeet, isNot(equals(plainFeet)));
  });

  test('a mirrored solve still assigns a foot to every note', () {
    // The scroller re-keys the solve back onto the original notes by position.
    // StepNote has no value equality, so if that re-keying were dropped the map
    // would miss every lookup and the foot guide would silently go blank rather
    // than fail loudly. Positions must line up one-for-one.
    final source = stream([0, 3, 1, 2, 0, 3, 2, 1]);
    final permuted = turned(source);
    expect(permuted.length, source.length);

    final analysis = FootAssigner.analyse(permuted, Modes.singles);
    final rekeyed = {
      for (int i = 0; i < source.length; i++)
        if (analysis.feet[permuted[i]] case final foot?) source[i]: foot,
    };
    expect(rekeyed.length, source.length);
  });
}
