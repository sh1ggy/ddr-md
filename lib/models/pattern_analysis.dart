/// Name: Pattern analysis
/// Description: Names the patterns in a chart from how it is danced. The
/// parity engine ([analyseParity]) decides the footing; this reads that
/// footing row by row and counts crossovers, footswitches, jacks and the rest,
/// each by a fixed rule, with the beat of every occurrence. Run offline over the
/// whole library by tool/generate_patterns.dart,
/// and live by the chart preview on its own footing.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/steps_model.dart';

/// Counted patterns, in display order. Values are the JSON keys.
enum Pattern {
  crossover,
  footswitch,
  sideswitch,
  jack,
  doublestep,
  bracket,
  candle,
  drill,
  staircase,
}

// Speed cutoffs: slower than these, consecutive steps are ordinary footwork
// rather than the technique. Shared with ITGmania's tech counts.
const double kJackCutoff = 0.176; // ~8ths at 170 BPM
const double kDoublestepCutoff = 0.235; // ~8ths at 128 BPM
const double kFootswitchCutoff = 0.3; // ~8ths at 100 BPM

/// Gap at or under which single steps chain into a drill or staircase (8ths at
/// 120 BPM), and how uneven that chain may be.
const double kRunGap = 0.25;
const double kRunEvenness = 0.1;

/// Longest a candle may take, first step to last.
const double kCandleSpan = 1.0;

/// A row of the solved chart: when it is, and which foot hit which column.
class FootedRow {
  final double second;
  final double beat;

  /// Column -> foot, for the columns stepped on this row (not held ones).
  final Map<int, ParityFoot> steps;

  const FootedRow(this.second, this.beat, this.steps);

  bool get single => steps.length == 1;
  int get column => steps.keys.first;
  ParityFoot get foot => steps.values.first;
  Iterable<int> columnsOf(ParityFoot f) =>
      steps.entries.where((e) => e.value == f).map((e) => e.key);
}

/// Pad x positions, for "which side of the body" — left of centre is negative.
const _xSingles = [-1.0, 0.0, 0.0, 1.0];
const _xDoubles = [-2.5, -1.5, -1.5, -0.5, 0.5, 1.5, 1.5, 2.5];

bool _isDown(int col) => col % 4 == 1;
bool _isUp(int col) => col % 4 == 2;

/// Occurrence beats per pattern, plus the half/full and up/down splits.
class FootworkCounts {
  final Map<Pattern, List<double>> at = {for (final p in Pattern.values) p: []};

  /// Every occurrence's first and last row, in seconds, for highlighting.
  final List<(Pattern, double, double)> spans = [];
  int fullCrossovers = 0;
  int upFootswitches = 0;
  int downFootswitches = 0;

  int count(Pattern p) => at[p]!.length;
}

/// Counts every [Pattern] over [rows] (a solved chart, in time order).
/// [holdSpans] are (start, end) seconds of each hold, so a doublestep the other
/// foot's hold forces isn't counted against the chart.
FootworkCounts countFootwork(List<FootedRow> rows, Modes mode,
    {List<(double, double)> holdSpans = const []}) {
  final xs = mode == Modes.doubles ? _xDoubles : _xSingles;
  final out = FootworkCounts();
  void add(Pattern p, FootedRow from, FootedRow to) {
    out.at[p]!.add(to.beat);
    out.spans.add((p, from.second, to.second));
  }

  double footX(FootedRow r, ParityFoot f) {
    final cols = r.columnsOf(f).toList();
    return cols.map((c) => xs[c]).reduce((a, b) => a + b) / cols.length;
  }

  for (int i = 1; i < rows.length; i++) {
    final cur = rows[i], prev = rows[i - 1];
    final gap = cur.second - prev.second;

    // Jack / doublestep: one foot takes two single steps in a row.
    if (cur.single && prev.single && cur.foot == prev.foot) {
      if (cur.column == prev.column) {
        if (gap < kJackCutoff) add(Pattern.jack, prev, cur);
      } else if (gap < kDoublestepCutoff &&
          !holdSpans.any((h) => h.$1 <= prev.second && h.$2 >= cur.second)) {
        add(Pattern.doublestep, prev, cur);
      }
    }

    // Bracket: one foot covers two panels on a row.
    for (final f in ParityFoot.values) {
      if (cur.steps.length >= 2 && cur.columnsOf(f).length >= 2) {
        add(Pattern.bracket, cur, cur);
      }
    }

    // Footswitch / sideswitch: the same panel, the other foot, quickly.
    if (gap < kFootswitchCutoff) {
      for (final e in cur.steps.entries) {
        final was = prev.steps[e.key];
        if (was == null || was == e.value) continue;
        if (_isUp(e.key) || _isDown(e.key)) {
          add(Pattern.footswitch, prev, cur);
          _isUp(e.key) ? out.upFootswitches++ : out.downFootswitches++;
        } else {
          add(Pattern.sideswitch, prev, cur);
        }
      }
    }

    // Crossover: the foot stepping now lands on the far side of the foot that
    // stepped last row. Full when it came from its own side (R-D-L played
    // R-L-R), half when it was already mid-pad (U-D-L).
    for (final f in ParityFoot.values) {
      final other = f == ParityFoot.left ? ParityFoot.right : ParityFoot.left;
      if (cur.columnsOf(f).isEmpty ||
          prev.columnsOf(other).isEmpty ||
          prev.columnsOf(f).isNotEmpty) {
        continue;
      }
      final fx = footX(cur, f), ox = footX(prev, other);
      final crossed = f == ParityFoot.right ? fx < ox : fx > ox;
      if (!crossed) continue;
      add(Pattern.crossover, prev, cur);
      if (i > 1 && rows[i - 2].columnsOf(f).isNotEmpty) {
        final fromX = footX(rows[i - 2], f);
        if (f == ParityFoot.right ? fromX > ox : fromX < ox) {
          out.fullCrossovers++;
        }
      }
      break;
    }

    // Candle: in alternation, one foot goes straight from Down to Up (or back)
    // on one pad, sweeping round the other foot.
    if (i > 1 && cur.single && prev.single && rows[i - 2].single) {
      final from = rows[i - 2];
      if (from.foot == cur.foot &&
          prev.foot != cur.foot &&
          cur.second - from.second <= kCandleSpan &&
          from.column ~/ 4 == cur.column ~/ 4 &&
          ((_isDown(from.column) && _isUp(cur.column)) ||
              (_isUp(from.column) && _isDown(cur.column)))) {
        add(Pattern.candle, from, cur);
      }
    }
  }

  _countRuns(rows, mode, out);
  return out;
}

