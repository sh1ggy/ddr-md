import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseProvider {
  static Future<Database> get _instance async =>
      _database ??= await getDatabaseInstance();
  static Database? _database;

  static Future<Database?> init() async {
    _database = await _instance;
    return _database;
  }

  // v6 schema. `scores` and `notes` carry a UUID `id` as their stable identity,
  // with the timestamp demoted to an ordinary editable column (`playedAt` /
  // `createdAt`) used only for display and sorting. `favorites` keeps its
  // integer key and its natural (songTitle, mode) uniqueness.
  static const String _scoresDdl =
      'CREATE TABLE IF NOT EXISTS scores(id TEXT PRIMARY KEY, playedAt TEXT NOT NULL, source TEXT NOT NULL DEFAULT \'camera\', songTitle TEXT, mode TEXT NOT NULL, difficulty TEXT, username TEXT, flare TEXT, score INT, marvelous INT, perfect INT, great INT, good INT, miss INT, maxCombo INT, imagePath TEXT NOT NULL DEFAULT \'\')';
  static const String _notesDdl =
      'CREATE TABLE IF NOT EXISTS notes(id TEXT PRIMARY KEY, createdAt TEXT NOT NULL, contents TEXT, songTitle TEXT, mode TEXT NOT NULL)';
  static const String _favoritesDdl =
      'CREATE TABLE IF NOT EXISTS favorites(id INTEGER PRIMARY KEY, isFav INT, songTitle TEXT, mode TEXT NOT NULL)';

  static Future<void> _createSchema(Database db) async {
    await db.execute(_notesDdl);
    await db.execute(_favoritesDdl);
    await db.execute(_scoresDdl);
  }

  static Future<Database> getDatabaseInstance() async {
    String path = join(await getDatabasesPath(), "ddr_database.db");
    return await openDatabase(path, version: 6, onCreate: (db, version) async {
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
    });
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
