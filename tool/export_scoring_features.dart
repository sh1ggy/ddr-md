/// Name: Foot timing features
/// Parent: Offline scoring pipeline
/// Description: Measures solved per-foot cadence, movement and hold constraints
/// from note streams using the canonical app solver.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

const coordinates = [(-1.0, 0.0), (0.0, -1.0), (0.0, 1.0), (1.0, 0.0)];

void stats(Map<String, double> out, String key, List<double> values) {
  final sorted = values.toList()..sort();
  final mean =
      values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;
  out['${key}_mean'] = mean;
  for (final q in [0.0, 0.5, 0.9, 0.99, 1.0]) {
    out['${key}_q${(q * 100).round()}'] =
        sorted.isEmpty ? 0 : sorted[(q * (sorted.length - 1)).round()];
  }
  out['${key}_cv'] = values.isEmpty || mean == 0
      ? 0
      : math.sqrt(values.fold(0.0, (s, v) => s + (v - mean) * (v - mean)) /
              values.length) /
          mean;
}

Map<String, double> measure(List<StepNote> notes, {List<List<num>>? minaRows}) {
  final parity = analyseParity(notes, Modes.singles);
  final rows = footedRows(notes, parity);
  if (rows.length < 2) return {};
  if (minaRows != null) {
    for (final row in rows) {
      final mask = row.steps.values
          .toSet()
          .fold(0, (m, f) => m | (f == ParityFoot.left ? 1 : 8));
      minaRows.add([row.second, mask]);
    }
  }
  final out = <String, double>{};
  final length = rows.last.second - rows.first.second;
  final gaps = <double>[],
      distances = <double>[],
      speeds = <double>[],
      axisTurns = <double>[],
      widths = <double>[],
      moveTurns = <double>[],
      intervalChanges = <double>[];
  final lastTime = <ParityFoot, double>{}, lastGap = <ParityFoot, double>{};
  final lastPosition = <ParityFoot, (double, double)>{},
      lastVector = <ParityFoot, (double, double)>{};
  final count = <ParityFoot, int>{for (final f in ParityFoot.values) f: 0};
  final heldUntil = <ParityFoot, double>{};
  var samePanelFast = 0,
      movingFast = 0,
      crossed = 0,
      narrow = 0,
      both = 0,
      heldOther = 0,
      heldSame = 0,
      reversalsFast = 0,
      constrainedFast = 0;
  double? lastAxis;
  var previousRow = rows.first.second;
  var totalDistance = 0.0;
  final notesBySecond = <double, List<StepNote>>{};
  for (final n in notes) {
    if (n.type != StepType.mine) {
      (notesBySecond[(n.second * 1000).roundToDouble() / 1000] ??= []).add(n);
    }
  }
  for (final row in rows) {
    final active = <ParityFoot, List<int>>{};
    for (final e in row.steps.entries) {
      (active[e.value] ??= []).add(e.key);
    }
    if (active.length == 2) both++;
    for (final e in active.entries) {
      final foot = e.key, cols = e.value;
      final x = cols.map((c) => coordinates[c].$1).reduce((a, b) => a + b) /
          cols.length;
      final y = cols.map((c) => coordinates[c].$2).reduce((a, b) => a + b) /
          cols.length;
      final other =
          foot == ParityFoot.left ? ParityFoot.right : ParityFoot.left;
      count[foot] = count[foot]! + 1;
      final otherHeld = (heldUntil[other] ?? -1) > row.second + 0.0005;
      final thisHeld = (heldUntil[foot] ?? -1) > row.second + 0.0005;
      if (otherHeld) heldOther++;
      if (thisHeld) heldSame++;
      final t = lastTime[foot], p = lastPosition[foot];
      if (t != null && p != null && row.second > t) {
        final dt = row.second - t, dx = x - p.$1, dy = y - p.$2;
        final distance = math.sqrt(dx * dx + dy * dy);
        gaps.add(dt);
        distances.add(distance);
        speeds.add(distance / dt);
        totalDistance += distance;
        if (dt < 0.2) {
          if (distance < 0.01) {
            samePanelFast++;
          } else {
            movingFast++;
          }
        }
        if (otherHeld && dt < 0.3) constrainedFast++;
        final previousGap = lastGap[foot];
        if (previousGap != null) {
          intervalChanges.add((math.log(dt / previousGap) / math.ln2).abs());
        }
        final vector = lastVector[foot];
        if (vector != null && distance > 0.01) {
          final oldLength =
              math.sqrt(vector.$1 * vector.$1 + vector.$2 * vector.$2);
          if (oldLength > 0.01) {
            final cosine =
                ((dx * vector.$1 + dy * vector.$2) / (distance * oldLength))
                    .clamp(-1.0, 1.0);
            final angle = math.acos(cosine);
            moveTurns.add(angle);
            if (angle > math.pi / 2 && dt < 0.3) reversalsFast++;
          }
        }
        if (distance > 0.01) lastVector[foot] = (dx, dy);
        lastGap[foot] = dt;
      }
      lastTime[foot] = row.second;
      lastPosition[foot] = (x, y);
    }
    final l = lastPosition[ParityFoot.left], r = lastPosition[ParityFoot.right];
    if (l != null && r != null) {
      final dx = r.$1 - l.$1, dy = r.$2 - l.$2;
      final width = math.sqrt(dx * dx + dy * dy);
      widths.add(width);
      if (l.$1 > r.$1) crossed++;
      if (width < 0.75) narrow++;
      if (width > 0.01) {
        final axis = math.atan2(dy, dx);
        if (lastAxis != null && row.second > previousRow) {
          var angle = (axis - lastAxis).abs();
          if (angle > math.pi) angle = 2 * math.pi - angle;
          axisTurns.add(angle / (row.second - previousRow));
        }
        lastAxis = axis;
      }
    }
    for (final n in notesBySecond[(row.second * 1000).roundToDouble() / 1000] ??
        <StepNote>[]) {
      if (n.isHold && n.endSecond != null && parity.feet[n] != null) {
        final foot = parity.feet[n]!;
        heldUntil[foot] = math.max(heldUntil[foot] ?? -1, n.endSecond!);
      }
    }
    previousRow = row.second;
  }
  stats(out, 'foot_gap', gaps);
  stats(out, 'foot_travel', distances);
  stats(out, 'foot_speed', speeds);
  stats(out, 'stance_axis_rate', axisTurns);
  stats(out, 'stance_width', widths);
  stats(out, 'foot_move_turn', moveTurns);
  stats(out, 'foot_interval_change', intervalChanges);
  final n = rows.length;
  for (final cutoff in [0.1, 0.15, 0.2, 0.3, 0.5]) {
    out['foot_gap_under_$cutoff'] =
        gaps.where((g) => g < cutoff).length / math.max(1, gaps.length);
  }
  out.addAll({
    'foot_same_panel_fast_per100': samePanelFast * 100 / n,
    'foot_moving_fast_per100': movingFast * 100 / n,
    'stance_crossed_fraction': crossed / n,
    'stance_narrow_fraction': narrow / n,
    'both_feet_row_fraction': both / n,
    'other_foot_held_fraction': heldOther / n,
    'stepping_foot_held_fraction': heldSame / n,
    'constrained_fast_fraction': constrainedFast / n,
    'fast_foot_reversal_fraction': reversalsFast / n,
    'foot_travel_per_second': totalDistance / math.max(length, 0.01),
    'foot_travel_per_row': totalDistance / n,
    'foot_count_imbalance':
        (count[ParityFoot.left]! - count[ParityFoot.right]!).abs() /
            math.max(1, count.values.reduce((a, b) => a + b)),
  });
  final footwork = footworkOf(notes, parity, Modes.singles);
  for (final p in Pattern.values) {
    out['solved_${p.name}_per100'] = footwork.count(p) * 100 / n;
    final spans = footwork.spans.where((s) => s.$1 == p).toList();
    out['solved_${p.name}_fast_per100'] =
        spans.where((s) => s.$3 - s.$2 < 0.15).length * 100 / n;
  }
  final mineTimes =
      notes.where((n) => n.type == StepType.mine).map((n) => n.second).toSet();
  out['mine_rows_per100'] = mineTimes.length * 100 / n;
  var quickAfterMine = 0;
  for (final t in mineTimes) {
    final next = rows.where((r) => r.second >= t).firstOrNull;
    if (next != null && next.second - t < 0.25) quickAfterMine++;
  }
  out['mine_quick_followup_per100'] = quickAfterMine * 100 / n;
  assert(out.values.every((v) => v.isFinite));
  return out;
}

