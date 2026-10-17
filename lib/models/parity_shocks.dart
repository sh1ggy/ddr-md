/// Name: Parity shock evasion
/// Parent: Parity / chart dancers
/// Description: Plans non-arrow support between the parity solve's note rows.
library;

import 'dart:math' as math;
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/steps_model.dart';

enum ShockMethod { standard, launch, heelToe }

/// Where one foot spends a shock: standing on centre metal, held just above it
/// ready for the next arrow, rocked onto the heel or toes that overhang centre
/// from Up/Down, or in the air over its arrow (standard).
enum ShockRole { centre, hover, pivot, air }

/// Stage coordinates in panel units: x right, y towards the screen.
class ShockFootPose {
  const ShockFootPose(this.x, this.y, this.lift, this.tilt,
      {this.airborne = false});
  final double x, y;
  final bool airborne;

  /// Height in metres and pitch in radians (positive lifts the heel).
  final double lift, tilt;
}

class ShockFoot {
  const ShockFoot(this.role, this.padX, this.release, this.exitStart,
      {this.steps = true, this.up = false});
  final ShockRole role;
  final double padX;

  /// When the foot leaves its evasion. One that [steps] leaves by stepping
  /// onto its next arrow at [release], travelling from [exitStart]; otherwise
  /// it settles back onto its own panel over that span.
  final double release, exitStart;
  final bool steps;

  /// A pivot from Up rests on its heel, from Down on its toes.
  final bool up;
}

class ShockEvasion {
  const ShockEvasion(
      {required this.second,
      required this.start,
      required this.land,
      required this.feasible,
      this.left,
      this.right,
      this.columns = const {0, 1, 2, 3}});
  final double second, start, land;
  final bool feasible;
  final Set<int> columns;

  /// Null for a foot this shock doesn't move: on a safe panel already, or
  /// still on centre metal from an earlier shock.
  final ShockFoot? left, right;
  ShockFoot? of(ParityFoot foot) => foot == ParityFoot.left ? left : right;

  ShockMethod get method {
    final roles = [left?.role, right?.role];
    if (roles.contains(ShockRole.air)) return ShockMethod.standard;
    if (roles.contains(ShockRole.pivot)) return ShockMethod.heelToe;
    return ShockMethod.launch;
  }

  /// How far [foot] is into its evasion: rising over [start]..[land], held
  /// through the shock until it leaves at its release.
  double amount(ParityFoot foot, double t) {
    final f = of(foot);
    if (!feasible || f == null || t <= start || t >= f.release) return 0;
    final a = t < land
        ? (t - start) / (land - start)
        : !f.steps && t > f.exitStart
            ? (f.release - t) / (f.release - f.exitStart)
            : 1.0;
    final v = a.clamp(0.0, 1.0);
    return v * v * (3 - 2 * v);
  }

  /// Linear progress of the spring off the arrows, for the hop's arc.
  double hop(double t) => ((t - start) / (land - start)).clamp(0.0, 1.0);

  /// Progress of [foot] stepping from its evasion onto its next arrow, or 0.
  double exit(ParityFoot foot, double t) {
    final f = of(foot);
    if (!feasible || f == null || !f.steps || t <= f.exitStart) return 0;
    return ((t - f.exitStart) / (f.release - f.exitStart)).clamp(0.0, 1.0);
  }

  /// Shoe-size-aware contact: a pivot keeps only the end over metal; a foot on
  /// centre stands flat unless the shoe is longer than the panel.
  ShockFootPose pose(ParityFoot foot, double shoePanels, double t) {
    final f = of(foot)!;
    final sign = foot == ParityFoot.left ? -1.0 : 1.0;
    final side = sign * (shoePanels * 0.185 + 0.015);
    switch (f.role) {
      case ShockRole.air:
        return ShockFootPose(f.padX + sign * 0.3, 0, 0.10, 0, airborne: true);
      case ShockRole.pivot:
        // Up: heel stays over centre, toes lift. Down reverses that pivot.
        final pitch = f.up ? -0.65 : 0.65;
        return ShockFootPose(
            f.padX + side,
            (f.up ? 1 : -1) * shoePanels * math.cos(pitch) * 0.5,
            shoePanels * 0.283 * math.sin(pitch.abs()) * 0.5,
            pitch);
      case ShockRole.hover:
        return ShockFootPose(f.padX + side, 0, 0.10, 0, airborne: true);
      case ShockRole.centre:
        final pitch = math.acos(math.min(1.0, 1 / shoePanels));
        return ShockFootPose(
            f.padX + side, 0, shoePanels * 0.283 * math.sin(pitch) / 2, pitch,
            airborne: t < land);
    }
  }
}

