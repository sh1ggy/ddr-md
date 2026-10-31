/// Name: CloudSync
/// Description: Optional cloud backup of the player's own data (scores,
/// sessions, notes, favourites, pins, snippets and settings), synced between
/// their devices through the Worker in infra/sync. There is no sign-in: the
/// account is a random key made on first use, kept in the iOS Keychain
/// (shared by iCloud Keychain) and in preferences (restored by Android's
/// backup). Local SQLite stays the source of truth. Triggers note every
/// changed row in sync_outbox; a sync pushes those rows as they are now (or
/// as deleted), then pulls what other devices wrote after its cursor. The
/// latest write to a row wins.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

/// Release builds default to the live server; debug/profile to off unless
/// given --dart-define=SYNC_URL=… (terraform output sync_url). Empty = off.
const kSyncUrl = String.fromEnvironment('SYNC_URL',
    defaultValue: kReleaseMode ? 'https://sync.ddr-md.workers.dev' : '');

/// A synced table and how its rows are told apart across devices.
class SyncTable {
  const SyncTable(this.name, this.key,
      {this.localOnly = const {}, this.refs = const {}});
  final String name;

  /// SQL terms with `{r}` for the row, joined into the row's key.
  final List<String> key;

  /// Columns that only mean something on this device (autoincrement ids).
  final Set<String> localOnly;

  /// Integer columns holding another synced table's local id, carried
  /// between devices as that row's key.
  final Map<String, String> refs;

  String keyOf(String row) => key
      .map((t) => "coalesce(${t.replaceAll('{r}', row)}, '')")
      .join('||char(31)||');
}

// Venues and cabinets first: rows pulled from other tables point at them.
// Their uid is their name (a cabinet's is "venue/name"), so a venue added
// on two devices becomes one.
const syncTables = [
  SyncTable('venues', ['{r}.uid'], localOnly: {'id'}),
  SyncTable('cabinets', ['{r}.uid'],
      localOnly: {'id'}, refs: {'venueId': 'venues'}),
  SyncTable('sessions', ['{r}.id'], refs: {'venueId': 'venues'}),
  SyncTable('credits', ['{r}.id'], refs: {'cabinetId': 'cabinets'}),
  SyncTable('timing_plays', ['{r}.id'], refs: {'cabinetId': 'cabinets'}),
  SyncTable('sync_overrides', [
    '(SELECT uid FROM cabinets WHERE id = {r}.cabinetId)',
    '{r}.side',
    '{r}.song',
    '{r}.mode',
    '{r}.difficulty'
  ], refs: {
    'cabinetId': 'cabinets'
  }),
  SyncTable('scores', ['{r}.id']),
  SyncTable('score_records', ['{r}.id']),
  SyncTable('recent_plays',
      ['{r}.konamiId', '{r}.mode', '{r}.difficulty', '{r}.playedAt']),
  SyncTable('notes', ['{r}.id']),
  SyncTable('favorites', ['{r}.songTitle', '{r}.mode'], localOnly: {'id'}),
  SyncTable('parity_pins',
      ['{r}.song', '{r}.mode', '{r}.difficulty', '{r}.beat', '{r}.col']),
  SyncTable('snippets', ['{r}.id']),
  SyncTable('card_gains', ['{r}.id']),
];

const _now = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";

/// v15: uids on venues and cabinets, the outbox, and its triggers. Every
/// existing row starts in the outbox, ready for the first sync.
Future<void> installSync(Database db) async {
  const fillUids = [
    'UPDATE venues SET uid = name WHERE uid IS NULL',
    "UPDATE cabinets SET uid = (SELECT v.uid FROM venues v WHERE v.id = cabinets.venueId) || '/' || name || "
        "CASE WHEN EXISTS (SELECT 1 FROM cabinets c WHERE c.venueId = cabinets.venueId AND c.name = cabinets.name AND c.id < cabinets.id) "
        "THEN '#' || id ELSE '' END WHERE uid IS NULL",
  ];
  // Already done: a build on an older schema (another worktree's, sharing
  // this app's database) can wind user_version back without undoing it, and
  // adds venues and cabinets without uids meanwhile.
  final venues = await db.rawQuery('PRAGMA table_info(venues)');
  if (venues.any((c) => c['name'] == 'uid')) {
    for (final sql in fillUids) {
      await db.execute(sql);
    }
    return;
  }
  await db.execute('ALTER TABLE venues ADD COLUMN uid TEXT');
  await db.execute('ALTER TABLE cabinets ADD COLUMN uid TEXT');
  for (final sql in fillUids) {
    await db.execute(sql);
  }
  await db.execute('CREATE UNIQUE INDEX venues_uid ON venues(uid)');
  await db.execute('CREATE UNIQUE INDEX cabinets_uid ON cabinets(uid)');
  await db.execute(
      'CREATE TABLE sync_outbox(t TEXT NOT NULL, k TEXT NOT NULL, at TEXT NOT NULL, PRIMARY KEY(t, k))');
  await db.execute('CREATE TABLE sync_meta(k TEXT PRIMARY KEY, v TEXT)');
  for (final t in syncTables) {
    await addSyncTriggers(db, t);
  }
  await queueEverything(db);
}

