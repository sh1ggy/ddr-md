/// Name: EditionViewerTest
/// Parent: EditionViewer
/// Description: Checks chart refresh and expanded-card appearance controls.
library;

import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_viewer.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('expanded stamps toggle independently and persist on reopening',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showEditionViewer(context,
                    facts: const EditionFacts(
                        chart: (
                          song: 'test',
                          mode: 'singles',
                          difficulty: 'hard'
                        ),
                        level: 16,
                        lamp: ClearLamp.pfc,
                        grade: Grade.aa,
                        flare: 'IX',
                        score: 900000),
                    options: (
                      borderId: 'gilded',
                      effects: true,
                      motion: false,
                      modeStamp: false,
                      gradeStamp: false,
                      difficultyStamp: false,
                      tierSuffix: false
                    ),
                    refreshScores: false,
                    artwork: const ColoredBox(color: Colors.indigo)),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edition-grade-stamp')), findsOneWidget);
    expect(find.byKey(const ValueKey('edition-flare-stamp')), findsOneWidget);
    expect(find.byKey(const ValueKey('edition-lamp-stamp')), findsOneWidget);
    expect(find.byType(EditionFooter), findsOneWidget);
    await tester.tap(find.byTooltip('Turn card stamps off'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('edition-achievement-stamp')), findsNothing);
    expect(find.byType(EditionFooter), findsNothing);
    expect(
        tester
            .widget<JacketEdition>(find.byType(JacketEdition))
            .options
            .effects,
        isTrue);
    expect(Settings.getInt(Settings.jacketViewerStampsOffKey), 1);
    await tester.tap(find.byTooltip('Turn card stamps on'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Turn card effects off'));
    await tester.pumpAndSettle();
    expect(find.byType(EditionFooter), findsNothing);
    await tester.tap(find.byTooltip('Turn card effects on'));
    await tester.pumpAndSettle();
    expect(find.byType(EditionFooter), findsOneWidget);
    await tester.tap(find.byTooltip('Turn card stamps off'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(JacketEdition))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Turn card stamps on'), findsOneWidget);
    expect(find.byType(EditionFooter), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an open viewer refreshes only its frozen chart and releases its subscription',
      (tester) async {
    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await DatabaseProvider.open(inMemoryDatabasePath);
      try {
        await DatabaseProvider.withTestDatabase(db, () async {
          Songs.list = [
            SongInfo(
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
                charts: const [])
          ];
          await tester.pumpWidget(const MaterialApp(
              home: Center(
                  child: SizedBox.square(
                      dimension: 320,
                      child: EditionViewer(
                          facts: EditionFacts(chart: (
                            song: 'test',
                            mode: 'singles',
                            difficulty: 'hard'
                          ), level: 16),
                          options: (
                            borderId: 'gilded',
                            effects: true,
                            motion: false,
                            modeStamp: false,
                            gradeStamp: false,
                            difficultyStamp: false,
                            tierSuffix: false
                          ),
                          child: ColoredBox(color: Colors.indigo))))));
          final play = Score(
              playedAt: '2026-10-30',
              source: ScoreSource.camera,
              songTitle: 'Test',
              mode: Modes.doubles,
              difficulty: 'EXPERT',
              score: 999990,
              marvelous: 400,
              perfect: 1,
              great: 0,
              good: 0,
              miss: 0,
              completionLamp: ClearLamp.pfc);
          await DatabaseProvider.addScore(play);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          expect(
              tester
                  .widget<JacketEdition>(find.byType(JacketEdition))
                  .facts
                  .grade,
              isNull);
          await DatabaseProvider.updateScore(
              play.copyWith(mode: Modes.singles));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          final facts =
              tester.widget<JacketEdition>(find.byType(JacketEdition)).facts;
          expect(facts.chart.mode, 'singles');
          expect(facts.grade, Grade.aaa);
          expect(facts.precision?.sourceRowId, play.id);
          await tester.pumpWidget(const SizedBox());
          await DatabaseProvider.deleteScore(play.id);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      } finally {
        await db.close();
      }
    });
  });
}
