/// Name: Recent play churn test
/// Parent: DatabaseProvider
/// Description: Re-listing the same recent plays queues nothing for cloud
/// backup; new or changed plays queue only themselves and keep scrape order.
library;

import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('an unchanged history check writes no recent plays', () async {
    final db = await DatabaseProvider.open(inMemoryDatabasePath);
    addTearDown(db.close);
    RecentPlay play(String id, int minute, {String? song}) => RecentPlay(
        konamiId: id,
        title: id,
        song: song,
        mode: Modes.singles,
        difficulty: 'EXPERT',
        playedAt: DateTime.utc(2026, 11, 8, 10, minute),
        score: 900000);
    Future<List<Object?>> queued() async => [
          for (final r in await db.query('sync_outbox',
              where: 't = ?', whereArgs: ['recent_plays'], orderBy: 'k'))
            r['k']
        ];
    Future<List<String>> ids() async =>
        [for (final p in await DatabaseProvider.getRecentPlays()) p.konamiId];

    await DatabaseProvider.withTestDatabase(db, () async {
      // b and c share a minute; the scrape lists b first, so b is newer.
      final first = [play('b', 1), play('c', 1), play('a', 0)];
      await DatabaseProvider.saveRecentPlays(first);
      expect(await ids(), ['b', 'c', 'a']);
      await db.delete('sync_outbox');

      await DatabaseProvider.saveRecentPlays(first);
      expect(await queued(), isEmpty);
      expect(await ids(), ['b', 'c', 'a']);

      await DatabaseProvider.saveRecentPlays(
          [play('d', 2), play('b', 1), play('c', 1), play('a', 0, song: 'A')]);
      expect(await ids(), ['d', 'b', 'c', 'a']);
      expect(await queued(), hasLength(2));
    });
  });
}
