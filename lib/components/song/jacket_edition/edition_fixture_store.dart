/// Name: EditionFixtureStore
/// Parent: EditionFixtureBrowser
/// Description: Isolated seeded score evidence and a lazy Cartesian fixture view.
library;

import 'dart:isolate';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks, kInGameDifficultyNames;
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/version_group.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'edition_model.dart';
import 'edition_rules.dart';

typedef EditionScoreRange = ({String label, Grade? grade, Score? play});
typedef EditionResultCase = ({String label, ClearLamp? lamp, Score? play});

/// Small axis tables represent every combination. Mixed-radix addressing
/// jumps to any row in constant time, rather than OFFSET-scanning millions.
class EditionFixtureSpace {
  EditionFixtureSpace();
  static const seedVersion = 1;
  Map<String, Score> loadedScores = {};
  late final List<EditionScoreRange> ranges = _ranges();
  late final List<EditionResultCase> results = _results();
  final flares = <String?>[null, ...kFlareRanks];
  final versions = <FlareGroup?>[null, ...FlareGroup.values];
  final levels = <int?>[null, for (var level = 1; level <= 20; level++) level];
  final difficulties = kInGameDifficultyNames.keys.toList(growable: false);
  final modes = Modes.values;
  List<int> get dimensions => [
        ranges.length,
        results.length,
        flares.length,
        versions.length,
        levels.length,
        difficulties.length,
        modes.length
      ];
  int get count => dimensions.fold(1, (a, b) => a * b);

  List<int> address(int index) {
    RangeError.checkValidIndex(index, this, 'index', count);
    final sizes = dimensions;
    final ids = List<int>.filled(sizes.length, 0);
    for (var i = sizes.length - 1; i >= 0; i--) {
      ids[i] = index % sizes[i];
      index ~/= sizes[i];
    }
    return ids;
  }

  int indexOf(List<int> ids) {
    final sizes = dimensions;
    if (ids.length != sizes.length) {
      throw ArgumentError('Seven axis IDs required');
    }
    var index = 0;
    for (var i = 0; i < sizes.length; i++) {
      RangeError.checkValueInInterval(ids[i], 0, sizes[i] - 1, 'axis $i');
      index = index * sizes[i] + ids[i];
    }
    return index;
  }

  List<int> get showcaseIndices {
    final specimens = <(Grade?, int)>[
      (null, 0),
      for (final grade in [
        Grade.e,
        Grade.d,
        Grade.c,
        Grade.b,
        Grade.a,
        Grade.aa,
        Grade.aaPlus
      ])
        (
          grade,
          grade == Grade.e
              ? results.indexWhere((r) => r.lamp == ClearLamp.failed)
              : 0
        ),
      for (final perfects in [10, 1, 9])
        (
          Grade.aaa,
          results.indexWhere((r) =>
              r.play?.completionLamp == ClearLamp.pfc &&
              r.play?.perfect == perfects)
        ),
      (
        Grade.aaa,
        results.indexWhere((r) => r.play?.completionLamp == ClearLamp.mfc)
      ),
    ];
    final indices = <int>[];
    for (var i = 0; i < specimens.length; i++) {
      final (grade, result) = specimens[i];
      indices.add(indexOf([
        ranges.indexWhere((r) => r.grade == grade),
        result,
        i == specimens.length - 1 ? flares.indexOf('EX') : 0,
        versions.indexOf(FlareGroup.gold),
        levels.indexOf(17),
        difficulties.indexOf('challenge'),
        0
      ]));
    }
    return indices;
  }

  EditionFacts factsAt(int index) {
    final a = address(index), range = ranges[a[0]], result = results[a[1]];
    final gradePlay = loadedScores[range.play?.id] ?? range.play;
    final precisionPlay = loadedScores[result.play?.id] ?? result.play;
    return EditionFacts(
        chart: (
          song: 'edition-fixture-$index',
          mode: modes[a[6]].name,
          difficulty: difficulties[a[5]]
        ),
        level: levels[a[4]],
        version: versions[a[3]],
        grade: range.grade == Grade.e
            ? Grade.e
            : gradePlay?.score == null
                ? null
                : gradeForScore(gradePlay!.score!),
        flare: flares[a[2]],
        score: range.grade == Grade.e ? null : gradePlay?.score,
        lamp: result.lamp,
        precision:
            precisionPlay == null ? null : precisionForPlay(precisionPlay));
  }