/// Notes [t]'s inserts, updates and deletes in the outbox, for a table
/// synced from the start or added to [syncTables] later.
Future<void> addSyncTriggers(DatabaseExecutor db, SyncTable t) async {
  const live = "NOT EXISTS (SELECT 1 FROM sync_meta WHERE k = 'applying')";
  String note(String row) =>
      "INSERT OR REPLACE INTO sync_outbox VALUES ('${t.name}', ${t.keyOf(row)}, $_now);";
  await db.execute(
      'CREATE TRIGGER IF NOT EXISTS sync_${t.name}_i AFTER INSERT ON ${t.name} WHEN $live BEGIN ${note('NEW')} END');
  await db.execute(
      'CREATE TRIGGER IF NOT EXISTS sync_${t.name}_u AFTER UPDATE ON ${t.name} WHEN $live BEGIN ${note('OLD')} ${note('NEW')} END');
  await db.execute(
      'CREATE TRIGGER IF NOT EXISTS sync_${t.name}_d AFTER DELETE ON ${t.name} WHEN $live BEGIN ${note('OLD')} END');
}

/// Puts every row in the outbox, for an account that starts out empty.
Future<void> queueEverything(DatabaseExecutor db) async {
  for (final t in syncTables) {
    await db.execute(
        "INSERT OR REPLACE INTO sync_outbox SELECT '${t.name}', ${t.keyOf('r')}, $_now FROM ${t.name} AS r");
  }
}

/// One change as the server stores it: table, key, when it was written, and
/// the row (null when deleted).
typedef SyncChange = ({String t, String k, String u, Map<String, Object?>? d});

/// The server's daily write budget is spent; what's waiting goes up later.
class SyncLimitException implements Exception {}

abstract class SyncServer {
  /// The account's revision after the push, and the indexes of [changes]
  /// that a newer write beat.
  Future<({int rev, List<int> lost})> push(List<SyncChange> changes,
      {String? ddrCode});

  /// Changes after [cursor], oldest first, and the account's latest
  /// revision.
  Future<({List<SyncChange> changes, int cursor, bool more, int head})> pull(
      int cursor);
  Future<void> deleteAll();
}

class HttpSyncServer implements SyncServer {
  HttpSyncServer(String url, this.key)
      : base = Uri.parse(url.endsWith('/') ? url : '$url/');
  final Uri base;
  final String key;

  @override
  Future<({int rev, List<int> lost})> push(List<SyncChange> changes,
      {String? ddrCode}) async {
    final body = await _send('POST', 'v1/push', {
      'ddrCode': ddrCode,
      'changes': [
        for (final c in changes) {'t': c.t, 'k': c.k, 'u': c.u, 'd': c.d}
      ]
    }) as Map;
    return (rev: body['rev'] as int, lost: (body['lost'] as List).cast<int>());
  }

  @override
  Future<({List<SyncChange> changes, int cursor, bool more, int head})> pull(
      int cursor) async {
    final body = await _send('GET', 'v1/pull?cursor=$cursor') as Map;
    return (
      changes: [
        for (final c in body['changes'] as List)
          (
            t: c['t'] as String,
            k: c['k'] as String,
            u: c['u'] as String,
            d: (c['d'] as Map?)?.cast<String, Object?>()
          )
      ],
      cursor: body['cursor'] as int,
      more: body['more'] as bool,
      head: body['head'] as int,
    );
  }

  @override
  Future<void> deleteAll() => _send('DELETE', 'v1/me');