/// Drills (two panels traded off evenly, alternating feet, 6+ steps) and
/// staircases (all four singles panels swept in order, alternating feet).
void _countRuns(List<FootedRow> rows, Modes mode, FootworkCounts out) {
  bool evenAlternating(int from, int to) {
    final first = rows[from + 1].second - rows[from].second;
    if (first > kRunGap) return false;
    for (int k = from + 1; k <= to; k++) {
      final g = rows[k].second - rows[k - 1].second;
      if (!rows[k].single ||
          rows[k].foot == rows[k - 1].foot ||
          (g - first).abs() > first * kRunEvenness) {
        return false;
      }
    }
    return rows[from].single;
  }

  // Drills: maximal runs, counted once each.
  int i = 0;
  while (i + 5 < rows.length) {
    int j = i + 1;
    while (j < rows.length &&
        evenAlternating(i, j) &&
        rows[j].column != rows[j - 1].column &&
        (j < i + 2 || rows[j].column == rows[j - 2].column)) {
      j++;
    }
    if (j - i >= 6) {
      out.at[Pattern.drill]!.add(rows[i].beat);
      out.spans.add((Pattern.drill, rows[i].second, rows[j - 1].second));
      i = j;
    } else {
      i++;
    }
  }

  if (mode != Modes.singles) return;
  const sweeps = [
    [0, 1, 2, 3],
    [0, 2, 1, 3],
    [3, 2, 1, 0],
    [3, 1, 2, 0],
  ];
  for (int s = 0; s + 3 < rows.length; s++) {
    if (!evenAlternating(s, s + 3)) continue;
    final cols = [for (int k = s; k < s + 4; k++) rows[k].column];
    if (sweeps
        .any((w) => List.generate(4, (k) => w[k] == cols[k]).every((b) => b))) {
      out.at[Pattern.staircase]!.add(rows[s].beat);
      out.spans.add((Pattern.staircase, rows[s].second, rows[s + 3].second));
      s += 2; // a chained sweep shares its turning panel
    }
  }
}

/// What the song page shows for one chart.
class ChartAnalysis {
  final int steps;
  final FootworkCounts footwork;

  /// Arrows per beat grid: "4", "8", "12", "16", "24", "32", "other".
  final Map<String, int> rhythm;

  const ChartAnalysis({
    required this.steps,
    required this.footwork,
    required this.rhythm,
  });
}

const _grids = [4, 8, 12, 16, 24, 32];

String _gridOf(double beat) {
  for (final q in _grids) {
    final units = beat * q / 4;
    if ((units - units.roundToDouble()).abs() < 0.01) return "$q";
  }
  return "other";
}

/// [parity]'s solve of [notes] as footed rows, in time order. The engine's
/// rows are its non-mine notes grouped by millisecond.
List<FootedRow> footedRows(List<StepNote> notes, ParityResult parity) {
  final byTime = <double, List<StepNote>>{};
  for (final n in notes) {
    if (n.type == StepType.mine) continue;
    byTime
        .putIfAbsent((n.second * 1000).roundToDouble() / 1000, () => [])
        .add(n);
  }
  final times = byTime.keys.toList()..sort();
  final rows = <FootedRow>[];
  for (int r = 0; r < times.length && r < parity.stances.length; r++) {
    final group = byTime[times[r]]!;
    final steps = <int, ParityFoot>{
      for (final n in group)
        if (parity.feet[n] != null && parity.stances[r].stepped.contains(n.col))
          n.col: parity.feet[n]!,
    };
    if (steps.isEmpty) continue;
    rows.add(FootedRow(group.first.second, group.first.beat, steps));
  }
  return rows;
}

List<(double, double)> _holdSpans(List<StepNote> notes) => [
      for (final n in notes)
        if (n.isHold && n.endSecond != null) (n.second, n.endSecond!),
    ];

/// Counts every [Pattern] in [notes] as [parity] foots them.
FootworkCounts footworkOf(
        List<StepNote> notes, ParityResult parity, Modes mode) =>
    countFootwork(footedRows(notes, parity), mode,
        holdSpans: _holdSpans(notes));

/// Solves [notes] with [weights] and reads off every pattern.
ChartAnalysis analyseChart(List<StepNote> notes, Modes mode,
    {ParityWeights weights = ParityWeights.defaults}) {
  final parity = analyseParity(notes, mode, weights: weights);
  final rhythm = <String, int>{};
  for (final n in notes) {
    if (n.type == StepType.mine) continue;
    final g = _gridOf(n.beat);
    rhythm[g] = (rhythm[g] ?? 0) + 1;
  }
  final rows = footedRows(notes, parity);
  return ChartAnalysis(
    steps: rows.length,
    footwork: countFootwork(rows, mode, holdSpans: _holdSpans(notes)),
    rhythm: rhythm,
  );
}
