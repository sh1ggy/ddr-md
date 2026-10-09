/// Name: Pattern generator
/// Parent: tool (dev only)
/// Description: Runs [analyseChart] over every chart in assets/steps with the
/// shipped footing weights, ranks each pattern against charts of the same
/// style and level, and writes assets/patterns/<name>.json for the song page.
/// Rerun after the steps or the parity engine change.
///
///   flutter test tool/generate_patterns.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:ddr_md/models/pattern_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Entry {
  final String song;
  final Modes mode;
  final String difficulty;
  final int level;
  ChartPatterns chart;

  _Entry(this.song, this.mode, this.difficulty, this.level, this.chart);
}

/// Share (0-100) of [cohort] strictly below [value], ties counting half.
int _percentile(double value, List<double> cohort) {
  var below = 0.0;
  for (final v in cohort) {
    if (v < value) {
      below += 1;
    } else if (v == value) {
      below += 0.5;
    }
  }
  return (below * 100 / cohort.length).round();
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
          entries.add(_Entry(steps.name, mode, diff, level,
              ChartPatterns.fromAnalysis(analyseChart(chart.notes, mode))));
        }
      }
    }

    // Rank within the same style, a level either side.
    for (final e in entries) {
      final cohort = entries
          .where((o) => o.mode == e.mode && (o.level - e.level).abs() <= 1)
          .map((o) => o.chart)
          .toList();
      e.chart = e.chart.withPercentiles({
        for (final p in Pattern.values)
          p.name:
              _percentile(e.chart.rate(p), [for (final c in cohort) c.rate(p)]),
      });
    }

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
