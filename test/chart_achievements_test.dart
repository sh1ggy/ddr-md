import 'dart:io';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Score play(
        {int? perfect = 1,
        int? marvelous = 400,
        int? great = 0,
        int? good = 0,
        int? miss = 0,
        ClearLamp? lamp = ClearLamp.pfc,
        String id = 'play'}) =>
    Score(
        id: id,
        playedAt: '2026-10-30',
        source: ScoreSource.camera,
        songTitle: 'Test',
        mode: Modes.singles,
        difficulty: 'EXPERT',
        score: 999990,
        marvelous: marvelous,
        perfect: perfect,
        great: great,
        good: good,
        miss: miss,
        completionLamp: lamp);

void main() {
  test('SDP requires 1–9 Perfects on one proven PFC play', () {
    for (final count in [1, 9]) {
      expect(precisionForPlay(play(perfect: count))?.award, PrecisionAward.sdp);
    }
    for (final count in [0, 10]) {
      expect(precisionForPlay(play(perfect: count))?.award, PrecisionAward.pfc);
    }
    for (final count in [null, -1]) {
      expect(precisionForPlay(play(perfect: count)), isNull);
    }
    expect(precisionForPlay(play(lamp: null)), isNull);
    expect(precisionForPlay(play(lamp: ClearLamp.clear)), isNull);
    expect(precisionForPlay(play(good: 1)), isNull);
    expect(precisionForPlay(play(great: 1)), isNull);
    expect(precisionForPlay(play(miss: 1)), isNull);
    expect(precisionForPlay(play(marvelous: null)), isNull);
    expect(precisionForPlay(play(great: null)), isNull);
    expect(precisionForPlay(play(marvelous: 0, perfect: 0)), isNull);
    expect(judgedTapTier(0, 0, 0, 0, 0), isNull);
    expect(judgedTapTier(400, 1, 0, 0, 0), FullComboTier.pfc);
  });
  test(
      'unrelated bests never manufacture precision; MFC wins with row provenance',
      () {
    final independent = [
      play(lamp: null, id: 'counts'),
      play(perfect: null, id: 'lamp')
    ];
    expect(bestPrecision(independent), isNull);
    expect(precisionForPlay(play(lamp: ClearLamp.mfc, perfect: 1)), isNull);
    final mfc = play(lamp: ClearLamp.mfc, perfect: 0, id: 'mfc');
    expect(bestPrecision([play(id: 'sdp'), mfc]),
        (award: PrecisionAward.mfc, sourceRowId: 'mfc', perfects: 0));
    expect(bestPrecision([play(id: 'b'), play(id: 'a')])?.sourceRowId, 'a');
  });
  test('completion round-trips, unknown values stay unknown, edit can clear it',
      () {
    final s = play();
    expect(Score.fromMap(s.toMap()).completionLamp, ClearLamp.pfc);
    expect(Score.fromMap({...s.toMap(), 'completionLamp': null}).completionLamp,
        isNull);
    expect(
        Score.fromMap({...s.toMap(), 'completionLamp': 'future'})
            .completionLamp,
        isNull);
    expect(s.copyWith(clearCompletionLamp: true).completionLamp, isNull);
    expect(s.copyWith(score: 999980).completionLamp, ClearLamp.pfc);
  });
  test('v16 additive migration preserves legacy rows and sync triggers',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('edition_migration');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/data.db';
    final db = await DatabaseProvider.open(path);
    final legacy = play(lamp: null);
    await db.insert('scores', legacy.toMap());
    await db.execute('ALTER TABLE scores DROP COLUMN completionLamp');
    await db.setVersion(16);
    await db.close();
    final migrated = await DatabaseProvider.open(path);
    addTearDown(migrated.close);
    final row = (await migrated.query('scores')).single;
    expect(row['id'], legacy.id);
    expect(row['completionLamp'], isNull);
    await migrated.delete('sync_outbox');
    await migrated.update('scores', {'completionLamp': 'pfc'},
        where: 'id = ?', whereArgs: [legacy.id]);
    expect((await migrated.query('sync_outbox')).single['t'], 'scores');
    expect(
        Score.fromMap((await migrated.query('scores')).single).completionLamp,
        ClearLamp.pfc);
    expect(await migrated.getVersion(), 19);
  });
}