  String labelAt(int index) {
    final a = address(index);
    return '${ranges[a[0]].label} • ${results[a[1]].label}';
  }

  static Score _play(String id,
          {int? score,
          int? perfect,
          int? marvelous,
          int? great,
          int? good,
          int? miss,
          ClearLamp? completion}) =>
      Score(
          id: 'edition-lab:$id',
          playedAt: '2026-01-01T12:00:00',
          source: ScoreSource.loadImage,
          songTitle: 'Edition lab fixture',
          mode: Modes.singles,
          difficulty: 'EXPERT',
          score: score,
          marvelous: marvelous,
          perfect: perfect,
          great: great,
          good: good,
          miss: miss,
          completionLamp: completion);

  List<EditionScoreRange> _ranges() {
    final scores = <int>{0, 1, 999990, 1000000};
    for (final grade in Grade.values.where((g) => g != Grade.e)) {
      for (final delta in [-1, 0, 1]) {
        final score = grade.minScore + delta;
        if (score >= 0 && score <= 1000000) scores.add(score);
      }
    }
    final ordered = scores.toList()..sort();
    return [
      (label: 'No score evidence', grade: null, play: null),
      (
        label: 'Failed / E',
        grade: Grade.e,
        play: _play('failed', score: 500000, completion: ClearLamp.failed)
      ),
      for (final score in ordered)
        (
          label: '${gradeForScore(score).label} • $score',
          grade: gradeForScore(score),
          play: _play('score-$score', score: score)
        ),
    ];
  }

  List<EditionResultCase> _results() => [
        (label: 'No result evidence', lamp: null, play: null),
        for (final lamp in ClearLamp.values)
          (
            label: 'Independent ${lamp.name.toUpperCase()}',
            lamp: lamp,
            play: null
          ),
        for (final perfects in [0, 1, 9, 10])
          (
            label: 'Verified PFC • $perfects Perfects',
            lamp: ClearLamp.pfc,
            play: _play('pfc-$perfects',
                score: 1000000 - perfects * 10,
                marvelous: 400,
                perfect: perfects,
                great: 0,
                good: 0,
                miss: 0,
                completion: ClearLamp.pfc)
          ),
        (
          label: 'Verified MFC',
          lamp: ClearLamp.mfc,
          play: _play('mfc',
              score: 1000000,
              marvelous: 400,
              perfect: 0,
              great: 0,
              good: 0,
              miss: 0,
              completion: ClearLamp.mfc)
        ),
        (
          label: 'Legacy tap-only • no completion proof',
          lamp: ClearLamp.pfc,
          play: _play('legacy',
              score: 999990,
              marvelous: 400,
              perfect: 1,
              great: 0,
              good: 0,
              miss: 0)
        ),
        (
          label: 'Partial OCR • missing Perfects',
          lamp: ClearLamp.pfc,
          play: _play('partial',
              score: 999990,
              marvelous: 400,
              great: 0,
              good: 0,
              miss: 0,
              completion: ClearLamp.pfc)
        ),
        (
          label: 'Tap-only MFC • hold/shock result unknown',
          lamp: ClearLamp.clear,
          play: _play('hold-unknown',
              score: 990000,
              marvelous: 400,
              perfect: 0,
              great: 0,
              good: 0,
              miss: 0)
        ),
        (
          label: 'Contradictory PFC • Miss present',
          lamp: ClearLamp.pfc,
          play: _play('contradictory',
              score: 990000,
              marvelous: 400,
              perfect: 1,
              great: 0,
              good: 0,
              miss: 1,
              completion: ClearLamp.pfc)
        ),
      ];

  /// Pure validation runs away from the UI isolate. It never loads artwork
  /// or constructs a widget, and retains only counters rather than recipes.
  Future<Map<String, int>> validateAll() {
    final space = this;
    return Isolate.run(() {
      var valid = 0;
      final total = space.count;
      for (var i = 0; i < total; i++) {
        final facts = space.factsAt(i);
        final recipe = resolveEdition(facts);
        if (recipe.tier != editionTier(facts.level) ||
            recipe.finish != finishFor(facts.grade) ||
            (recipe.secret && recipe.frame != EditionFrame.gold) ||
            (recipe.ex != (facts.flare == 'EX'))) {
          throw StateError('Fixture $i failed resolution');
        }
        valid++;
      }
      return {'validated': valid, 'seedVersion': seedVersion};
    });
  }
}

