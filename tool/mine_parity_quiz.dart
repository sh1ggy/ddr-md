/// Name: Parity quiz miner
/// Parent: tool (dev only)
/// Description: Finds real-chart moments where the parity engine is least sure
/// between two footings, for each divisive pattern: candidates worth a look in
/// the footing editor, or for tuning the defaults. Each candidate is solved free
/// and with its key note forced to the other foot; the smaller the cost gap, the
/// more divisive the moment.
///
///   QUIZ_OUT=quiz_candidates.json flutter test tool/mine_parity_quiz.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _l = ParityFoot.left, _r = ParityFoot.right;
ParityFoot _flip(ParityFoot? f) => f == _l ? _r : _l;

/// One chart's rows (non-mine notes sharing a second) and its free solve.
class _Chart {
  final List<StepNote> notes;
  final List<List<StepNote>> rows;
  final ParityResult free;
  final List<StepNote> holds;

  _Chart(this.notes)
      : rows = _rows(notes),
        free = analyseParity(notes, Modes.singles),
        holds = notes.where((n) => n.isHold && n.endSecond != null).toList();

  static List<List<StepNote>> _rows(List<StepNote> notes) {
    final byTime = <double, List<StepNote>>{};
    for (final n in notes) {
      if (n.type != StepType.mine) byTime.putIfAbsent(n.second, () => []).add(n);
    }
    final secs = byTime.keys.toList()..sort();
    return [for (final s in secs) byTime[s]!];
  }

  double sec(int i) => rows[i].first.second;
  double gap(int i) => sec(i) - sec(i - 1);
  bool single(int i) => rows[i].length == 1;
  StepNote one(int i) => rows[i].first;
  ParityFoot? foot(StepNote n) => free.feet[n];
  bool held(int i) => holds.any((h) => h.second < sec(i) && sec(i) < h.endSecond!);

  ParityStance stanceAt(int i) =>
      free.stances.firstWhere((s) => s.second == sec(i));
}

/// Every side arrow in rows [from]..[to] on its own side's foot: the
/// face-forward reading a spin or slow crossover is weighed against.
Map<StepNote, ParityFoot> _faceForward(_Chart c, int from, int to) => {
      for (int i = from; i <= to; i++)
        for (final n in c.rows[i])
          if (n.col == 0) n: _l else if (n.col == 3) n: _r
    };

/// A pattern names the rows worth asking about and the alternative footing.
typedef _Alt = (int row, List<Map<StepNote, ParityFoot>> alternatives);

