import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/parity_labels.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DatabaseProvider {
  static Future<Database> get _instance async =>
      _database ??= await getDatabaseInstance();
  static Database? _database;

  static Future<Database?> init() async {
    _database = await _instance;
    return _database;
  }

  // v7 schema. `scores` and `notes` carry a UUID `id` as their stable identity,
  // with the timestamp demoted to an ordinary editable column (`playedAt` /
  // `createdAt`) used only for display and sorting. `favorites` keeps its
  // integer key and its natural (songTitle, mode) uniqueness.
  static const String _scoresDdl =
      'CREATE TABLE IF NOT EXISTS scores(id TEXT PRIMARY KEY, playedAt TEXT NOT NULL, source TEXT NOT NULL DEFAULT \'camera\', songTitle TEXT, mode TEXT NOT NULL, difficulty TEXT, username TEXT, flare TEXT, score INT, exScore INT, marvelous INT, perfect INT, great INT, good INT, miss INT, maxCombo INT, imagePath TEXT NOT NULL DEFAULT \'\')';
  static const String _notesDdl =
      'CREATE TABLE IF NOT EXISTS notes(id TEXT PRIMARY KEY, createdAt TEXT NOT NULL, contents TEXT, songTitle TEXT, mode TEXT NOT NULL)';
  static const String _favoritesDdl =
      'CREATE TABLE IF NOT EXISTS favorites(id INTEGER PRIMARY KEY, isFav INT, songTitle TEXT, mode TEXT NOT NULL)';

  // v8: hand-set feet for chart notes (the parity labeller). One row per note,
  // keyed by beat and unturned column; chartHash marks rows from an older
  // version of the chart as stale.
  static const String _parityPinsDdl =
      'CREATE TABLE IF NOT EXISTS parity_pins(song TEXT NOT NULL, mode TEXT NOT NULL, difficulty TEXT NOT NULL, chartHash TEXT NOT NULL, beat REAL NOT NULL, col INT NOT NULL, foot TEXT NOT NULL, PRIMARY KEY(song, mode, difficulty, beat, col))';

  // v9: saved chart sections (Snippets tab).
  static const String _snippetsDdl =
      'CREATE TABLE IF NOT EXISTS snippets(id TEXT PRIMARY KEY, createdAt TEXT NOT NULL, song TEXT NOT NULL, mode TEXT NOT NULL, difficulty TEXT NOT NULL, chartHash TEXT NOT NULL, startBeat REAL NOT NULL, endBeat REAL NOT NULL, label TEXT NOT NULL DEFAULT \'\')';

  // v10: named cabinets, each play's result-screen timing, and hard sync
  // overrides per chart, cabinet and side.
  static const String _cabinetsDdl =
      'CREATE TABLE IF NOT EXISTS cabinets(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)';
  static const String _timingPlaysDdl =
      'CREATE TABLE IF NOT EXISTS timing_plays(id TEXT PRIMARY KEY, playedAt TEXT NOT NULL, cabinetId INT NOT NULL, side TEXT NOT NULL, song TEXT NOT NULL, mode TEXT NOT NULL, difficulty TEXT NOT NULL, songOffsetMs REAL NOT NULL, syncUsedMs REAL NOT NULL, averageMs REAL NOT NULL, variationMs REAL NOT NULL)';
  static const String _syncOverridesDdl =
      'CREATE TABLE IF NOT EXISTS sync_overrides(cabinetId INT NOT NULL, side TEXT NOT NULL, song TEXT NOT NULL, mode TEXT NOT NULL, difficulty TEXT NOT NULL, ms REAL NOT NULL, PRIMARY KEY(cabinetId, side, song, mode, difficulty))';

  // v12: each chart's best from a source (manual or e-amusement), one row per
  // source and chart. See [ScoreRecord].
  static const String _scoreRecordsDdl =
      'CREATE TABLE IF NOT EXISTS score_records(id TEXT PRIMARY KEY, source TEXT NOT NULL, song TEXT, konamiId TEXT, title TEXT NOT NULL, mode TEXT NOT NULL, difficulty TEXT NOT NULL, score INT, exScore INT, rank TEXT NOT NULL DEFAULT \'\', clearLamp TEXT, flareRank TEXT NOT NULL DEFAULT \'\', flareSkill INT, maxCombo INT, playedAt TEXT, updatedAt TEXT NOT NULL)';
  static const String _scoreRecordsIndex =
      'CREATE INDEX IF NOT EXISTS score_records_chart ON score_records(song, mode, difficulty)';

  // v13: every play the recent plays page has listed, one row per play.
  static const String _recentPlaysDdl =
      'CREATE TABLE IF NOT EXISTS recent_plays(konamiId TEXT NOT NULL, title TEXT NOT NULL, song TEXT, mode TEXT NOT NULL, difficulty TEXT NOT NULL, playedAt TEXT NOT NULL, score INT, PRIMARY KEY(konamiId, mode, difficulty, playedAt))';

  static Future<void> _createSchema(Database db) async {
    await db.execute(_notesDdl);
    await db.execute(_favoritesDdl);
    await db.execute(_scoresDdl);
    await db.execute(_parityPinsDdl);
    await db.execute(_snippetsDdl);
    await _createSessionSchema(db);
    await _upgradeToVenues(db);
    await _createScoreRecords(db);
    await db.execute(_recentPlaysDdl);
  }

  static Future<void> _createScoreRecords(Database db) async {
    await db.execute(_scoreRecordsDdl);
    await db.execute(_scoreRecordsIndex);
  }

  static Future<void> _createSessionSchema(Database db) async {
    await db.execute(_cabinetsDdl);
    await db.execute(_timingPlaysDdl);
    await db.execute(_syncOverridesDdl);
  }

  // v11: cabinets belong to a venue, and plays to a credit (one cabinet +
  // side) within a session at that venue. Each v10 cabinet becomes a venue
  // of the same name with one unnamed cabinet.
  static Future<void> _upgradeToVenues(Database db) async {
    // Already done: a build on an older schema (another worktree's, sharing
    // this app's database) can wind user_version back without undoing it.
    final plays = await db.rawQuery('PRAGMA table_info(timing_plays)');
    if (plays.any((c) => c['name'] == 'creditId')) return;
    await db.execute(
        'CREATE TABLE IF NOT EXISTS venues(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS sessions(id TEXT PRIMARY KEY, venueId INT NOT NULL, startedAt TEXT NOT NULL, endedAt TEXT)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS credits(id TEXT PRIMARY KEY, sessionId TEXT NOT NULL, number INT NOT NULL, cabinetId INT NOT NULL, side TEXT NOT NULL, startedAt TEXT NOT NULL)');
    await db.execute('ALTER TABLE timing_plays ADD COLUMN creditId TEXT');
    // Rebuilt rather than altered: v10's UNIQUE name can't be dropped, and
    // every venue's lone cabinet is named ''.
    await db.execute(
        'CREATE TABLE cabinets_v11(id INTEGER PRIMARY KEY AUTOINCREMENT, venueId INT NOT NULL, name TEXT NOT NULL DEFAULT \'\')');
    for (final c in await db.query('cabinets')) {
      final venueId = await db.insert('venues', {'name': c['name']});
      await db.insert(
          'cabinets_v11', {'id': c['id'], 'venueId': venueId, 'name': ''});
    }
    await db.execute('DROP TABLE cabinets');
    await db.execute('ALTER TABLE cabinets_v11 RENAME TO cabinets');
  }

  // Builds from every worktree share one app container; each worktree passes
  // its own --dart-define=DB_NAME so an older schema can't touch the main one.
  static const _dbName =
      String.fromEnvironment('DB_NAME', defaultValue: 'ddr_database.db');

  static Future<Database> getDatabaseInstance() async {
    String path = join(await getDatabasesPath(), _dbName);
    return await openDatabase(path, version: 13, onCreate: (db, version) async {
      await _createSchema(db);
    }, onUpgrade: (db, oldVersion, newVersion) async {
      // The app is not yet released and the pre-v6 tables overloaded their
      // timestamp as the primary key. Rather than migrate that debt forward,
      // v6 drops and recreates scores/notes/favorites with the clean schema.
      // Any local dev rows are discarded.
      if (oldVersion < 6) {
        await db.execute('DROP TABLE IF EXISTS scores');
        await db.execute('DROP TABLE IF EXISTS notes');
        await db.execute('DROP TABLE IF EXISTS favorites');
        await _createSchema(db);
      }
      // v7: EX score OCR'd from the results screen. Nullable like the other
      // count columns; pre-v7 rows simply have no reading.
      if (oldVersion == 6) {
        await db.execute('ALTER TABLE scores ADD COLUMN exScore INT');
      }
      if (oldVersion < 8) await db.execute(_parityPinsDdl);
      if (oldVersion < 9) await db.execute(_snippetsDdl);
      if (oldVersion < 10) await _createSessionSchema(db);
      if (oldVersion < 11) await _upgradeToVenues(db);
      if (oldVersion < 12) await _createScoreRecords(db);
      if (oldVersion < 13) await db.execute(_recentPlaysDdl);
    });
  }

  // -- SESSION FUNCTIONS
  static Future<List<Venue>> getVenues() async {
    final db = await _instance;
    return [
      for (final r in await db.query("venues", orderBy: "name"))
        Venue.fromMap(r)
    ];
  }

  // A new venue comes with its one cabinet.
  static Future<Venue> addVenue(String name) async {
    final db = await _instance;
    final id = await db.insert("venues", {'name': name});
    await db.insert("cabinets", {'venueId': id, 'name': ''});
    return Venue(id, name);
  }

  static Future<List<Cabinet>> getCabinets(int venueId) async {
    final db = await _instance;
    final rows = await db.rawQuery(
        'SELECT c.id, c.venueId, c.name, v.name AS venueName FROM cabinets c '
        'JOIN venues v ON v.id = c.venueId WHERE c.venueId = ? ORDER BY c.id',
        [venueId]);
    return [for (final r in rows) Cabinet.fromMap(r)];
  }

  static Future<Cabinet> addCabinet(Venue venue, String name) async {
    final db = await _instance;
    final id = await db.insert("cabinets", {'venueId': venue.id, 'name': name});
    return Cabinet(id, venue.id, venue.name, name);
  }

  static const _sessionSelect =
      'SELECT s.*, v.name AS venueName FROM sessions s '
      'JOIN venues v ON v.id = s.venueId';

  static Future<PlaySession> startSession(Venue venue) async {
    final db = await _instance;
    final session = PlaySession(const Uuid().v4(), venue, DateTime.now(), null);
    await db.insert("sessions", {
      'id': session.id,
      'venueId': venue.id,
      'startedAt': session.startedAt.toIso8601String(),
    });
    return session;
  }

  static Future<void> endSession(String id) async {
    final db = await _instance;
    await db.update("sessions", {'endedAt': DateTime.now().toIso8601String()},
        where: "id = ?", whereArgs: [id]);
  }

  static Future<PlaySession?> getSession(String id) async {
    final db = await _instance;
    final rows = await db.rawQuery('$_sessionSelect WHERE s.id = ?', [id]);
    return rows.isEmpty ? null : PlaySession.fromMap(rows.first);
  }

  // Newest first.
  // Newest first; every session when [limit] is null.
  static Future<List<PlaySession>> getSessions({int? limit}) async {
    final db = await _instance;
    final rows = await db.rawQuery(
        '$_sessionSelect ORDER BY s.startedAt DESC LIMIT ?', [limit ?? -1]);
    return [for (final r in rows) PlaySession.fromMap(r)];
  }

  static Future<void> saveCredit(Credit credit) async {
    final db = await _instance;
    await db.insert("credits", {
      'id': credit.id,
      'sessionId': credit.sessionId,
      'number': credit.number,
      'cabinetId': credit.cabinet.id,
      'side': credit.side.name,
      'startedAt': credit.startedAt.toIso8601String(),
    });
  }

  // A session's credits, newest first.
  static Future<List<Credit>> getCredits(String sessionId) async {
    final db = await _instance;
    final rows = await db.rawQuery(
        'SELECT cr.*, c.venueId, c.name AS cabinetName, v.name AS venueName '
        'FROM credits cr JOIN cabinets c ON c.id = cr.cabinetId '
        'JOIN venues v ON v.id = c.venueId '
        'WHERE cr.sessionId = ? ORDER BY cr.number DESC',
        [sessionId]);
    return [for (final r in rows) Credit.fromMap(r)];
  }

  // Deletes cascade to the plays logged under them.
  static Future<void> deleteCredit(String id) async {
    final db = await _instance;
    await db.delete("timing_plays", where: "creditId = ?", whereArgs: [id]);
    await db.delete("credits", where: "id = ?", whereArgs: [id]);
  }

  static Future<void> deleteSession(String id) async {
    final db = await _instance;
    await db.delete("timing_plays",
        where: "creditId IN (SELECT id FROM credits WHERE sessionId = ?)",
        whereArgs: [id]);
    await db.delete("credits", where: "sessionId = ?", whereArgs: [id]);
    await db.delete("sessions", where: "id = ?", whereArgs: [id]);
  }

  static Future<void> deleteCabinet(int id) async {
    final db = await _instance;
    for (final table in ["timing_plays", "sync_overrides", "credits"]) {
      await db.delete(table, where: "cabinetId = ?", whereArgs: [id]);
    }
    await db.delete("cabinets", where: "id = ?", whereArgs: [id]);
  }

  static Future<void> deleteVenue(int id) async {
    final db = await _instance;
    for (final c
        in await db.query("cabinets", where: "venueId = ?", whereArgs: [id])) {
      await deleteCabinet(c['id'] as int);
    }
    for (final s
        in await db.query("sessions", where: "venueId = ?", whereArgs: [id])) {
      await deleteSession(s['id'] as String);
    }
    await db.delete("venues", where: "id = ?", whereArgs: [id]);
  }

  // Every play logged in a session's credits, newest first.
  static Future<List<TimingPlay>> getSessionPlays(String sessionId) async {
    final db = await _instance;
    final rows = await db.rawQuery(
        'SELECT p.* FROM timing_plays p JOIN credits cr ON cr.id = p.creditId '
        'WHERE cr.sessionId = ? ORDER BY p.playedAt DESC',
        [sessionId]);
    return [for (final r in rows) TimingPlay.fromMap(r)];
  }

  static Future<void> saveTimingPlay(TimingPlay play) async {
    final db = await _instance;
    await db.insert("timing_plays", play.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteTimingPlay(String id) async {
    final db = await _instance;
    await db.delete("timing_plays", where: "id = ?", whereArgs: [id]);
  }

  // Every play on one cabinet + side, newest first.
  static Future<List<TimingPlay>> getTimingPlays(
      int cabinetId, PadSide side) async {
    final db = await _instance;
    final rows = await db.query("timing_plays",
        where: "cabinetId = ? AND side = ?",
        whereArgs: [cabinetId, side.name],
        orderBy: "playedAt DESC");
    return [for (final r in rows) TimingPlay.fromMap(r)];
  }

  static Future<double?> getSyncOverride(int cabinetId, PadSide side,
      String song, Modes mode, String difficulty) async {
    final db = await _instance;
    final rows = await db.query("sync_overrides",
        where:
            "cabinetId = ? AND side = ? AND song = ? AND mode = ? AND difficulty = ?",
        whereArgs: [cabinetId, side.name, song, mode.name, difficulty]);
    return rows.isEmpty ? null : (rows.first['ms'] as num).toDouble();
  }

  // A null [ms] clears the override.
  static Future<void> setSyncOverride(int cabinetId, PadSide side, String song,
      Modes mode, String difficulty, double? ms) async {
    final db = await _instance;
    final key = {
      'cabinetId': cabinetId,
      'side': side.name,
      'song': song,
      'mode': mode.name,
      'difficulty': difficulty,
    };
    if (ms == null) {
      await db.delete("sync_overrides",
          where: key.keys.map((k) => "$k = ?").join(" AND "),
          whereArgs: key.values.toList());
    } else {
      await db.insert("sync_overrides", {...key, 'ms': ms},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // -- SCORE RECORD FUNCTIONS
  // Insert or replace by id, all in one transaction.
  static Future<void> saveScoreRecords(List<ScoreRecord> records) async {
    final db = await _instance;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in records) {
        batch.insert("score_records", r.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  // Every source's records for one song and mode.
  static Future<List<ScoreRecord>> getScoreRecordsBySong(
      String song, Modes mode) async {
    final db = await _instance;
    final rows = await db.query("score_records",
        where: "song = ? AND mode = ?", whereArgs: [song, mode.name]);
    return [for (final r in rows) ScoreRecord.fromMap(r)];
  }

  static Future<List<ScoreRecord>> getScoreRecords(
      ScoreRecordSource source) async {
    final db = await _instance;
    final rows = await db
        .query("score_records", where: "source = ?", whereArgs: [source.name]);
    return [for (final r in rows) ScoreRecord.fromMap(r)];
  }

  static Future<int> countScoreRecords(ScoreRecordSource source) async {
    final db = await _instance;
    return Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM score_records WHERE source = ?',
            [source.name])) ??
        0;
  }

  static Future<void> deleteScoreRecords(ScoreRecordSource source) async {
    final db = await _instance;
    await db
        .delete("score_records", where: "source = ?", whereArgs: [source.name]);
  }

  // -- RECENT PLAY FUNCTIONS
  // Replaces by play, so a later sync can fill in a song match.
  static Future<void> saveRecentPlays(List<RecentPlay> plays) async {
    final db = await _instance;
    final batch = db.batch();
    for (final p in plays) {
      batch.insert("recent_plays", p.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // Newest first.
  static Future<List<RecentPlay>> getRecentPlays({int? limit}) async {
    final db = await _instance;
    final rows =
        await db.query("recent_plays", orderBy: "playedAt DESC", limit: limit);
    return [for (final r in rows) RecentPlay.fromMap(r)];
  }

  static Future<int> countRecentPlays() async {
    final db = await _instance;
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM recent_plays')) ??
        0;
  }

  // -- SNIPPET FUNCTIONS
  // Insert or replace, keyed by id, so an edited snippet keeps its place.
  static Future<void> saveSnippet(Snippet snippet) async {
    final db = await _instance;
    await db.insert("snippets", snippet.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteSnippet(String id) async {
    final db = await _instance;
    await db.delete("snippets", where: "id = ?", whereArgs: [id]);
  }

  // Newest first.
  static Future<List<Snippet>> getAllSnippets() async {
    final db = await _instance;
    final rows = await db.query("snippets", orderBy: "createdAt DESC");
    return [for (final r in rows) Snippet.fromMap(r)];
  }

  // -- PARITY PIN FUNCTIONS
  // Pins for one chart, skipping any saved against a different chartHash.
  static Future<List<ParityPin>> getParityPins(
      ChartRef ref, String chartHash) async {
    final db = await _instance;
    final rows = await db.query("parity_pins",
        where: "song = ? AND mode = ? AND difficulty = ? AND chartHash = ?",
        whereArgs: [ref.song, ref.mode, ref.difficulty, chartHash]);
    return [
      for (final r in rows)
        (
          r["beat"] as double,
          r["col"] as int,
          r["foot"] == "L" ? ParityFoot.left : ParityFoot.right,
        )
    ];
  }

  // Every chart's pins, keyed by chart and the note hash they were set against.
  static Future<Map<(ChartRef, String), List<ParityPin>>>
      getAllParityPins() async {
    final db = await _instance;
    final out = <(String, String, String, String), List<ParityPin>>{};
    for (final r in await db.query("parity_pins")) {
      out.putIfAbsent((
        r["song"] as String,
        r["mode"] as String,
        r["difficulty"] as String,
        r["chartHash"] as String
      ), () => []).add((
        r["beat"] as double,
        r["col"] as int,
        r["foot"] == "L" ? ParityFoot.left : ParityFoot.right,
      ));
    }
    return {
      for (final MapEntry(key: (song, mode, diff, hash), value: pins)
          in out.entries)
        (ChartRef(song, mode, diff), hash): pins
    };
  }

  static Future<void> setParityPin(
      ChartRef ref, String chartHash, ParityPin pin) async {
    final db = await _instance;
    final (beat, col, foot) = pin;
    await db.insert(
      "parity_pins",
      {
        "song": ref.song,
        "mode": ref.mode,
        "difficulty": ref.difficulty,
        "chartHash": chartHash,
        "beat": beat,
        "col": col,
        "foot": foot == ParityFoot.left ? "L" : "R",
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deleteParityPin(
      ChartRef ref, double beat, int col) async {
    final db = await _instance;
    await db.delete("parity_pins",
        where:
            "song = ? AND mode = ? AND difficulty = ? AND beat = ? AND col = ?",
        whereArgs: [ref.song, ref.mode, ref.difficulty, beat, col]);
  }

  // -- FAVS FUNCTIONS
  // Add favorite to the database
  static addFavorite(Favorite favorite) async {
    final db = await _instance;
    var raw = await db.insert(
      "favorites",
      favorite.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return raw;
  }

  // Get favorites list for a play mode
  static Future<List<Favorite>> getAllFavorites(Modes mode) async {
    final db = await _instance;
    var response =
        await db.query("favorites", where: "mode = ?", whereArgs: [mode.name]);
    List<Favorite> list = response.map((c) => Favorite.fromMap(c)).toList();
    return list;
  }

  // Delete favorite from the database
  static deleteFavorite(Favorite fav) async {
    final db = await _instance;
    Favorite deletedFav = Favorite(
        id: fav.id, isFav: false, songTitle: fav.songTitle, mode: fav.mode);
    // Favourites is one to one with song per mode so this where condition
    // reflects that.
    await db.delete("favorites",
        where: "songTitle = ? AND mode = ?",
        whereArgs: [fav.songTitle, fav.mode.name]);
    return deletedFav;
  }

  static Future<Favorite?> getFavoriteBySong(
      String songTitleTranslit, Modes mode) async {
    final db = await _instance;
    var response = await db.query("favorites",
        where: "songTitle = ? AND mode = ?",
        whereArgs: [songTitleTranslit, mode.name]);
    var list = response.map((c) => Favorite.fromMap(c)).firstOrNull;
    return list;
  }

  // --- SCORES FUNCTIONS
  // Add score to the database
  static addScore(Score score) async {
    final db = await _instance;
    var raw = await db.insert(
      "scores",
      score.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return raw;
  }

  // Update an existing score in place, keyed by its id (the primary key).
  static updateScore(Score score) async {
    final db = await _instance;
    var raw = await db.update("scores", score.toMap(),
        where: "id = ?", whereArgs: [score.id]);
    return raw;
  }

  // Get all scores from the database for a specific song and play mode
  static Future<List<Score>> getAllScoresBySong(
      String songTitleTranslit, Modes mode) async {
    final db = await _instance;
    var response = await db.query("scores",
        where: "songTitle = ? AND mode = ?",
        whereArgs: [songTitleTranslit, mode.name],
        orderBy: "playedAt DESC");
    List<Score> list = response.map((c) => Score.fromMap(c)).toList();
    return list;
  }

  // Get the most recent score from the database for a specific song and play mode
  static Future<Score?> getLatestScoreBySong(
      String songTitleTranslit, Modes mode) async {
    final db = await _instance;
    var response = await db.query("scores",
        where: "songTitle = ? AND mode = ?",
        whereArgs: [songTitleTranslit, mode.name],
        orderBy: "playedAt DESC",
        limit: 1);
    if (response.isEmpty) return null;
    return Score.fromMap(response.first);
  }

  // Get all scores from the database (across modes)
  static Future<List<Score>> getAllScores() async {
    final db = await _instance;
    var response = await db.query("scores", orderBy: "playedAt DESC");
    List<Score> list = response.map((c) => Score.fromMap(c)).toList();
    return list;
  }

  // --- NOTES FUNCTIONS
  // Add note to database
  static addNote(Note note) async {
    final db = await _instance;
    var raw = await db.insert(
      "notes",
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return raw;
  }

  // Update an existing note's contents in place, keyed by its id. The note's
  // identity and createdAt are preserved — only the contents change.
  static updateNote(Note note, String newContents) async {
    final db = await _instance;
    var raw = await db.update("notes", {'contents': newContents},
        where: "id = ?", whereArgs: [note.id]);
    return raw;
  }

  // Delete note from the database, keyed by its id.
  static deleteNote(String id) async {
    final db = await _instance;
    var raw = await db.delete("notes", where: "id = ?", whereArgs: [id]);
    return raw;
  }

  // Get all notes from the database - UNUSED
  static Future<List<Note>> getAllNotes() async {
    final db = await _instance;
    var response = await db.query("notes");
    List<Note> list = response.map((c) => Note.fromMap(c)).toList();
    return list;
  }

  // Get all notes from the database for a specific song and play mode
  static Future<List<Note>> getAllNotesBySong(
      String songTitleTranslit, Modes mode) async {
    final db = await _instance;
    var response = await db.query("notes",
        where: "songTitle = ? AND mode = ?",
        whereArgs: [songTitleTranslit, mode.name]);
    List<Note> list = response.map((c) => Note.fromMap(c)).toList();
    return list;
  }

  static Future<Note?> getLatestNoteBySong(
      String songTitleTranslit, Modes mode) async {
    final db = await _instance;
    var response = await db.query("notes",
        where: "songTitle = ? AND mode = ?",
        whereArgs: [songTitleTranslit, mode.name],
        orderBy: "createdAt ASC");
    if (response.isEmpty) return null;
    Note latestNote = response.map((c) => Note.fromMap(c)).toList().last;
    return latestNote;
  }
}