class EditionFixtureStore {
  EditionFixtureStore._(this.db, this.space);
  final Database db;
  final EditionFixtureSpace space;
  static Future<EditionFixtureStore> open({String? databasePath}) async {
    // Always a dedicated file and direct handle. Never becomes the app's
    // DatabaseProvider.db, and no CloudSync instance is given this handle.
    final file = databasePath ??
        path.join(await getDatabasesPath(), 'jacket_edition_lab_v1.db');
    final db = await DatabaseProvider.open(file);
    final space = EditionFixtureSpace();
    try {
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final range in space.ranges) {
          if (range.play != null) {
            batch.insert('scores', range.play!.toMap(),
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        for (final result in space.results) {
          if (result.play != null) {
            batch.insert('scores', result.play!.toMap(),
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        for (final table in [
          'range',
          'result',
          'flare',
          'version',
          'level',
          'difficulty',
          'mode'
        ]) {
          batch.execute(
              'CREATE TABLE IF NOT EXISTS edition_$table(id INTEGER PRIMARY KEY, value TEXT, label TEXT)');
        }
        final axes = <List<(String?, String)>>[
          [for (final r in space.ranges) (r.grade?.name, r.label)],
          [for (final r in space.results) (r.lamp?.name, r.label)],
          [for (final f in space.flares) (f, f ?? 'Unknown')],
          [for (final v in space.versions) (v?.name, v?.name ?? 'Neutral')],
          [
            for (final l in space.levels)
              (l?.toString(), l?.toString() ?? 'Unknown')
          ],
          [for (final d in space.difficulties) (d, d)],
          [for (final m in space.modes) (m.name, m.name)],
        ];
        const tables = [
          'range',
          'result',
          'flare',
          'version',
          'level',
          'difficulty',
          'mode'
        ];
        for (var a = 0; a < tables.length; a++) {
          for (var i = 0; i < axes[a].length; i++) {
            batch.insert('edition_${tables[a]}',
                {'id': i, 'value': axes[a][i].$1, 'label': axes[a][i].$2},
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        batch.execute(
            'CREATE VIEW IF NOT EXISTS edition_combinations AS SELECT '
            'g.id AS rangeId, r.id AS resultId, f.id AS flareId, v.id AS versionId, '
            'l.id AS levelId, d.id AS difficultyId, m.id AS modeId '
            'FROM edition_range g CROSS JOIN edition_result r CROSS JOIN edition_flare f '
            'CROSS JOIN edition_version v CROSS JOIN edition_level l '
            'CROSS JOIN edition_difficulty d CROSS JOIN edition_mode m');
        await batch.commit(noResult: true);
      });
      space.loadedScores = {
        for (final row in await db.query('scores'))
          row['id'] as String: Score.fromMap(row)
      };
      return EditionFixtureStore._(db, space);
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  /// Read actual seeded rows by indexed axis IDs. There is no huge OFFSET
  /// scan and no materialized table containing every permutation.
  Future<List<({int index, EditionFacts facts, String label})>> page(int start,
      {int size = 12}) async {
    RangeError.checkValidIndex(start, space, 'start', space.count);
    if (size < 1 || size > 24) throw RangeError.range(size, 1, 24, 'size');
    final indices = [
      for (var i = start; i < space.count && i < start + size; i++) i
    ];
    return _read(indices);
  }

  Future<List<({int index, EditionFacts facts, String label})>> showcase() =>
      _read(space.showcaseIndices);

  Future<List<({int index, EditionFacts facts, String label})>> _read(
      List<int> indices) async {
    final batch = db.batch();
    for (final i in indices) {
      batch.rawQuery(
          'SELECT * FROM edition_combinations WHERE rangeId=? AND resultId=? '
          'AND flareId=? AND versionId=? AND levelId=? AND difficultyId=? AND modeId=?',
          space.address(i));
    }
    final rows = await batch.commit();
    return [
      for (var i = 0; i < indices.length; i++)
        if ((rows[i] as List).length == 1)
          (
            index: indices[i],
            facts: space.factsAt(indices[i]),
            label: space.labelAt(indices[i])
          )
    ];
  }

  Future<void> close() => db.close();
}