final Map<String, Iterable<_Alt> Function(_Chart)> _patterns = {
  // A repeated Up/Down at 8ths-16ths: jack it or switch feet.
  'jack-vs-footswitch': (c) sync* {
    for (int i = 1; i < c.rows.length; i++) {
      if (!c.single(i) || !c.single(i - 1) || c.held(i)) continue;
      final a = c.one(i - 1), b = c.one(i);
      if (a.col != b.col || (b.col != 1 && b.col != 2)) continue;
      if (c.gap(i) < 0.1 || c.gap(i) > 0.26) continue;
      yield (i, [{b: _flip(c.foot(b))}]);
    }
  },
  // A slow change of arrow: take it with the same foot or cross over.
  'slow-doublestep-vs-crossover': (c) sync* {
    for (int i = 1; i < c.rows.length; i++) {
      if (!c.single(i) || !c.single(i - 1) || c.held(i)) continue;
      final a = c.one(i - 1), b = c.one(i);
      if (a.col == b.col || c.gap(i) < 0.28) continue;
      final s = c.stanceAt(i);
      final crossed = s.leftHeel == 3 || s.rightHeel == 0;
      if (crossed) {
        yield (i, [_faceForward(c, i, (i + 3).clamp(0, c.rows.length - 1))]);
      } else if (c.foot(a) == c.foot(b)) {
        yield (i, [{b: _flip(c.foot(b))}]);
      }
    }
  },
  // A fast change of arrow taken with the same foot: doublestep it, or cross
  // over to keep alternating.
  'doublestep-vs-crossover': (c) sync* {
    for (int i = 1; i < c.rows.length; i++) {
      if (!c.single(i) || !c.single(i - 1) || c.held(i)) continue;
      final a = c.one(i - 1), b = c.one(i);
      if (a.col == b.col || c.gap(i) >= 0.28) continue;
      if (c.foot(a) == c.foot(b)) yield (i, [{b: _flip(c.foot(b))}]);
    }
  },
  // One foot travelling Up <-> Down across the middle.
  'candle': (c) sync* {
    final last = <ParityFoot, int>{};
    for (int i = 0; i < c.rows.length; i++) {
      if (!c.single(i)) {
        last.clear();
        continue;
      }
      final n = c.one(i);
      final f = c.foot(n);
      if (f == null) continue;
      final prev = last[f];
      if (prev != null && prev == i - 2 && (n.col == 1 || n.col == 2)) {
        final p = c.one(prev).col;
        if ((p == 1 || p == 2) && p != n.col) yield (i, [{n: _flip(f)}]);
      }
      last[f] = i;
    }
  },
  // Both feet fully swapped sides: spin through or reset.
  'spin': (c) sync* {
    bool was = false;
    for (int i = 0; i < c.rows.length; i++) {
      final s = c.stanceAt(i);
      final swapped = s.leftHeel == 3 && s.rightHeel == 0;
      if (swapped && !was && c.single(i)) {
        yield (i, [_faceForward(c, i, (i + 3).clamp(0, c.rows.length - 1))]);
      }
      was = swapped;
    }
  },
  // A side + centre chord with a quick follow-up: bracket it or jump.
  'bracket-vs-jump': (c) sync* {
    for (int i = 0; i + 1 < c.rows.length; i++) {
      final row = c.rows[i];
      if (row.length != 2 || c.gap(i + 1) > 0.3) continue;
      final side = row.where((n) => n.col == 0 || n.col == 3).firstOrNull;
      final centre = row.where((n) => n.col == 1 || n.col == 2).firstOrNull;
      if (side == null || centre == null) continue;
      // Asked as all three readings: bracket, plain jump, crossed jump.
      final sideFoot = side.col == 0 ? _l : _r;
      final readings = [
        {side: sideFoot, centre: sideFoot},
        {side: sideFoot, centre: _flip(sideFoot)},
        {side: _flip(sideFoot), centre: sideFoot},
      ];
      yield (
        i,
        [
          for (final r in readings)
            if (r[side] != c.foot(side) || r[centre] != c.foot(centre)) r
        ]
      );
    }
  },
  // A held centre arrow with side taps around it: which foot holds.
  'hold-with-taps': (c) sync* {
    for (int i = 0; i < c.rows.length; i++) {
      for (final h in c.rows[i]) {
        if (!h.isHold || (h.col != 1 && h.col != 2) || h.endSecond == null) {
          continue;
        }
        final taps = c.notes.where((n) =>
            n.second > h.second &&
            n.second < h.endSecond! &&
            n.type != StepType.mine &&
            (n.col == 0 || n.col == 3));
        if (taps.length >= 2) yield (i, [{h: _flip(c.foot(h))}]);
      }
    }
  },
  // L D R L U R and its mirrors/inversions: walk the lateral or reset.
  'lateral': (c) sync* {
    const shapes = [
      [0, 1, 3, 0, 2, 3],
      [0, 2, 3, 0, 1, 3],
      [3, 1, 0, 3, 2, 0],
      [3, 2, 0, 3, 1, 0],
    ];
    for (int i = 5; i < c.rows.length; i++) {
      if (!List.generate(6, (k) => c.single(i - 5 + k)).every((x) => x)) {
        continue;
      }
      if (List.generate(5, (k) => c.gap(i - 4 + k)).any((g) => g > 0.3)) {
        continue;
      }
      final cols = List.generate(6, (k) => c.one(i - 5 + k).col);
      if (!shapes.any((s) => List.generate(6, (k) => s[k] == cols[k]).every((x) => x))) {
        continue;
      }
      final key = c.one(i - 2);
      yield (i - 2, [{key: _flip(c.foot(key))}]);
    }
  },
};

