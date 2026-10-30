/// Name: Pattern generator
/// Parent: tool (dev only)
/// Description: Runs [analyseChart] over every chart in assets/steps with the
/// shipped footing weights and writes assets/patterns/<name>.json for the song
/// page, plus assets/pattern_levels.json, the table each chart is ranked
/// against at its level, with an example moment per chart category. Rerun after the steps or the parity engine change.
///
///   flutter test tool/generate_patterns.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:ddr_md/models/pattern_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Entry {
  final String song;
  final Modes mode;
  final String difficulty;
  final ChartPatterns chart;
  final List<StepNote> notes;
  final SongInfo info;

  _Entry(this.song, this.mode, this.difficulty, this.chart, this.notes,
      this.info);
}

/// Seconds of chart each category's example loops.
const _momentLength = 6.0;

/// When [e] shows [c]: the seconds the category's measure counts.
List<double> _evidence(_Entry e, ChartCategory c) {
  final taps = [
    for (final n in e.notes)
      if (n.type != StepType.mine) n
  ];
  final rows = <double, int>{};
  for (final n in taps) {
    rows.update(n.second, (v) => v + 1, ifAbsent: () => 1);
  }
  final secondOf = {for (final n in taps) n.beat: n.second};
  List<double> at(List<Pattern> ps) => [
        for (final p in ps)
          for (final b in e.chart.at[p]!)
            if (secondOf[b] case final s?) s
      ];
  final chart = e.info.charts.firstOrNull;
  return switch (c) {
    ChartCategory.jumps => [
        for (final r in rows.entries)
          if (r.value >= 2) r.key
      ],
    ChartCategory.jack => at([Pattern.jack, Pattern.drill]),
    ChartCategory.crossover => at([Pattern.crossover]),
    ChartCategory.footswitch => at([Pattern.footswitch, Pattern.sideswitch]),
    ChartCategory.bracket => at([Pattern.bracket]),
    ChartCategory.freeze => [
        for (final n in taps)
          if (n.isHold && n.endSecond != null)
            for (var t = n.second; t < n.endSecond!; t += 0.25) t
      ],
    ChartCategory.swing => [
        for (final n in taps)
          if (![4, 8, 16].any((q) {
            final u = n.beat * q / 4;
            return (u - u.roundToDouble()).abs() < 0.01;
          }))
            n.second
      ],
    ChartCategory.gimmick when chart != null => [
        for (final s in chart.stops) s.st,
        for (final b in chart.bpms)
          if (b.val != chart.dominantBpm) b.st,
      ],
    _ => rows.keys.toList(),
  };
}

/// The [_momentLength] window holding the most of [times], as (from, to).
(double, double)? _busiest(List<double> times) {
  if (times.isEmpty) return null;
  times.sort();
  var best = 0, start = 0, j = 0;
  for (int i = 0; i < times.length; i++) {
    while (times[j] < times[i] - _momentLength) {
      j++;
    }
    if (i - j + 1 > best) {
      best = i - j + 1;
      start = j;
    }
  }
  final from = times[start];
  return (from, from + _momentLength);
}

/// Per category, the SP chart at level [_exampleLevels] that leads with it
/// most clearly, and its stretch that shows it best.
const _exampleLevels = (13, 17);

List<Map<String, dynamic>> _examples(
    List<_Entry> entries, PatternLevels levels) {
  final best = <ChartCategory, (_Entry, int)>{};
  for (final e in entries) {
    if (e.mode != Modes.singles ||
        e.chart.level < _exampleLevels.$1 ||
        e.chart.level > _exampleLevels.$2) {
      continue;
    }
    final ranked = levels.rank(e.mode, e.chart);
    final c = ranked.primaryCategory;
    if (c == null || c == ChartCategory.balanced) continue;
    final lead = ranked.categoryPercentiles[c]! -
        [
          for (final k in kRankedCategories)
            if (k != c) ranked.categoryPercentiles[k]!
        ].reduce(max);
    if (lead > (best[c]?.$2 ?? -1)) best[c] = (e, lead);
  }
  return [
    for (final c in kRankedCategories)
      if (best[c] case (final e, _))
        if (_busiest(_evidence(e, c)) case (final from, final to))
          {
            "category": c.name,
            "song": e.song,
            "difficulty": e.difficulty,
            "from": (from * 1000).roundToDouble() / 1000,
            "to": (to * 1000).roundToDouble() / 1000,
          }
  ];
}

/// Share of the song off its main BPM (capped at half) blended with how many
/// stops it has (capped at 20), 0-1.
double _gimmick(SongInfo info) {
  if (info.charts.isEmpty) return 0;
  final c = info.charts.first;
  final total = c.bpms.fold(0.0, (a, b) => a + b.ed - b.st);
  if (total <= 0 || c.dominantBpm == 0) return 0;
  final off = c.bpms
          .where((b) => (b.val - c.dominantBpm).abs() / c.dominantBpm > 0.05)
          .fold(0.0, (a, b) => a + b.ed - b.st) /
      total;
  return min(off, 0.5) / 0.5 * 0.6 +
      min(log(1 + c.stops.length) / log(21), 1) * 0.4;
}

void main() {
  test('generate assets/patterns', () {
    final out = Directory('assets/patterns')..createSync();
    final entries = <_Entry>[];
    final clock = Stopwatch()..start();

    for (final file in Directory('assets/steps').listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final steps = SongSteps.fromJson(jsonDecode(file.readAsStringSync()));
      final songFile = File('assets/songs/${steps.name}.json');
      if (!songFile.existsSync()) continue;
      final info = SongInfo.fromJson(jsonDecode(songFile.readAsStringSync()));
      for (final mode in Modes.values) {
        final levels =
            (mode == Modes.singles ? info.singles : info.doubles).toJson();
        final charts = mode == Modes.singles ? steps.singles : steps.doubles;
        for (final MapEntry(key: diff, value: chart) in charts.entries) {
          final level = levels[diff] as int?;
          if (level == null || chart.notes.isEmpty) continue;
          entries.add(_Entry(
              steps.name,
              mode,
              diff,
              ChartPatterns.fromAnalysis(
                  analyseChart(chart.notes, mode), level,
                  gimmick: _gimmick(info)),
              chart.notes,
              info));
        }
      }
    }

    final levels =
        PatternLevels.of([for (final e in entries) (e.mode, e.chart)]);
    File('assets/pattern_levels.json').writeAsStringSync(jsonEncode(
        {...levels.toJson(), "examples": _examples(entries, levels)}));

    final bySong = <String, Map<Modes, Map<String, ChartPatterns>>>{};
    for (final e in entries) {
      bySong.putIfAbsent(e.song, () => {for (final m in Modes.values) m: {}})[
          e.mode]![e.difficulty] = e.chart;
    }
    for (final MapEntry(key: name, value: modes) in bySong.entries) {
      final song = SongPatterns(
          singles: modes[Modes.singles]!, doubles: modes[Modes.doubles]!);
      File('${out.path}/$name.json').writeAsStringSync(jsonEncode(song));
    }

    // ignore: avoid_print
    print('${entries.length} charts, ${bySong.length} songs in '
        '${clock.elapsed.inSeconds}s');
  }, timeout: Timeout.none);
}
