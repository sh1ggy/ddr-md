/// Name: Edition binder tests
/// Parent: EditionBinderPage
/// Description: A cover per level with its count and top card, then
/// sheets of every chart there, collected or not.
library;

import 'package:ddr_md/components/song/jacket_edition/edition_binder_page.dart';
import 'package:ddr_md/components/song/jacket_edition/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_viewer.dart';
import 'package:ddr_md/components/song/jacket_edition/compact_jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_model.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_rules.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_painter.dart';
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:flutter/gestures.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/chart_bests.dart';
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
  testWidgets('complete covers earn finish and weakest frame independently',
      (tester) async {
    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});
      await Settings.init();
      final db = await DatabaseProvider.open(inMemoryDatabasePath);
      final originalSongs = Songs.list;
      SongInfo song(String name) => SongInfo.fromJson({
            'name': name,
            'title': name,
            'version': 'DDR WORLD',
            'sp': {'hard': 14},
            'dp': <String, dynamic>{}
          });
      Songs.list = [song('a'), song('b')];
      final state = SongState();
      try {
        await DatabaseProvider.withTestDatabase(db, () async {
          Future<void> show() async {
            await tester.pumpWidget(ChangeNotifierProvider.value(
                value: state,
                child: MaterialApp(
                    key: UniqueKey(),
                    theme: floorPopTheme(Brightness.dark),
                    home: const EditionBinderPage(level: 14))));
            for (var i = 0; i < 8; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await tester.pump(const Duration(milliseconds: 50));
            }
            expect(tester.takeException(), isNull);
          }

          Offset? countPosition;
          for (final (rank, lamp, finish, frame) in [
            ('AAA', ClearLamp.clear, EditionFinish.prism, EditionFrame.stock),
            ('AA', ClearLamp.pfc, EditionFinish.print, EditionFrame.gold),
            ('AAA', ClearLamp.pfc, EditionFinish.prism, EditionFrame.gold),
          ]) {
            await DatabaseProvider.saveScoreRecords([
              for (final name in ['a', 'b'])
                ScoreRecord(
                    id: name,
                    source: ScoreRecordSource.manual,
                    song: name,
                    title: name,
                    mode: Modes.singles,
                    difficulty: 'EXPERT',
                    score: rank == 'AAA' ? 995000 : 960000,
                    rank: rank,
                    clearLamp: lamp,
                    flareRank: 'EX',
                    updatedAt: DateTime(2026)),
            ]);
            await show();
            final cover =
                tester.widget<JacketEdition>(find.byType(JacketEdition));
            final recipe = resolveEdition(cover.facts, cover.options);
            expect((recipe.finish, recipe.frame), (finish, frame));
            final geometry = EditionGeometry(recipe, const Size(488, 700),
                maxFrameWidth: cover.maxFrameWidth);
            expect(geometry.width, lessThanOrEqualTo(14));
            geometry.dispose();
            expect((
              recipe.motif,
              recipe.tier,
              recipe.flareIndex,
              recipe.negative,
              recipe.difficultyShape
            ), (
              EditionMotif.neutral,
              null,
              -1,
              false,
              0
            ));
            expect(cover.interactive, isFalse);
            expect(cover.layers,
                {EditionLayer.art, EditionLayer.frame, EditionLayer.finish});
            expect(find.byType(EditionFooter), findsNothing);
            expect(find.byKey(const ValueKey('edition-grade-stamp')),
                findsNothing);
            final position = tester.getTopLeft(find.text('2/2'));
            countPosition ??= position;
            expect(position, countPosition);
          }

          final originalSize = tester.view.physicalSize;
          final originalRatio = tester.view.devicePixelRatio;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(350, 540);
          await show();
          expect(find.byType(SingleChildScrollView), findsNothing);
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalRatio;

          final divider =
              binderPages(Modes.singles).whereType<BinderDivider>().single;
          BinderDivider precisionFloor(List<PrecisionAward> awards) =>
              BinderDivider(14, pockets: [
                for (final (i, p) in divider.pockets.indexed)
                  (
                    song: p.song,
                    difficulty: p.difficulty,
                    best: p.best,
                    card: EditionFacts(chart: p.card!.chart, precision: (
                      award: awards[i],
                      sourceRowId: '$i',
                      perfects: null
                    ))
                  )
              ]);
          expect(
              resolveEdition(
                      precisionFloor([PrecisionAward.mfc, PrecisionAward.sdp])
                          .coverFacts!)
                  .frame,
              EditionFrame.platinum);
          expect(
              resolveEdition(
                      precisionFloor([PrecisionAward.mfc, PrecisionAward.mfc])
                          .coverFacts!)
                  .frame,
              EditionFrame.rainbow);

          await Settings.setInt(Settings.jacketEffectsOffKey, 1);
          await Settings.setInt(Settings.jacketMotionOffKey, 1);
          await show();
          final off = tester.widget<JacketEdition>(find.byType(JacketEdition));
          expect(off.options.effects, isFalse);
          expect(off.options.motion, isFalse);
          expect(
              find.descendant(
                  of: find.byType(JacketEdition),
                  matching: find.byType(CustomPaint)),
              findsNothing);
          expect(tester.getTopLeft(find.text('2/2')), countPosition);
          await Settings.setInt(Settings.jacketEffectsOffKey, 0);

          Songs.list = [...Songs.list, song('c')];
          await show();
          expect(find.byType(JacketEdition), findsNothing);
          expect(find.text('2/3'), findsOneWidget);
          await DatabaseProvider.saveScoreRecords([
            ScoreRecord(
                id: 'c',
                source: ScoreRecordSource.manual,
                song: 'c',
                title: 'c',
                mode: Modes.singles,
                difficulty: 'EXPERT',
                score: 960000,
                rank: 'AA',
                clearLamp: ClearLamp.gfc,
                flareRank: '',
                updatedAt: DateTime(2026))
          ]);
          await show();
          expect(find.byType(JacketEdition), findsNothing);
          expect(find.text('3/3'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        });
      } finally {
        Songs.list = originalSongs;
        state.dispose();
        await db.close();
      }
    });
  });

  testWidgets('dividers and sheets by level, gaps as empty pockets',
      (tester) async {
    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});
      await Settings.init();
      final db = await DatabaseProvider.open(inMemoryDatabasePath);
      final originalSongs = Songs.list;
      SongInfo song(String name, int hard) => SongInfo.fromJson({
            'name': name,
            'title': name,
            'version': 'DDR WORLD',
            'sp': {'easy': 5, 'hard': hard},
            'dp': {'hard': hard}
          });
      Songs.list = [song('a', 14), song('b', 14), song('c', 14), song('d', 15)];
      final state = SongState();
      try {
        await DatabaseProvider.withTestDatabase(db, () async {
          await DatabaseProvider.saveScoreRecords([
            for (final (name, score) in [
              ('a', 900000),
              ('b', 980000),
              ('c', 950000),
              ('d', 990000)
            ])
              ScoreRecord(
                  id: name,
                  source: ScoreRecordSource.manual,
                  song: name,
                  title: name,
                  mode: Modes.singles,
                  difficulty: 'EXPERT',
                  score: score,
                  rank: 'AA',
                  clearLamp: ClearLamp.clear,
                  flareRank: name == 'a' ? 'IX' : '',
                  updatedAt: DateTime(2026)),
          ]);
          await ChartBests.ensure(Modes.singles);
          String show(BinderPage page) => switch (page) {
                BinderDivider d => '${d.level}: ${d.collected}/${d.total}'
                    ' top ${d.top?.song.name}',
                BinderSheet s => '${s.level}: ${[
                    for (final p in s.pockets)
                      '${p.song.name}${p.card == null ? '?' : ''}'
                  ].join(' ')}',
              };
          // No level has the ten scored charts a negative needs; every
          // level-5 chart is unplayed.
          expect(binderPages(Modes.singles).map(show), [
            '15: 1/1 top null',
            '15: d',
            '14: 3/3 top null',
            '14: a b c',
            '5: 0/4 top null',
            '5: a? b? c? d?',
          ]);
          await tester.pumpWidget(ChangeNotifierProvider.value(
              value: state,
              child: MaterialApp(
                  theme: floorPopTheme(Brightness.dark),
                  home: Builder(
                      builder: (context) => Scaffold(
                          body: TextButton(
                              onPressed: () => showEditionViewer(context,
                                  facts: const EditionFacts(chart: (
                                    song: 'a',
                                    mode: 'singles',
                                    difficulty: 'hard'
                                  )),
                                  options: defaultEditionOptions,
                                  artwork:
                                      const ColoredBox(color: Colors.indigo),
                                  from: const Rect.fromLTWH(20, 20, 100, 100),
                                  refreshScores: false,
                                  onBinder: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const EditionBinderPage(level: 14)))),
                              child: const Text('Open jacket')))))));
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(30, 30));
          await tester.tap(find.text('Open jacket'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(
              tester.getCenter(find.byType(JacketEdition)),
              (tester.view.physicalSize / tester.view.devicePixelRatio)
                  .center(Offset.zero));
          await tester.tap(find.widgetWithText(TextButton, 'Binder'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          for (var frame = 0; frame < 12; frame++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          expect(find.text('3/3'), findsOneWidget);
          expect(find.bySemanticsLabel('Singles'), findsOneWidget);
          expect(
              find.byKey(const ValueKey('edition-flare-stamp')), findsNothing);
          expect(
              find.byKey(const ValueKey('edition-grade-stamp')), findsNothing);
          expect(find.byType(EditionFooter), findsNothing);
          // Open a collected card after the jacket-to-binder handoff.
          await tester
              .tap(find.byType(CompactJacketEdition).hitTestable().last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.widgetWithText(TextButton, 'Guide'), findsOneWidget);
          await mouse.moveTo(const Offset(400, 300));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.tapAt(const Offset(30, 30));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await mouse.removePointer();
          state.setMode(Modes.doubles);
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await tester.pump();
          expect(find.bySemanticsLabel('Doubles'), findsOneWidget);
          expect(find.bySemanticsLabel('Singles'), findsNothing);

          await tester.pumpWidget(const SizedBox());
        });
      } finally {
        Songs.list = originalSongs;
        state.dispose();
        await db.close();
      }
    });
  });
}
