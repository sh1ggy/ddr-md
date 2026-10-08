import 'dart:convert';
import 'dart:io';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/parity_labels.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checks the unpinned solve against every hand-set foot exported to
/// test/parity_labels/ (see docs/parity/labelling.md).
void main() {
  test('solve agrees with hand-labelled footing', () {
    final dir = Directory('test/parity_labels');
    final files = dir.existsSync()
        ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];
    final problems = <String>[];
    var checked = 0;
    for (final file in files) {
      final chart = ChartLabels.fromJson(json.decode(file.readAsStringSync()));
      final ref = chart.ref;
      final song = SongSteps.fromJson(json.decode(
          File('assets/steps/${ref.song}.json').readAsStringSync()));
      final mode = ref.mode == 'dp' ? Modes.doubles : Modes.singles;
      final notes = song.chartFor(mode, ref.difficulty)!.notes;
      final name = '${ref.song} [${ref.mode} ${ref.difficulty}]';
      if (chartHash(notes) != chart.chartHash) {
        problems.add('$name: chart changed since labelling, labels are stale');
        continue;
      }
      checked += chart.pins.length;
      final wrong = disagreements(
          chart.pins, notes, analyseParity(notes, mode).feet);
      for (final (b, c, f) in wrong) {
        problems.add('$name beat $b col $c: labelled ${f.name}');
      }
    }
    expect(problems, isEmpty,
        reason: '${problems.length} of $checked labelled notes disagree:\n'
            '${problems.join('\n')}');
  });
}
