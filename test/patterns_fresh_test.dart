/// Name: PatternsFreshTest
/// Description: The generated assets/patterns still match what the current
/// parity engine and counting rules produce, on a sample of songs. Skipped on
/// a fresh clone, where the generated assets are absent.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:ddr_md/models/pattern_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final present = Directory('assets/patterns').existsSync();
  test(
      'assets/patterns is current (else: flutter test tool/generate_patterns.dart)',
      () {
    final steps = Directory('assets/steps')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in [for (int i = 0; i < steps.length; i += 40) steps[i]]) {
      final song = SongSteps.fromJson(jsonDecode(file.readAsStringSync()));
      final raw = jsonDecode(
          File('assets/patterns/${song.name}.json').readAsStringSync());
      expect(raw['schema'], kPatternsSchema, reason: song.name);
      final shipped = SongPatterns.fromJson(raw);
      for (final mode in Modes.values) {
        final charts = mode == Modes.singles ? song.singles : song.doubles;
        for (final MapEntry(key: diff, value: chart) in charts.entries) {
          final stored = shipped.chartFor(mode, diff);
          if (stored == null) continue;
          expect(
              ChartPatterns.fromAnalysis(analyseChart(chart.notes, mode))
                  .counts,
              stored.counts,
              reason: '${song.name} ${mode.name} $diff');
        }
      }
    }
  }, skip: present ? false : 'assets/patterns not generated');
}
