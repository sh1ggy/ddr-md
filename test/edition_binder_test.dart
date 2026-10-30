/// Name: Edition binder tests
/// Parent: EditionBinderPage
/// Description: A divider per level with its count and top card, then
/// sheets of every chart there, collected or not.
library;

import 'package:ddr_md/components/song/jacket_edition/edition_binder_page.dart';
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
            'dp': <String, dynamic>{}
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
                  flareRank: '',
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
          // Level 15 has one scored chart, too few for a negative; every
          // level-5 chart is unplayed.
          expect(binderPages(Modes.singles).map(show), [
            '15: 1/1 top null',
            '15: d',
            '14: 3/3 top b',
            '14: a b c',
            '5: 0/4 top null',
            '5: a? b? c? d?',
          ]);
          await tester.pumpWidget(ChangeNotifierProvider.value(
              value: state,
              child: MaterialApp(
                  theme: floorPopTheme(Brightness.dark),
                  home: const EditionBinderPage(level: 14))));
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('Level 14'), findsOneWidget);
          expect(find.text('3 of 3 collected'), findsOneWidget);
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
