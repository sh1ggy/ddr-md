/// Name: Edition binder tests
/// Parent: EditionBinderPage
/// Description: Cards filed by level, each level led by its negative.
library;

import 'package:ddr_md/components/song/jacket_edition/compact_jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_binder_page.dart';
import 'package:ddr_md/components/song_json.dart';
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
  testWidgets('files cards by level with the top score as negative first',
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
          await tester.pumpWidget(ChangeNotifierProvider.value(
              value: state,
              child: MaterialApp(
                  theme: floorPopTheme(Brightness.dark),
                  home: const EditionBinderPage())));
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await tester.pump();
          final cards = tester
              .widgetList<CompactJacketEdition>(
                  find.byType(CompactJacketEdition))
              .map((c) => (c.facts.chart.song, c.facts.levelTop))
              .toList();
          // Level 15 first; level 14's three charts lead with its top score.
          // Level 15 has one scored chart, too few for a negative.
          expect(cards, [
            ('d', false),
            ('b', true),
            ('c', false),
            ('a', false),
          ]);
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
