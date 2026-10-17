/// Name: Shock evasion tests
/// Parent: Parity shock planner
/// Description: Verifies support choice, pivot direction and note clearance.
library;

import 'dart:math' as math;
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/parity_shocks.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

StepNote note(double t, int col, {double? end}) => StepNote(
    beat: t * 2,
    second: t,
    col: col,
    type: end == null ? StepType.tap : StepType.hold,
    endSecond: end);
List<StepNote> shocks(double t) => [
      for (var c = 0; c < 4; c++)
        StepNote(beat: t * 2, second: t, col: c, type: StepType.mine)
    ];
ParityStance stance(double t, int l, int r, Set<int> hit) => ParityStance(
    second: t,
    leftHeel: l,
    leftToe: l,
    rightHeel: r,
    rightToe: r,
    stepped: hit);

void main() {
  for (final col in [1, 2]) {
    test('heel/toe on $col releases the arrow without a rear-corner retreat',
        () {
      final p = planShockEvasions([
        note(1, col),
        ...shocks(1.3),
        note(1.6, 3)
      ], [
        stance(1, col, 3, {col}),
        stance(1.6, col, 3, {3})
      ], Modes.singles)
          .single;
      expect(p.method, ShockMethod.heelToe);
      expect(p.left!.role, ShockRole.pivot);
      expect(p.right!.role, ShockRole.hover);
      expect(p.amount(ParityFoot.left, 1), 0);
      expect(p.amount(ParityFoot.left, 1.3), 1);
      expect(p.amount(ParityFoot.left, 1.6), 0);
      final foot = p.pose(ParityFoot.left, 1, 1.3);
      expect(foot.tilt.sign, col == 2 ? -1 : 1);
      // The supporting heel/toe touches centre metal, the arrow-facing end rises.
      final pivotY = foot.y + (col == 2 ? -1 : 1) * math.cos(foot.tilt) / 2;
      expect(pivotY, closeTo(0, 1e-9));
      expect(foot.lift, closeTo(math.sin(foot.tilt.abs()) * .283 / 2, 1e-9));
    });
  }
  test('launch lands the other foot flat on centre until its own next step',
      () {
    final p = planShockEvasions([
      note(1, 0),
      ...shocks(1.3),
      note(1.6, 3),
      note(2, 0)
    ], [
      stance(1, 0, 3, {0}),
      stance(1.6, 0, 3, {3}),
      stance(2, 0, 3, {0})
    ], Modes.singles)
        .single;
    expect(p.method, ShockMethod.launch);
    expect(p.left!.role, ShockRole.centre);
    expect(p.right!.role, ShockRole.hover);
    expect(p.pose(ParityFoot.left, 1, p.start + .01).airborne, isTrue);
    final landed = p.pose(ParityFoot.left, 1, 1.3);
    expect((landed.airborne, landed.lift, landed.tilt), (false, 0, 0));
    expect(p.amount(ParityFoot.right, 1.6), 0);
    expect(p.amount(ParityFoot.left, 1.8), 1);
    expect(p.exit(ParityFoot.left, 1.95), inExclusiveRange(0, 1));
  });
  test('heel/toe lands the spare foot when the pivot foot steps next', () {
    final p = planShockEvasions([
      note(1, 2),
      ...shocks(1.3),
      note(1.6, 0)
    ], [
      stance(1, 2, 3, {2}),
      stance(1.6, 0, 3, {0})
    ], Modes.singles)
        .single;
    expect(p.left!.role, ShockRole.pivot);
    expect(p.right!.role, ShockRole.centre);
  });
  test('a foot on centre stays there through the next shock', () {
    final plans = planShockEvasions([
      note(1, 0),
      ...shocks(1.3),
      note(1.5, 3),
      ...shocks(1.7),
      note(2, 0)
    ], [
      stance(1, 0, 3, {0}),
      stance(1.5, 0, 3, {3}),
      stance(2, 0, 3, {0})
    ], Modes.singles);
    expect(plans[1].left, isNull);
    expect(shockFor(plans, ParityFoot.left, 1.7), plans[0]);
    expect(plans[0].amount(ParityFoot.left, 1.7 + .084), 1);
  });
  test('hold is never released early to evade a shock', () {
    final p = planShockEvasions([
      note(1, 2, end: 1.4),
      ...shocks(1.3)
    ], [
      stance(1, 2, 3, {2})
    ], Modes.singles)
        .single;
    expect(p.feasible, isFalse);
    expect(p.amount(ParityFoot.left, 1.3), 0);
  });
  test('finished hold bounds the launch transition', () {
    final p = planShockEvasions([
      note(1, 2, end: 1.2),
      ...shocks(1.3)
    ], [
      stance(1, 2, 3, {2})
    ], Modes.singles)
        .single;
    expect(p.start, 1.2);
    expect(p.amount(ParityFoot.left, 1.19), 0);
  });
  test('DP split stance evades on each foot\'s own pad', () {
    final p = planShockEvasions([
      note(1, 0),
      for (var c = 0; c < 8; c++)
        StepNote(beat: 2.6, second: 1.3, col: c, type: StepType.mine),
      note(1.6, 7)
    ], [
      stance(1, 0, 7, {0}),
      stance(1.6, 0, 7, {7})
    ], Modes.doubles)
        .single;
    expect(p.left!.padX, -1.5);
    expect(p.right!.padX, 1.5);
  });
  test('isolated mines do not become shocks', () {
    expect(planShockEvasions([shocks(1).first], [], Modes.singles), isEmpty);
  });
  test('only shoes longer than a panel are pitched to fit centre', () {
    final p = planShockEvasions([
      note(1, 0),
      ...shocks(1.3)
    ], [
      stance(1, 0, 3, {0})
    ], Modes.singles)
        .single;
    for (final size in [.8, 1.0, 1.2]) {
      for (final f in ParityFoot.values) {
        final q = p.pose(f, size, 1.3);
        expect(q.x.abs() + size * .185, lessThan(.5));
        expect(q.tilt == 0, size <= 1);
        expect(size * math.cos(q.tilt), lessThanOrEqualTo(1 + 1e-9));
      }
    }
  });
  test('DP safe-pad note and hold continue during a one-pad shock', () {
    final notes = [
      note(1, 0),
      note(1, 7, end: 1.6),
      ...shocks(1.3),
      note(1.3, 6)
    ];
    final p = planShockEvasions(
            notes,
            [
              stance(1, 0, 7, {0, 7}),
              stance(1.3, 0, 6, {6})
            ],
            Modes.doubles)
        .single;
    expect(p.feasible, isTrue);
    expect(p.left, isNotNull);
    expect(p.right, isNull);
    expect(p.columns.contains(7), isFalse);
    expect(p.amount(ParityFoot.left, 1.3), 1);
  });
}
