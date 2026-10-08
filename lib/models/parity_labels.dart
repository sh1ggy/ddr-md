/// Name: Parity labels
/// Parent: ChartScroller, test/parity_labels_test.dart
/// Description: Hand-set feet for notes in real charts. In the chart preview
/// they pin the solve; exported, they are the evidence the labels test checks
/// the unpinned engine against. Also finds the moments worth labelling
/// (same-panel stances, footswitches, doublesteps, crossovers, side switches).
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/steps_model.dart';

enum ParityFlag { samePanel, footswitch, doublestep, crossover, sideswitch }

/// Which chart a set of labels belongs to: the steps file's song name, sp/dp,
/// and the difficulty key.
class ChartRef {
  final String song;
  final String mode;
  final String difficulty;

  const ChartRef(this.song, this.mode, this.difficulty);

  String get fileName => '${song}__${mode}_$difficulty.json';
}

/// A hand-set foot for one note, identified by beat and (unturned) column.
typedef ParityPin = (double beat, int col, ParityFoot foot);

/// All pins for one chart, as exported for the labels test. [chartHash] ties
/// them to the exact note data, so a regenerated chart reports its labels as
/// stale instead of misapplying them.
class ChartLabels {
  final ChartRef ref;
  final String chartHash;
  final List<ParityPin> pins;

  const ChartLabels(this.ref, this.chartHash, this.pins);

  factory ChartLabels.fromJson(Map<String, dynamic> j) => ChartLabels(
        ChartRef(j['song'] as String, j['mode'] as String,
            j['difficulty'] as String),
        j['chart_hash'] as String,
        [
          for (final p in j['pins'] as List)
            (
              (p['b'] as num).toDouble(),
              p['c'] as int,
              p['f'] == 'L' ? ParityFoot.left : ParityFoot.right,
            )
        ],
      );

  Map<String, dynamic> toJson() => {
        'song': ref.song,
        'mode': ref.mode,
        'difficulty': ref.difficulty,
        'chart_hash': chartHash,
        'pins': [
          for (final (b, c, f) in pins)
            {'b': b, 'c': c, 'f': f == ParityFoot.left ? 'L' : 'R'}
        ],
      };
}

/// [pins] keyed by the chart's own notes, for [analyseParity]. Pins whose note
/// no longer exists are dropped.
Map<StepNote, ParityFoot> pinsByNote(
    Iterable<ParityPin> pins, List<StepNote> notes) {
  final byKey = {for (final n in notes) (n.beat, n.col): n};
  return {
    for (final (b, c, f) in pins)
      if (byKey[(b, c)] case final n?) n: f
  };
}

/// FNV-1a over the note data. Stable across runs and platforms, unlike
/// [Object.hashAll].
String chartHash(List<StepNote> notes) {
  int h = 0x811c9dc5;
  for (final n in notes) {
    for (final unit in '${n.beat}:${n.col}:${n.type.index};'.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// Pins the solve gives the other foot to.
List<ParityPin> disagreements(Iterable<ParityPin> pins, List<StepNote> notes,
    Map<StepNote, ParityFoot> solved) {
  final byKey = {for (final n in notes) (n.beat, n.col): n};
  return [
    for (final pin in pins)
      if (byKey[(pin.$1, pin.$2)] case final n? when solved[n] != pin.$3) pin
  ];
}

/// Seconds of the rows each flag fires on, ascending. Rows are distinct note
/// seconds (mines excluded), matching the stance timeline.
Map<ParityFlag, List<double>> findFlags(
    List<StepNote> notes, ParityResult solve, Modes mode) {
  final flags = {for (final f in ParityFlag.values) f: <double>[]};
  final rows = <double, List<StepNote>>{};
  for (final n in notes) {
    if (n.type != StepType.mine) rows.putIfAbsent(n.second, () => []).add(n);
  }
  final secs = rows.keys.toList()..sort();
  final holds = notes.where((n) => n.isHold && n.endSecond != null).toList();
  bool held(double t) => holds.any((h) => h.second < t && t < h.endSecond!);

  bool wasCrossed = false;
  for (final s in solve.stances) {
    if (s.leftHeel != -1 && s.leftHeel == s.rightHeel) {
      flags[ParityFlag.samePanel]!.add(s.second);
    }
    // Only the row that enters a crossover; the rows it holds through follow.
    final crossed =
        mode == Modes.singles && (s.leftHeel == 3 || s.rightHeel == 0);
    if (crossed && !wasCrossed) flags[ParityFlag.crossover]!.add(s.second);
    wasCrossed = crossed;
  }

  final lastFootOn = <int, ParityFoot>{};
  for (int i = 0; i < secs.length; i++) {
    final row = rows[secs[i]]!;
    for (final n in row) {
      final f = solve.feet[n];
      if (f == null) continue;
      final side = mode == Modes.singles ? (n.col == 0 || n.col == 3) : false;
      if (side && lastFootOn[n.col] != null && lastFootOn[n.col] != f) {
        flags[ParityFlag.sideswitch]!.add(secs[i]);
      }
      lastFootOn[n.col] = f;
    }
    if (i == 0) continue;
    final prev = rows[secs[i - 1]]!;
    if (prev.length != 1 || row.length != 1 || held(secs[i])) continue;
    final a = prev.first, b = row.first;
    if (a.col == b.col && solve.feet[a] != solve.feet[b]) {
      flags[ParityFlag.footswitch]!.add(secs[i]);
    }
    if (a.col != b.col && solve.feet[a] == solve.feet[b]) {
      flags[ParityFlag.doublestep]!.add(secs[i]);
    }
  }
  for (final l in flags.values) {
    l.sort();
  }
  return flags;
}
