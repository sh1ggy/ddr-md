/// Name: Song edition summary tests
/// Parent: SongDetails
/// Description: A plain header jacket, and a zoomed card that follows the
/// selected chart and its scores.
library;

import 'package:ddr_md/components/song/song_details.dart';
import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets(
      'plain header; the zoom follows the selected chart and its scores',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});
      await Settings.init();
      final db = await DatabaseProvider.open(inMemoryDatabasePath);
      final originalSongs = Songs.list;
      final song = SongInfo.fromJson({
        'name': 'header-fixture',
        'title': 'Header fixture',
        'version': 'DDR WORLD',
        'sp': {'easy': 5, 'hard': 17},
        'dp': {'hard': 18}
      });
      final state = SongState()..setSongInfo(song);
      Songs.list = [song];
      try {
        await DatabaseProvider.withTestDatabase(db, () async {
          ScoreRecord record(String id, Modes mode, String difficulty,
                  String rank, ClearLamp lamp, String flare) =>
              ScoreRecord(
                  id: id,
                  source: ScoreRecordSource.manual,
                  song: song.name,
                  title: song.title,
                  mode: mode,
                  difficulty: difficulty,
                  rank: rank,
                  clearLamp: lamp,
                  flareRank: flare,
                  updatedAt: DateTime(2026));
          await DatabaseProvider.saveScoreRecords([
            record('sp-easy', Modes.singles, 'BASIC', 'B', ClearLamp.fc, 'I'),
            record(
                'sp-hard', Modes.singles, 'EXPERT', 'AAA', ClearLamp.pfc, 'EX'),
            record(
                'dp-hard', Modes.doubles, 'EXPERT', 'AA', ClearLamp.mfc, 'IX'),
          ]);
          await tester.pumpWidget(ChangeNotifierProvider.value(
              value: state,
              child: MaterialApp(
                  theme: floorPopTheme(Brightness.dark),
                  home: Scaffold(
                      body: SingleChildScrollView(
                          child: SongDetails(songInfo: song, chart: null))))));
          Future<void> refresh() async {
            await Future<void>.delayed(const Duration(milliseconds: 80));
            await tester.pumpAndSettle();
          }

          Future<JacketEdition> zoom() async {
            await tester.tap(find.byType(SongArtwork).last);
            await Future<void>.delayed(const Duration(milliseconds: 80));
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            return tester.widget<JacketEdition>(find.byType(JacketEdition));
          }

          Future<void> close() async {
            await tester.tap(find.byType(SongArtwork).last);
            await tester.pumpAndSettle();
          }

          await refresh();
          expect(find.byType(JacketEdition), findsNothing);
          expect(find.byType(EditionAchievementStamps), findsNothing);
          expect(tester.binding.transientCallbackCount, 0);
          var card = await zoom();
          expect(card.facts.grade, Grade.b);
          expect(card.facts.flare, 'I');
          // The score card carries the badges; the zoomed card is its finish.
          expect(resolveEdition(card.facts, card.options).gradeStamp, isNull);
          await close();
          state.setChosenDifficulty(1);
          await tester.pump();
          card = await zoom();
          expect(card.facts.grade, Grade.aaa);
          expect(card.facts.level, 17);
          expect(card.facts.flare, 'EX');
          await close();
          state.setMode(Modes.doubles);
          await tester.pump();
          card = await zoom();
          expect(card.facts.chart.mode, 'doubles');
          expect(card.facts.grade, Grade.aa);
          expect(card.facts.level, 18);
          await close();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      } finally {
        Songs.list = originalSongs;
        state.dispose();
        await db.close();
      }
    });
  }, skip: !editionDevelopmentEnabled);
}