void main() {
  test('mine parity quiz candidates', () {
    final found = <String, List<Map<String, dynamic>>>{
      for (final p in _patterns.keys) p: []
    };
    final files = Directory('assets/steps').listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final song = SongSteps.fromJson(json.decode(f.readAsStringSync()));
      for (final MapEntry(key: diff, value: chart) in song.singles.entries) {
        if (chart.notes.isEmpty || diff == 'beginner') continue;
        final c = _Chart(chart.notes);
        for (final MapEntry(key: name, value: find) in _patterns.entries) {
          // Footwork choices read best on mid-level charts; only the slow
          // doublestep is really a slow-chart question.
          if (diff == 'easy' && name != 'slow-doublestep-vs-crossover') continue;
          // A few per chart keeps the run short and the pool varied.
          for (final (row, alternatives) in find(c).take(3)) {
            final from = (row - 4).clamp(0, c.rows.length - 1);
            final to = (row + 3).clamp(0, c.rows.length - 1);
            // The lead-in keeps the engine's feet, so an alternative can't
            // just be the same footing mirrored from the start.
            final lead = {
              for (int i = from; i < row; i++)
                for (final n in c.rows[i])
                  if (c.foot(n) case final f?) n: f,
            };
            final alts = <ParityResult>[];
            for (final pins in alternatives) {
              final alt = analyseParity(chart.notes, Modes.singles,
                  pins: {...lead, ...pins});
              final differs = [
                for (int i = row; i <= to; i++)
                  for (final n in c.rows[i]) alt.feet[n] != c.foot(n)
              ].any((x) => x);
              if (alt.cost > c.free.cost && differs) alts.add(alt);
            }
            if (alts.isEmpty) continue;
            final delta = alts.map((a) => a.cost - c.free.cost).reduce(
                (a, b) => a < b ? a : b);
            // An exact tie is settled by the rest of the chart, not by style,
            // so it illustrates nothing.
            if (delta < 1) continue;
            // Holds clutter a moment unless they're what it's about.
            final window = [for (int i = from; i <= to; i++) ...c.rows[i]];
            if (name != 'hold-with-taps' && window.any((n) => n.isHold)) {
              continue;
            }
            found[name]!.add({
              'song': song.name,
              'difficulty': diff,
              'second': c.sec(row),
              'delta': delta,
              'rows': [
                for (int i = from; i <= to; i++)
                  {
                    's': c.sec(i),
                    'key': i == row,
                    'notes': [
                      for (final n in c.rows[i])
                        {
                          'b': n.beat,
                          'c': n.col,
                          'hold': n.isHold,
                          if (n.endSecond != null) 'e': n.endSecond,
                          'a': c.foot(n) == _l ? 'L' : 'R',
                          'alts': [
                            for (final alt in alts)
                              alt.feet[n] == _l ? 'L' : 'R'
                          ],
                        }
                    ],
                  }
              ],
            });
          }
        }
      }
    }
    // Most divisive first, one moment per song.
    final out = <String, List<Map<String, dynamic>>>{};
    for (final MapEntry(key: name, value: list) in found.entries) {
      list.sort((a, b) => (a['delta'] as double).compareTo(b['delta'] as double));
      final songs = <String>{};
      out[name] = [
        for (final m in list)
          if (songs.add(m['song'] as String)) m
      ].take(5).toList();
    }
    File(Platform.environment['QUIZ_OUT']!).writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert(out));
  }, timeout: Timeout.none);
}
