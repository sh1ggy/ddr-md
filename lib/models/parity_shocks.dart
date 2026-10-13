/// Name: Parity shock evasion
/// Parent: Parity / chart dancers
/// Description: Plans non-arrow support between the parity solve's note rows.
library;

import 'dart:math' as math;
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/steps_model.dart';

enum ShockMethod { standard, launch, heelToe }

/// Stage coordinates in panel units: x right, y towards the screen.
class ShockFootPose {
  const ShockFootPose(this.x, this.y, this.lift, this.tilt,
      {this.airborne = false});
  final double x, y;
  final bool airborne;

  /// Height in metres and pitch in radians (positive lifts the heel).
  final double lift, tilt;
}

class ShockEvasion {
  const ShockEvasion(
      {required this.second,
      required this.start,
      required this.end,
      required this.method,
      required this.support,
      required this.padX,
      required this.up,
      required this.transfer,
      required this.feasible,
      this.columns = const {0, 1, 2, 3},
      this.leftAffected = true,
      this.rightAffected = true});
  final double second, start, end, padX;
  final ShockMethod method;
  final ParityFoot? support;
  final bool up, transfer, feasible;
  final Set<int> columns;
  final bool leftAffected, rightAffected;
  bool affects(ParityFoot foot) =>
      foot == ParityFoot.left ? leftAffected : rightAffected;

  /// Clear the arrows at the shock, with transitions bounded by actual notes.
  double amount(double t) {
    if (!feasible || t <= start || t >= end) return 0;
    final before = math.min(0.09, (second - start) * 0.4);
    final after = math.min(0.09, (end - second) * 0.4);
    final a = t < second - before
        ? (t - start) / (second - before - start)
        : t > second + after
            ? (end - t) / (end - second - after)
            : 1.0;
    final v = a.clamp(0.0, 1.0);
    return v * v * (3 - 2 * v);
  }

  /// Shoe-size-aware contact: heel/toe supports use only the end over metal;
  /// launch feet pitch enough to fit their projected sole inside the centre.
  ShockFootPose pose(ParityFoot foot, double shoePanels, double t) {
    final sign = foot == ParityFoot.left ? -1.0 : 1.0;
    final side = sign * (shoePanels * 0.185 + 0.015);
    if (method == ShockMethod.standard) {
      return ShockFootPose(padX + sign * 0.3, 0, 0.10, 0, airborne: true);
    }
    final supporting = foot == support;
    if (method == ShockMethod.heelToe && supporting) {
      // Up: heel stays over centre, toes lift. Down reverses that pivot.
      final pitch = up ? -0.65 : 0.65;
      return ShockFootPose(
          padX + side,
          (up ? 1 : -1) * shoePanels * math.cos(pitch) * 0.5,
          shoePanels * 0.283 * math.sin(pitch.abs()) * 0.5,
          pitch);
    }
    final pitch = math.acos(math.min(1.0, 0.80 / shoePanels));
    final resting = supporting || transfer;
    // Heel/toe keeps the spare foot airborne through the shock, then transfers
    // weight to centre metal so the original support can take the next arrow.
    final land = method == ShockMethod.heelToe && transfer && !supporting
        ? ((t - second) / (end - second) * 2).clamp(0.0, 1.0)
        : 1.0;
    final height = shoePanels * 0.283 * math.sin(pitch) / 2;
    return ShockFootPose(
        padX + side,
        0,
        resting ? 0.10 + (height - 0.10) * land : 0.10,
        resting ? pitch * land : 0,
        airborne: !resting || land < 0.999);
  }
}

/// Full-pad mine rows are shocks; isolated mines remain the solver's concern.
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
  final out = <ShockEvasion>[];
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
    final desiredSupport =
        nextFoot == ParityFoot.left ? ParityFoot.right : ParityFoot.left;
    ParityFoot? pivot;
    int pivotCol = -1;
    if (previous != null) {
      for (final foot in [
        desiredSupport,
        desiredSupport == ParityFoot.left ? ParityFoot.right : ParityFoot.left
      ]) {
        final cols = previous.columnsFor(foot);
        if (cols.length == 1 &&
            previous.stepped.contains(cols.single) &&
            columns.contains(cols.single) &&
            (cols.single % 4 == 1 || cols.single % 4 == 2)) {
          pivot = foot;
          pivotCol = cols.single;
          break;
        }
      }
    }
    final support = pivot ?? desiredSupport;
    final cols = previous?.columnsFor(support) ?? const <int>[];
    final padX = count == 4
        ? 0.0
        : ((pivotCol >= 0 ? pivotCol : (cols.isEmpty ? 0 : cols.first)) < 4
            ? -1.5
            : 1.5);
    // DP may have one foot on each pad; use an airborne fallback rather than
    // dragging a supporting foot across the seam on an SP-only assumption.
    final split = count == 8 &&
        previous != null &&
        previous.columnsFor(ParityFoot.left).isNotEmpty &&
        previous.columnsFor(ParityFoot.right).isNotEmpty &&
        (previous.columnsFor(ParityFoot.left).first < 4) !=
            (previous.columnsFor(ParityFoot.right).first < 4);
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
    out.add(ShockEvasion(
        second: t,
        start: start,
        end: end,
        method: split || previous == null
            ? ShockMethod.standard
            : pivot != null
                ? ShockMethod.heelToe
                : ShockMethod.launch,
        support: support,
        padX: padX,
        up: pivotCol % 4 == 2,
        transfer: nextFoot == null || pivot == nextFoot,
        feasible: !blocked && start < t && end > t,
        columns: columns,
        leftAffected: previous == null ||
            previous.columnsFor(ParityFoot.left).any(columns.contains),
        rightAffected: previous == null ||
            previous.columnsFor(ParityFoot.right).any(columns.contains)));
  }
  return out;
}

ShockEvasion? shockAt(List<ShockEvasion> plans, double second) {
  var lo = 0, hi = plans.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (plans[mid].second <= second) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  for (final i in [lo - 1, lo]) {
    if (i >= 0 && i < plans.length && plans[i].amount(second) > 0) {
      return plans[i];
    }
  }
  return null;
}
