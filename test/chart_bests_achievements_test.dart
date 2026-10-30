import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('local changes and simultaneous SP/DP refresh evidence independently',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await DatabaseProvider.open(inMemoryDatabasePath);
    addTearDown(db.close);
    await DatabaseProvider.withTestDatabase(db, () async {
      final song = SongInfo(
          ssc: false,
          version: 'WORLD',
          name: 'test',
          title: 'Test',
          titletranslit: 'Test',
          artist: '',
          artisttranslit: '',
          songLength: 100,
          perChart: false,
          singles: Difficulty(hard: 16),
          doubles: Difficulty(hard: 17),
          radarSingles: const {},
          radarDoubles: const {},
          singlesNotecounts: Difficulty(),
          doublesNotecounts: Difficulty(),
          charts: const []);
      Songs.list = [song];
      final s = Score(
          id: 'local',
          playedAt: '2026-10-30',
          source: ScoreSource.camera,
          songTitle: 'Test',
          mode: Modes.singles,
          difficulty: 'EXPERT',
          score: 999990,
          marvelous: 400,
          perfect: 1,
          great: 0,
          good: 0,
          miss: 0);
      await DatabaseProvider.addScore(s);
      final r = ScoreRecord(
          id: 'record',
          source: ScoreRecordSource.manual,
          song: 'test',
          title: 'Test',
          mode: Modes.singles,
          difficulty: 'EXPERT',
          score: 900000,
          rank: 'AA',
          clearLamp: ClearLamp.pfc,
          flareRank: 'IX',
          updatedAt: DateTime(2026));
      await DatabaseProvider.saveScoreRecords([r]);
      await Future.wait(
          [ChartBests.ensure(Modes.singles), ChartBests.ensure(Modes.doubles)]);
      expect(ChartBests.at(song, Modes.doubles, 0), isNull);
      expect(ChartBests.at(song, Modes.singles, 0),
          (score: 999990, grade: Grade.aaa, lamp: ClearLamp.pfc, flare: 'IX'));
      expect(ChartBests.precisionAt('test', Modes.singles, 'EXPERT'), isNull);
      await DatabaseProvider.updateScore(
          s.copyWith(completionLamp: ClearLamp.pfc));
      await ChartBests.ensure(Modes.singles);
      expect(ChartBests.precisionAt('test', Modes.singles, 'EXPERT')?.award,
          PrecisionAward.sdp);
      await DatabaseProvider.updateScore(
          s.copyWith(mode: Modes.doubles, completionLamp: ClearLamp.pfc));
      await Future.wait(
          [ChartBests.ensure(Modes.singles), ChartBests.ensure(Modes.doubles)]);
      expect(ChartBests.precisionAt('test', Modes.singles, 'EXPERT'), isNull);
      expect(
          ChartBests.precisionAt('test', Modes.doubles, 'EXPERT')?.sourceRowId,
          'local');
      await DatabaseProvider.deleteScore(s.id);
      await ChartBests.ensure(Modes.doubles);
      expect(ChartBests.precisionAt('test', Modes.doubles, 'EXPERT'), isNull);
      await DatabaseProvider.deleteScoreRecords(ScoreRecordSource.manual);
      await ChartBests.ensure(Modes.singles);
      expect(ChartBests.at(song, Modes.singles, 0), isNull);
    });
  });
}
