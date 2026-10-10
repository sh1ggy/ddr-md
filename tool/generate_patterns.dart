/// Name: Pattern generator
/// Parent: tool (dev only)
/// Description: Runs [analyseChart] over every chart in assets/steps with the
/// shipped footing weights and writes assets/patterns/<name>.json for the song
/// page, plus assets/pattern_levels.json, the table each chart is ranked
/// against at its level. Rerun after the steps or the parity engine change.
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
  final ChartPatterns chart;

  _Entry(this.song, this.mode, this.difficulty, this.chart);
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
                  analyseChart(chart.notes, mode), level)));
        }
      }
    }

    File('assets/pattern_levels.json').writeAsStringSync(jsonEncode(
        PatternLevels.of([for (final e in entries) (e.mode, e.chart)])));

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