  Future<Object?> _send(String method, String path, [Object? body]) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final url = base.resolve(path);
      final req = await client.openUrl(method, url);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(json.encode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 30));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode == 429) throw SyncLimitException();
      if (res.statusCode >= 300) {
        throw HttpException('HTTP ${res.statusCode}', uri: url);
      }
      return text.isEmpty ? null : json.decode(text);
    } finally {
      client.close();
    }
  }
}

/// One sync of [db] with [server]: push the outbox, then pull and apply.
class SyncEngine {
  SyncEngine(this.db, this.server,
      {required this.account,
      required this.readPrefs,
      required this.writePrefs,
      this.ddrCode});
  final Database db;
  final SyncServer server;

  /// Which account the cursor and outbox are for (a fingerprint of the key).
  final String account;
  final Map<String, Object> Function() readPrefs;
  final Future<void> Function(Map<String, Object?> prefs) writePrefs;
  final String? ddrCode;

  // Per request; the server refuses more.
  static const _chunk = 200;

  /// True when rows or settings came down. Settings go up last, so a new
  /// device takes the account's settings rather than sending up its
  /// defaults.
  Future<bool> run() async {
    if (await _meta('account') != account) await _startOver();
    await _push();
    var pulled = await _pull();
    if (pulled == null) {
      await _startOver();
      await _push();
      pulled = await _pull() ?? false;
    }
    await _pushPrefs();
    return pulled;
  }

  // Everything here goes up again: another account, or one the server lost.
  Future<void> _startOver() => db.transaction((txn) async {
        await txn.delete('sync_meta');
        await queueEverything(txn);
        await _setMeta(txn, 'account', account);
      });

