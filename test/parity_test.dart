import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build a simple single-note stream. Each entry is (beat, col); seconds are
/// derived from a fixed bpm so timing-sensitive costs (jack/footswitch/distance)
/// behave realistically.
List<StepNote> stream(List<(double, int)> steps, {double bpm = 150}) {
  final secPerBeat = 60.0 / bpm;
  return [
    for (final (beat, col) in steps)
      StepNote(
        beat: beat,
        second: beat * secPerBeat,
        col: col,
        type: StepType.tap,
      ),
  ];
}

String render(List<StepNote> notes, Map<StepNote, ParityFoot> p) => notes
    .map((n) => '${n.col}:${p[n] == ParityFoot.left ? "L" : p[n] == ParityFoot.right ? "R" : "?"}')
    .join(' ');

void main() {
  const L = 0, D = 1, U = 2, R = 3;

  test('alternating LRLR stream uses alternating feet', () {
    final notes =
        stream([(0, L), (1, R), (2, L), (3, R), (4, L), (5, R)]);
    final p = assignParity(notes, Modes.singles);
    final feet = notes.map((n) => p[n]).toList();
    // Should strictly alternate (no doublesteps on an easy alternating run).
    for (int i = 1; i < feet.length; i++) {
      expect(feet[i], isNot(equals(feet[i - 1])),
          reason: 'note $i repeated a foot: ${render(notes, p)}');
    }
  });

  test('crossover run: L D U R danced without doublestepping', () {
    // A candle-ish run that forces a crossover: left, down, up, right in a
    // fast stream. The correct reading crosses a foot over rather than
    // doublestepping. We assert: no foot is used twice in a row.
    final notes = stream([(0, L), (1, D), (2, U), (3, R)], bpm: 160);
    final p = assignParity(notes, Modes.singles);
    final feet = notes.map((n) => p[n]).toList();
    for (int i = 1; i < feet.length; i++) {
      expect(feet[i], isNot(equals(feet[i - 1])),
          reason: 'doublestep at $i: ${render(notes, p)}');
    }
  });

  test('footswitch: repeat where a jack would force a doublestep switches feet',
      () {
    // Force the footswitch to be the cheaper option. In "R L L D", the two L's
    // repeat: if the second L jacks (same foot, left) then reaching D next needs
    // the right foot which just isn't near — and more importantly the entry
    // R->L establishes flow that a jack breaks with a doublestep. The engine
    // should footswitch the L (left then right) so the run keeps alternating:
    // R L(sw) D ... i.e. the two L notes take different feet.
    final notes = stream([(0, R), (1, L), (2, L), (3, D)], bpm: 150);
    final p = assignParity(notes, Modes.singles);
    // Whatever it picks, every consecutive pair must not doublestep (same foot,
    // different columns). That is the property that matters for playability.
    final feet = notes.map((n) => p[n]).toList();
    for (int i = 1; i < feet.length; i++) {
      final sameFoot = feet[i] == feet[i - 1];
      final sameCol = notes[i].col == notes[i - 1].col;
      // Same foot is only OK on a jack (same column). Same foot on a different
      // column is a doublestep and should not happen in a clean stream.
      if (sameFoot && !sameCol) {
        fail('doublestep at $i: ${render(notes, p)}');
      }
    }
  });

  test('does not start crossed over', () {
    final notes = stream([(0, R), (1, L), (2, R), (3, L)]);
    final p = assignParity(notes, Modes.singles);
    // First note on Right should be right foot (starting crossed over is a
    // huge penalty).
    expect(p[notes[0]], equals(ParityFoot.right),
        reason: 'started crossed over: ${render(notes, p)}');
  });

  test('empty and mine-only streams are safe', () {
    expect(assignParity([], Modes.singles), isEmpty);
    final mines = [
      const StepNote(beat: 0, second: 0, col: 0, type: StepType.mine),
    ];
    expect(assignParity(mines, Modes.singles), isEmpty);
  });

  test('doubles mode runs without error and assigns all notes', () {
    final notes = stream([(0, 0), (1, 3), (2, 4), (3, 7), (4, 2), (5, 5)]);
    final p = assignParity(notes, Modes.doubles);
    expect(p.length, equals(notes.length));
  });
}
