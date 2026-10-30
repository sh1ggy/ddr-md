/// Name: Recent play migration test
/// Parent: DatabaseProvider
/// Description: Upgrades a cloud-enabled v15 database without losing its
/// plays, identity rows, sync metadata or change-tracking triggers.
library;

import 'dart:io';

import 'package:ddr_md/models/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v15 cloud database gains scrape order and retains cloud tracking',
      () async {
    final dir = await Directory.systemTemp.createTemp('credit-migration-');
    final path = '${dir.path}/migration.db';
    var db = await DatabaseProvider.open(path);
    addTearDown(() async {
      if (db.isOpen) await db.close();
      await dir.delete(recursive: true);
    });
    final venue =
        await db.insert('venues', {'name': 'Seed venue', 'uid': 'seed'});
    await db.insert('sync_meta', {'k': 'migration-test', 'v': 'keep'});
    Map<String, Object?> play(String id) => {
          'konamiId': id,
          'title': id,
          'song': id,
          'mode': 'singles',
          'difficulty': 'EXPERT',
          'playedAt': '2026-10-28T10:00:00.000Z',
          'score': 900000,
        };
    for (final id in ['a', 'b']) {
      await db.insert('recent_plays', play(id));
    }
    final triggers = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' ORDER BY name");
    expect(triggers, isNotEmpty);
    // Recreate production v15 with cloud sync already installed before
    // reopening the app and applying the scrape-order migration.
    await db.execute('ALTER TABLE recent_plays DROP COLUMN syncOrder');
    await db.setVersion(15);
    await db.close();

    db = await DatabaseProvider.open(path);
    expect(await db.getVersion(), 17);
    final rows = await db.query('recent_plays', orderBy: 'rowid');
    expect(rows.map((r) => r['konamiId']), ['a', 'b']);
    expect(rows.map((r) => r['syncOrder']), [0, 0]);
    expect((await db.query('venues')).single['id'], venue);
    expect((await db.query('venues')).single['uid'], 'seed');
    expect(
        (await db.query('sync_meta',
                where: 'k = ?', whereArgs: ['migration-test']))
            .single['v'],
        'keep');
    expect(
        await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' ORDER BY name"),
        triggers);
    await db.insert('recent_plays', {...play('new'), 'syncOrder': 10});
    expect(
        await db
            .query('sync_outbox', where: 't = ?', whereArgs: ['recent_plays']),
        hasLength(3));
    await db.delete('sync_outbox', where: 't = ?', whereArgs: ['recent_plays']);
    await db.update('recent_plays', {'score': 950000},
        where: 'konamiId = ?', whereArgs: ['a']);
    expect(
        await db
            .query('sync_outbox', where: 't = ?', whereArgs: ['recent_plays']),
        hasLength(1));
  });
}