  Future<void> _push() async {
    var cursor = int.parse(await _meta('cursor') ?? '0');
    final outbox = await db.query('sync_outbox');
    final uids = await _uidsById(db);
    final pending = <(Map<String, Object?>, SyncChange)>[];
    for (final t in syncTables) {
      final entries = outbox.where((e) => e['t'] == t.name).toList();
      if (entries.isEmpty) continue;
      final rows = {
        for (final r in await db
            .rawQuery('SELECT ${t.keyOf('r')} AS _k, r.* FROM ${t.name} AS r'))
          r['_k']: r
      };
      for (final e in entries) {
        final row = rows[e['k']];
        pending.add((
          e,
          (
            t: t.name,
            k: e['k'] as String,
            u: e['at'] as String,
            d: row == null ? null : _portable(t, row, uids),
          )
        ));
      }
    }
    for (var i = 0; i < pending.length; i += _chunk) {
      final chunk = pending.skip(i).take(_chunk).toList();
      final pushed =
          await server.push([for (final (_, c) in chunk) c], ddrCode: ddrCode);
      final batch = db.batch();
      // Nothing else was written since the cursor and every row held, so
      // pulling these back would only echo them.
      if (pushed.lost.isEmpty && pushed.rev - chunk.length == cursor) {
        cursor = pushed.rev;
        batch.insert('sync_meta', {'k': 'cursor', 'v': '$cursor'},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final (e, _) in chunk) {
        // Only if unchanged since it was read: a newer edit still needs
        // pushing.
        batch.delete('sync_outbox',
            where: 't = ? AND k = ? AND at = ?',
            whereArgs: [e['t'], e['k'], e['at']]);
      }
      await batch.commit(noResult: true);
    }
  }

  // The settings as last synced are kept in sync_meta, so what changed here
  // since can be told apart from what changed elsewhere.
  Future<void> _pushPrefs() async {
    final prefs = _canonical(readPrefs());
    if (prefs == await _meta('prefs')) return;
    final cursor = int.parse(await _meta('cursor') ?? '0');
    final pushed = await server.push([
      (
        t: 'prefs',
        k: 'app',
        u: DateTime.now().toUtc().toIso8601String(),
        d: json.decode(prefs) as Map<String, Object?>,
      )
    ], ddrCode: ddrCode);
    await _setMeta(db, 'prefs', prefs);
    if (pushed.lost.isEmpty && pushed.rev - 1 == cursor) {
      await _setMeta(db, 'cursor', '${pushed.rev}');
    }
  }

  // Whether anything came down; null when the server has less than this
  // device already pulled (its data was lost), so everything must go up again.
  Future<bool?> _pull() async {
    var cursor = int.parse(await _meta('cursor') ?? '0');
    final changes = <SyncChange>[];
    for (var more = true; more;) {
      final page = await server.pull(cursor);
      if (page.head < cursor) return null;
      changes.addAll(page.changes);
      cursor = page.cursor;
      more = page.more;
    }
    if (changes.isEmpty) return false;
    Map<String, Object?>? prefs;
    await db.transaction((txn) async {
      await _setMeta(txn, 'applying', '1');
      // Rows edited here since the push stay as they are; they go up next
      // time.
      final pending = {
        for (final r in await txn.query('sync_outbox')) (r['t'], r['k'])
      };
      final ids = {
        for (final t in ['venues', 'cabinets'])
          t: {
            for (final r in await txn.query(t, columns: ['id', 'uid']))
              r['uid']: r['id'] as int
          }
      };
      for (final t in syncTables) {
        Map<Object?, int>? rowids;
        Set<String>? columns;
        for (final c in changes) {
          if (c.t != t.name || pending.contains((c.t, c.k))) continue;
          rowids ??= {
            for (final r in await txn.rawQuery(
                'SELECT rowid AS _id, ${t.keyOf('r')} AS _k FROM ${t.name} AS r'))
              r['_k']: r['_id'] as int
          };
          columns ??= {
            for (final r in await txn.rawQuery('PRAGMA table_info(${t.name})'))
              r['name'] as String
          };
          final rowid = rowids[c.k];
          final row = c.d == null ? null : _local(t, c.d!, columns, ids);
          if (c.d == null) {
            if (rowid != null) {
              await txn.delete(t.name, where: 'rowid = ?', whereArgs: [rowid]);
              rowids.remove(c.k);
            }
          } else if (row == null) {
            // Points at a venue or cabinet this device doesn't have.
          } else if (rowid != null) {
            await txn.update(t.name, row,
                where: 'rowid = ?',
                whereArgs: [rowid],
                conflictAlgorithm: ConflictAlgorithm.ignore);
          } else {
            final id = await txn.insert(t.name, row,
                conflictAlgorithm: ConflictAlgorithm.ignore);
            if (id != 0) {
              rowids[c.k] = id;
              ids[t.name]?[row['uid']] = id;
            }
          }
        }
      }
      for (final c in changes) {
        if (c.t == 'prefs') prefs = c.d;
      }
      await txn.delete('sync_meta', where: "k = 'applying'");
      await _setMeta(txn, 'cursor', '$cursor');
    });
    if (changes.any((c) => c.t == 'scores' || c.t == 'score_records')) {
      DatabaseProvider.invalidateAchievements();
    }
    if (prefs case final remote?) {
      // Settings changed here since the last sync stay, on top of the
      // pulled ones, and go up after.
      final last = await _meta('prefs');
      final synced = last == null ? null : json.decode(last) as Map;
      final edits = {
        for (final MapEntry(:key, :value) in readPrefs().entries)
          if (synced != null && synced[key] != value) key: value
      };
      await writePrefs(remote);
      await writePrefs(edits);
      await _setMeta(db, 'prefs', _canonical(remote));
    }
    return true;
  }

  static Map<String, Object?> _portable(SyncTable t, Map<String, Object?> row,
          Map<String, Map<Object?, Object?>> uids) =>
      {
        for (final MapEntry(:key, :value) in row.entries)
          if (key != '_k' && !t.localOnly.contains(key))
            key: t.refs[key] == null ? value : uids[t.refs[key]]![value],
      };

  // Null when a reference can't be resolved here.
  static Map<String, Object?>? _local(SyncTable t, Map<String, Object?> data,
      Set<String> columns, Map<String, Map<Object?, int>> ids) {
    final row = <String, Object?>{};
    for (final MapEntry(:key, :value) in data.entries) {
      if (!columns.contains(key) || t.localOnly.contains(key)) continue;
      final ref = t.refs[key];
      if (ref == null) {
        row[key] = value;
      } else if (ids[ref]![value] case final id?) {
        row[key] = id;
      } else {
        return null;
      }
    }
    return row;
  }

  static Future<Map<String, Map<Object?, Object?>>> _uidsById(
          Database db) async =>
      {
        for (final t in ['venues', 'cabinets'])
          t: {
            for (final r in await db.query(t, columns: ['id', 'uid']))
              r['id']: r['uid']
          }
      };

  Future<String?> _meta(String k) async =>
      (await db.query('sync_meta', where: 'k = ?', whereArgs: [k]))
          .firstOrNull?['v'] as String?;

  static Future<int> _setMeta(DatabaseExecutor db, String k, String v) =>
      db.insert('sync_meta', {'k': k, 'v': v},
          conflictAlgorithm: ConflictAlgorithm.replace);

  static String _canonical(Map<String, Object?> prefs) =>
      json.encode({for (final k in prefs.keys.toList()..sort()) k: prefs[k]});
}

/// The app's sync: on when the player turns it on and the build has a server.
class CloudSync {
  static final running = ValueNotifier(false);