/// Full-pad mine rows are shocks; isolated mines remain the solver's concern.
/// Each moved foot is planned on its own: Up/Down feet that just stepped pivot,
/// any other foot lands on centre metal, and the foot that steps next is held
/// free above it while someone else carries the weight. Feet that left their
/// arrows stay off them until their own next step.
List<ShockEvasion> planShockEvasions(
    List<StepNote> notes, List<ParityStance> stances, Modes mode) {
  final count = mode == Modes.singles ? 4 : 8;
  final mines = <int, Set<int>>{};
  for (final n in notes.where((n) => n.type == StepType.mine)) {
    (mines[(n.second * 1000).round()] ??= {}).add(n.col);
  }
  final times = [
    for (final e in mines.entries)
      if (e.value.length >= 3) e.key / 1000
  ]..sort();
  final rows = [...stances]..sort((a, b) => a.second.compareTo(b.second));
  double? stepAfter(ParityFoot foot, double t) {
    for (final s in rows) {
      if (s.second > t && s.columnsFor(foot).any(s.stepped.contains)) {
        return s.second;
      }
    }
    return null;
  }

  // Per foot, the shock that last moved it and how long it's away.
  final away = <ParityFoot, (int, double)>{};
  final clear = <(int, ParityFoot), double>{};
  final drafts =
      <(double, double, double, bool, Set<int>, Map<ParityFoot, ShockFoot>)>[];
  for (var i = 0; i < times.length; i++) {
    final t = times[i];
    ParityStance? previous, next;
    for (final s in rows) {
      if (s.second < t) {
        previous = s;
      } else if (s.second > t) {
        next = s;
        break;
      }
    }
    final columns = mines[(t * 1000).round()]!;
    final blocked = notes.any((n) =>
        columns.contains(n.col) &&
        n.type != StepType.mine &&
        ((n.second - t).abs() < 0.001 ||
            (n.isHold && n.second < t && (n.endSecond ?? n.second) > t)));
    ParityFoot? nextFoot;
    if (next != null && next.stepped.length == 1) {
      final col = next.stepped.single;
      nextFoot = next.columnsFor(ParityFoot.left).contains(col)
          ? ParityFoot.left
          : ParityFoot.right;
    }
    final affectedRows = rows.where((s) => s.stepped.any(columns.contains));
    final before = affectedRows.where((s) => s.second < t).toList();
    final after = affectedRows.where((s) => s.second > t).toList();
    var start = math.max(
        t - 0.22, (before.isEmpty ? t - 1 : before.last.second) + 0.001);
    for (final n in notes) {
      if (columns.contains(n.col) &&
          n.isHold &&
          n.second < t &&
          n.endSecond != null &&
          n.endSecond! <= t) {
        start = math.max(start, n.endSecond!);
      }
    }
    var end = math.min(
        t + 0.22, (after.isEmpty ? t + 1 : after.first.second) - 0.001);
    if (i > 0) start = math.max(start, (times[i - 1] + t) / 2);
    if (i + 1 < times.length) end = math.min(end, (times[i + 1] + t) / 2);
    final land = t - math.min(0.09, (t - start) * 0.4);
    final cleared = t + math.min(0.09, (end - t) * 0.4);

    final feet = <ParityFoot, ShockFoot>{};
    if (previous == null) {
      // Nobody has stepped yet: stay in the air over the pad.
      for (final foot in ParityFoot.values) {
        feet[foot] = ShockFoot(ShockRole.air, 0, end, cleared, steps: false);
      }
    } else {
      final carried = {
        for (final e in away.entries)
          if (e.value.$2 > t) e.key
      };
      for (final foot in carried) {
        final key = (away[foot]!.$1, foot);
        clear[key] = math.max(clear[key]!, cleared);
      }
      final moving = [
        for (final foot in ParityFoot.values)
          if (!carried.contains(foot) &&
              previous.columnsFor(foot).any(columns.contains))
            foot
      ];
      double padOf(ParityFoot foot) {
        final cols = previous!.columnsFor(foot);
        return count == 4 || cols.isEmpty ? 0 : (cols.first < 4 ? -1.5 : 1.5);
      }

      // Feet already safe carry the weight: on an unshocked panel, or still on
      // centre metal (or a heel/toe) from an earlier shock.
      var supported = ParityFoot.values.any((foot) => carried.contains(foot)
          ? drafts[away[foot]!.$1].$6[foot]!.role != ShockRole.hover
          : !moving.contains(foot) && previous!.columnsFor(foot).isNotEmpty);
      final pivots = [
        for (final foot in moving)
          if (previous.columnsFor(foot).length == 1 &&
              previous.stepped.contains(previous.columnsFor(foot).single) &&
              (previous.columnsFor(foot).single % 4 == 1 ||
                  previous.columnsFor(foot).single % 4 == 2))
            foot
      ];
      for (final foot in pivots) {
        final col = previous.columnsFor(foot).single;
        final own = stepAfter(foot, t);
        // Toes go back down once the shock passes, unless another arrives
        // before this foot steps again.
        final stepsNext = own != null &&
            (own == next?.second || times.any((s) => s > t && s < own));
        final release = stepsNext ? own : (next?.second ?? t + 0.22);
        feet[foot] = ShockFoot(ShockRole.pivot, padOf(foot), release,
            math.max(cleared, release - 0.18),
            steps: stepsNext, up: col % 4 == 2);
        supported = true;
      }
      // The foot that isn't stepping next lands first, so it can be the one
      // carrying the weight.
      final rest = moving.where((f) => !pivots.contains(f)).toList()
        ..sort((a, b) => (a == nextFoot ? 1 : 0) - (b == nextFoot ? 1 : 0));
      for (final foot in rest) {
        final role =
            supported && foot == nextFoot ? ShockRole.hover : ShockRole.centre;
        supported = true;
        final own = stepAfter(foot, t);
        final release = own ?? t + 0.5;
        feet[foot] = ShockFoot(
            role, padOf(foot), release, math.max(cleared, release - 0.18),
            steps: own != null);
      }
    }
    final feasible = !blocked && start < t && end > t;
    for (final e in feet.entries) {
      if (feasible) away[e.key] = (i, e.value.release);
      clear[(i, e.key)] = e.value.exitStart;
    }
    drafts.add((t, start, land, feasible, columns, feet));
  }

  return [
    for (var i = 0; i < drafts.length; i++)
      () {
        final (t, start, land, feasible, columns, feet) = drafts[i];
        ShockFoot? final_(ParityFoot foot) {
          final f = feet[foot];
          if (f == null) return null;
          return ShockFoot(
              f.role, f.padX, f.release, math.min(f.release, clear[(i, foot)]!),
              steps: f.steps, up: f.up);
        }

        return ShockEvasion(
            second: t,
            start: start,
            land: land,
            feasible: feasible,
            columns: columns,
            left: final_(ParityFoot.left),
            right: final_(ParityFoot.right));
      }()
  ];
}

/// The shock currently moving [foot], if any. A foot sent to centre metal can
/// stay there through later shocks, so this looks back past the latest one.
ShockEvasion? shockFor(List<ShockEvasion> plans, ParityFoot foot, double t) {
  var lo = 0, hi = plans.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (plans[mid].second <= t + 0.25) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  for (var i = lo - 1; i >= 0 && plans[i].second > t - 4; i--) {
    if (plans[i].amount(foot, t) > 0) return plans[i];
  }
  return null;
}
