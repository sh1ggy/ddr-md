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

  static const String _scoresDdl =
      'CREATE TABLE IF NOT EXISTS scores(date TEXT PRIMARY KEY, songTitle TEXT, difficulty TEXT, username TEXT, flare TEXT, score INT, marvelous INT, perfect INT, great INT, good INT, miss INT, maxCombo INT)';

  // Favourites, notes and scores are tracked per play mode (v4); rows saved
  // before the column existed default to singles.
  static const String _addModeColumnDdl =
      "ADD COLUMN mode TEXT NOT NULL DEFAULT 'singles'";
  static const List<String> _perModeTables = ['notes', 'favorites', 'scores'];

  static Future<Database> getDatabaseInstance() async {
    String path = join(await getDatabasesPath(), "ddr_database.db");
    return await openDatabase(path, version: 4, onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE IF NOT EXISTS notes(date TEXT PRIMARY KEY, contents TEXT, songTitle TEXT)',
      );
      await db.execute(
          'CREATE TABLE IF NOT EXISTS favorites(id INTEGER PRIMARY KEY, isFav INT, songTitle TEXT)');
      await db.execute(_scoresDdl);
      for (final table in _perModeTables) {
        await db.execute('ALTER TABLE $table $_addModeColumnDdl');
      }
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 3) {
        await db.execute(_scoresDdl);
      }
      if (oldVersion < 4) {
        for (final table in _perModeTables) {
          await db.execute('ALTER TABLE $table $_addModeColumnDdl');
        }
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

  // Get all scores from the database for a specific song and play mode
  static Future<List<Score>> getAllScoresBySong(
      String songTitleTranslit, Modes mode) async {
    final db = await _instance;
    var response = await db.query("scores",
        where: "songTitle = ? AND mode = ?",
        whereArgs: [songTitleTranslit, mode.name],
        orderBy: "date DESC");
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
        orderBy: "date DESC",
        limit: 1);
    if (response.isEmpty) return null;
    return Score.fromMap(response.first);
  }

  // Get all scores from the database (across modes)
  static Future<List<Score>> getAllScores() async {
    final db = await _instance;
    var response = await db.query("scores", orderBy: "date DESC");
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

  // Update existing note in the database
  static updateNote(Note note, String newContents) async {
    final db = await _instance;
    Note updatedNote = Note(
        contents: newContents,
        date: DateTime.now().toIso8601String(),
        songTitle: note.songTitle,
        mode: note.mode);
    var raw = await db.update("notes", updatedNote.toMap(),
        where: "date = ?", whereArgs: [note.date]);
    return raw;
  }

  // Delete note from the database
  static deleteNote(String date) async {
    final db = await _instance;
    var raw = await db.delete("notes", where: "date = ?", whereArgs: [date]);
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
        orderBy: "date ASC");
    if (response.isEmpty) return null;
    Note latestNote = response.map((c) => Note.fromMap(c)).toList().last;
    return latestNote;
  }
}