  /// Bumped when a sync brings down rows or settings, so open pages reload.
  static final pulled = ValueNotifier(0);
  static Future<void>? _running;
  static DateTime? _last;

  static bool get available => kSyncUrl.isNotEmpty;
  static bool get enabled =>
      available && Settings.getInt(Settings.cloudSyncOnKey) == 1;

  /// Syncs unless off, already running, or (without [force]) done in the
  /// last half minute. Throws what the sync threw.
  static Future<void> sync({bool force = false}) async {
    if (!enabled) return;
    final last = _last;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }
    return _running ??= _sync().whenComplete(() => _running = null);
  }

  /// For lifecycle hooks: a failed sync just waits for the next one.
  static void syncQuietly() => sync().catchError((Object e) {
        debugPrint('Cloud sync failed: $e');
      });

  static Future<void> _sync() async {
    running.value = true;
    try {
      final rival = Settings.getString(Settings.rivalCodeSpeedKey)
          .replaceAll(RegExp(r'\D'), '');
      final key = await _key();
      final pulled = await SyncEngine(
        await DatabaseProvider.db,
        HttpSyncServer(kSyncUrl, key),
        account: sha256.convert(utf8.encode(key)).toString().substring(0, 16),
        readPrefs: Settings.syncedPrefs,
        writePrefs: Settings.applySyncedPrefs,
        ddrCode: rival.length == 8 ? rival : null,
      ).run();
      if (pulled) CloudSync.pulled.value++;
      _last = DateTime.now();
      await Settings.setString(
          Settings.cloudSyncedAtKey, _last!.toIso8601String());
    } finally {
      running.value = false;
    }
  }

  static Future<void> setEnabled(bool on) async {
    await Settings.setInt(Settings.cloudSyncOnKey, on ? 1 : 0);
    if (on) await sync(force: true);
  }

  /// Deletes this account's copy on the server and turns sync off. The next
  /// time it's turned on, everything here goes up again under a new key
  /// (the engine starts over for an account it hasn't synced).
  static Future<void> deleteCloudCopy() async {
    await _running;
    await HttpSyncServer(kSyncUrl, await _key()).deleteAll();
    await Settings.setInt(Settings.cloudSyncOnKey, 0);
    await Settings.setString(Settings.cloudSyncedAtKey, '');
    await _store(_newKey());
  }

  static const _keychain = FlutterSecureStorage(
      iOptions: IOSOptions(
          synchronizable: true,
          accessibility: KeychainAccessibility.first_unlock));
  static const _keyName = 'cloudSyncKey';
  static final _keyFormat = RegExp(r'^[A-Za-z0-9_-]{43}$');

  // The Keychain copy wins: on a new iPhone it arrives through iCloud
  // Keychain, before any preferences do.
  static Future<String> _key() async {
    String? key;
    if (Platform.isIOS) {
      key = await _keychain.read(key: _keyName).catchError((_) => null);
    }
    if (key == null || !_keyFormat.hasMatch(key)) {
      key = Settings.getString(Settings.cloudSyncKeyKey);
    }
    if (!_keyFormat.hasMatch(key)) key = _newKey();
    await _store(key);
    return key;
  }

  static Future<void> _store(String key) async {
    await Settings.setString(Settings.cloudSyncKeyKey, key);
    if (Platform.isIOS) {
      await _keychain
          .write(key: _keyName, value: key)
          .catchError((Object e) => debugPrint('Keychain: $e'));
    }
  }

  static String _newKey() {
    final random = Random.secure();
    return base64Url.encode(
        [for (var i = 0; i < 32; i++) random.nextInt(256)]).replaceAll('=', '');
  }
}