void main() {
  test('export canonical scoring derivatives', () {
    final root = Platform.environment['SCORING_INPUT'];
    final output = Platform.environment['SCORING_OUTPUT'];
    final manifest = Platform.environment['SCORING_CHARTS'];
    if (root == null || output == null || manifest == null) {
      throw ArgumentError(
          'Set SCORING_INPUT (songs/steps parent), SCORING_OUTPUT and SCORING_CHARTS');
    }
    final selected = jsonDecode(File(manifest).readAsStringSync()) as List;
    final results = <Map<String, dynamic>>[];
    for (final raw in selected) {
      final name = raw['name'] as String, diff = raw['difficulty'] as String;
      final bytes = File('$root/steps/$name.json').readAsBytesSync();
      final chart =
          SongSteps.fromJson(jsonDecode(utf8.decode(bytes))).singles[diff];
      if (chart == null) throw StateError('Missing SP $diff for $name');
      final rows = <List<num>>[];
      final features = measure(chart.notes, minaRows: rows);
      final parity = analyseParity(chart.notes, Modes.singles);
      final counts = footworkOf(chart.notes, parity, Modes.singles);
      results.add({
        'name': name,
        'difficulty': diff,
        'source_sha256': sha256.convert(bytes).toString(),
        'features': features,
        'mina_rows': rows,
        'patterns': {
          'steps': footedRows(chart.notes, parity).length,
          'counts': {for (final p in Pattern.values) p.name: counts.count(p)},
          'at': {for (final p in Pattern.values) p.name: counts.at[p]},
        },
      });
    }
    File(output).writeAsStringSync(jsonEncode(results));
    final sources = <String, String>{};
    for (final path in [
      'lib/models/parity.dart',
      'lib/models/pattern_analysis.dart',
      'lib/models/steps_model.dart',
      'tool/export_scoring_features.dart'
    ]) {
      sources[path] = sha256.convert(File(path).readAsBytesSync()).toString();
    }
    File('$output.metadata.json').writeAsStringSync(jsonEncode({
      'sources': sources,
      'sha256': sha256.convert(File(output).readAsBytesSync()).toString(),
    }));
  }, timeout: Timeout.none);
}
