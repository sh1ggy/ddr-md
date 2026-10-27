import 'dart:convert';
import 'dart:io';

import 'package:ddr_md/models/cloud_sync.dart';
import 'package:ddr_md/models/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The Worker's rules: the latest write to a row wins (a beaten one still
/// takes a new revision), and pulls page through rows by revision.
class _Server implements SyncServer {
  final _rows = <(String, String), (SyncChange, int)>{};
  var _rev = 0;

  @override
  Future<({int rev, List<int> lost})> push(List<SyncChange> changes,
      {String? ddrCode}) async {
    final lost = <int>[];
    for (final (i, c) in changes.indexed) {
      final d = json.decode(json.encode(c.d)) as Map<String, Object?>?;
      final old = _rows[(c.t, c.k)]?.$1;
      if (old == null || c.u.compareTo(old.u) >= 0) {
        _rows[(c.t, c.k)] = ((t: c.t, k: c.k, u: c.u, d: d), ++_rev);
      } else {
        _rows[(c.t, c.k)] = (old, ++_rev);
        lost.add(i);
      }
    }
    return (rev: _rev, lost: lost);
  }

  @override
  Future<({List<SyncChange> changes, int cursor, bool more, int head})> pull(
      int cursor) async {
    final after = _rows.values.where((r) => r.$2 > cursor).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    final page = after.take(3).toList();
    return (
      changes: [for (final r in page) r.$1],
      cursor: page.isEmpty ? cursor : page.last.$2,
      more: after.length > 3,
      head: _rows.isEmpty ? 0 : _rev,
    );
  }

  @override
  Future<void> deleteAll() async {
    _rows.clear();
    _rev = 0;
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('two devices converge through the server', () async {
    final dir = await Directory.systemTemp.createTemp('cloud_sync');
    final a = await DatabaseProvider.open('${dir.path}/a.db');
    final b = await DatabaseProvider.open('${dir.path}/b.db');
    final server = _Server();
    final prefsA = <String, Object>{'chosenReadSpeed': 550};
    final prefsB = <String, Object>{};
    Future<void> sync(Database db, Map<String, Object> prefs) => SyncEngine(
          db,
          server,
          account: 'test',
          readPrefs: () => prefs,
          writePrefs: (p) async => prefs.addAll(p.cast()),
        ).run();

    // B already has a cabinet at the same venue, under other local ids.
    await b.insert('venues', {'id': 7, 'name': 'Round1', 'uid': 'Round1'});
    await b.insert('cabinets',
        {'id': 9, 'venueId': 7, 'name': 'Left', 'uid': 'Round1/Left'});
    await b.insert('notes', {
      'id': 'nb',
      'createdAt': '2026-10-01',
      'contents': 'from B',
      'mode': 'singles'
    });

    final venue = await a.insert('venues', {'name': 'Round1', 'uid': 'Round1'});
    final cab = await a.insert(
        'cabinets', {'venueId': venue, 'name': '', 'uid': 'Round1/'});
    await a.insert('sessions',
        {'id': 's1', 'venueId': venue, 'startedAt': '2026-10-26T10:00'});
    await a.insert('credits', {
      'id': 'c1',
      'sessionId': 's1',
      'number': 1,
      'cabinetId': cab,
      'side': 'p1',
      'startedAt': '2026-10-26T10:01'
    });
    await a.insert('sync_overrides', {
      'cabinetId': cab,
      'side': 'p1',
      'song': 'MAX 300',
      'mode': 'singles',
      'difficulty': 'expert',
      'ms': 12.5
    });
    await a.insert('notes', {
      'id': 'na',
      'createdAt': '2026-10-02',
      'contents': 'from A',
      'mode': 'singles'
    });
    await a.insert('favorites',
        {'isFav': 1, 'songTitle': 'MAX 300', 'mode': 'singles'});
    await a.insert('parity_pins', {
      'song': 'MAX 300',
      'mode': 'singles',
      'difficulty': 'expert',
      'chartHash': 'h',
      'beat': 12.5,
      'col': 2,
      'foot': 'L'
    });

    await sync(a, prefsA);
    await sync(b, prefsB);
    await sync(a, prefsA);

    // One Round1 on B, holding both cabinets; A's rows point at B's ids.
    expect(await b.query('venues'), hasLength(1));
    final bCab = (await b.query('cabinets', where: "uid = 'Round1/'")).single;
    expect(bCab['venueId'], 7);
    final credit = (await b.query('credits')).single;
    expect(credit['cabinetId'], bCab['id']);
    expect((await b.query('sync_overrides')).single['cabinetId'], bCab['id']);
    expect((await b.query('sessions')).single['venueId'], 7);
    expect(await b.query('notes'), hasLength(2));
    expect(await a.query('notes'), hasLength(2));
    expect(await a.query('cabinets'), hasLength(2));
    expect(prefsB['chosenReadSpeed'], 550);

    // Deletes and edits travel too.
    await a.delete('favorites');
    await a.delete('notes', where: "id = 'nb'");
    await a.update('parity_pins', {'foot': 'R'});
    await sync(a, prefsA);
    await sync(b, prefsB);
    expect(await b.query('favorites'), isEmpty);
    expect((await b.query('notes')).single['id'], 'na');
    expect((await b.query('parity_pins')).single['foot'], 'R');
    expect(await a.query('sync_outbox'), isEmpty);
    expect(await b.query('sync_outbox'), isEmpty);

    // An edit beaten by a newer one elsewhere is replaced by the winner.
    await b.update('notes', {'contents': 'older'}, where: "id = 'na'");
    await b.update('sync_outbox', {'at': '2000-01-01T00:00:00.000Z'},
        where: "k = 'na'");
    await a.update('notes', {'contents': 'newer'}, where: "id = 'na'");
    await sync(a, prefsA);
    await sync(b, prefsB);
    expect((await b.query('notes')).single['contents'], 'newer');

    // A server that lost everything gets it all back.
    await server.deleteAll();
    await sync(a, prefsA);
    expect((await server.pull(0)).head, greaterThan(0));

    await a.close();
    await b.close();
    await dir.delete(recursive: true);
  });
}
