import 'dart:math' as math;

import 'package:ddr_md/components/song/notes/dancing_feet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Chart column indices — turnFor asks about the player's legs, so it reads
  // the chart, not the TURN-mapped panels on screen.
  const l = 0, d = 1, u = 2, r = 3;

  // Negative is counter-clockwise on the canvas, i.e. the body faces LEFT.
  double deg(int leftCol, int rightCol) =>
      turnFor(leftCol, rightCol) * 180 / math.pi;

  test('a <V^> staircase never turns the body', () {
    // The four stances an alternating L-D-U-R staircase cycles through
    // (confirmed against the solver). No leg crosses — the feet take turns
    // reaching forward — so the whole run stays pointing up the pad.
    //
    // The trap this guards: reading "crossed" off the feet's x coordinates
    // rather than their panels. A foot on a centre panel can sit further across
    // than its partner without any crossing, and U/R in particular measures as
    // most of a panel of "cross", which spun the body mid-staircase.
    for (final (name, lc, rc) in [
      ('L/D', l, d),
      ('U/D', u, d),
      ('U/R', u, r),
      ('L/R', l, r),
    ]) {
      expect(deg(lc, rc), 0, reason: '$name should stand forward');
    }
  });

  test('an alternating up/down run stays forward', () {
    // Both orderings, because a measure that depends on which foot is higher
    // alternates sign every step and visibly swings the feet back and forth.
    expect(deg(u, d), 0);
    expect(deg(d, u), 0);
  });

  // The crossed stances, as danced and dictated. There are only five in singles,
  // so this is the whole rule rather than a sample of it.
  //
  // A single cross reaches 45, not 90: one foot is still on a centre panel, so
  // the line between the feet runs diagonally and the body squares up to it. The
  // pivot panel therefore sets the sign, and it flips with which foot crossed —
  // the same partner panel opens the body one way for a left cross and winds it
  // the other for a right one.
  test('a single crossover turns the body 45 along the line of the feet', () {
    expect(deg(d, l), closeTo(-45, 0.001)); // R crosses under, partner on Down
    expect(deg(u, l), closeTo(45, 0.001)); //  R crosses under, partner on Up
    expect(deg(r, d), closeTo(45, 0.001)); //  L crosses over,  partner on Down
    expect(deg(r, u), closeTo(-45, 0.001)); // L crosses over,  partner on Up
  });

  test('the fully swapped stance turns a full quarter', () {
    // Both feet on side panels puts the axis flat across the pad, where +-90
    // name the same line. From square it resolves to +90.
    expect(deg(r, l), closeTo(90, 0.001));
  });

  // Each (left, right) stance in order, stepped through stepTurn.
  List<int> walk(List<(int, int)> stances) {
    var turn = 0.0, fl = -1, fr = -1;
    return [
      for (final (lc, rc) in stances)
        (turn = stepTurn(turn, fl, fr, fl = lc, fr = rc)) * 180 ~/ math.pi
    ];
  }

  test('only stepping across turns the body', () {
    // Scooby R-D-L-R footed R L R L: each foot steps across in turn, so the body
    // winds left and stays left rather than spinning round to +90.
    expect(walk([(l, r), (d, r), (d, l), (r, l)]), [0, 0, -45, -90]);
    // A D+L jump landing crossed, a re-press, then the right foot steps back
    // out of the cross: nobody stepped across, so no turn anywhere.
    expect(walk([(l, u), (d, l), (d, l), (d, u)]), [0, 0, 0, 0]);
  });

  test('both feet on one panel is a footswitch, not a crossover', () {
    for (final c in [l, d, u, r]) {
      expect(deg(c, c), 0, reason: 'stacked on column $c');
    }
  });

  test('a foot presses down on impact and recovers to full size', () {
    // Smallest on the landing frame, back to exactly 1 once the press is spent —
    // a foot standing through a long gap must not sit permanently shrunken.
    final onImpact = padPressFactor(0);
    expect(onImpact, lessThan(1));
    expect(padPressFactor(1.0), 1);
    // Monotonic recovery: any dip that overshoots or bounces reads as a wobble.
    var last = onImpact;
    for (var s = 0.01; s <= 0.3; s += 0.01) {
      final now = padPressFactor(s);
      expect(now, greaterThanOrEqualTo(last - 1e-9), reason: 'dipped again at $s');
      last = now;
    }
  });
}
