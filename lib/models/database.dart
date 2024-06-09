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

  static Future<Database> getDatabaseInstance() async {
    String path = join(await getDatabasesPath(), "ddr_database.db");
    return await openDatabase(path, version: 2, onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE IF NOT EXISTS notes(date TEXT PRIMARY KEY, contents TEXT, songTitle TEXT)',
      );
      await db.execute(
          'CREATE TABLE IF NOT EXISTS favorites(id INTEGER PRIMARY KEY, isFav INT, songTitle TEXT)');
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

  // Get favorites list
  static Future<List<Favorite>> getAllFavorites() async {
    final db = await _instance;
    var response = await db.query("favorites");
    List<Favorite> list = response.map((c) => Favorite.fromMap(c)).toList();
    return list;
  }

  // Delete favorite from the database
  static deleteFavorite(Favorite fav) async {
    final db = await _instance;
    Favorite deletedFav =
        Favorite(id: fav.id, isFav: false, songTitle: fav.songTitle);
    var raw =
        await db.delete("favorites", where: "id = ?", whereArgs: [fav.id]);
    return deletedFav;
  }

  static Future<Favorite?> getFavoriteBySong(String songTitleTranslit) async {
    final db = await _instance;
    var response = await db.query("favorites",
        where: "songTitle = ?", whereArgs: [songTitleTranslit]);
    var list = response.map((c) => Favorite.fromMap(c)).firstOrNull;
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
        songTitle: note.songTitle);
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

  // Get all notes from the database for a specific song
  static Future<List<Note>> getAllNotesBySong(String songTitleTranslit) async {
    final db = await _instance;
    var response = await db
        .query("notes", where: "songTitle = ?", whereArgs: [songTitleTranslit]);
    List<Note> list = response.map((c) => Note.fromMap(c)).toList();
    return list;
  }

  static Future<Note?> getPrevNoteBySong(String songTitleTranslit) async {
    final db = await _instance;
    var response = await db
        .query("notes", where: "songTitle = ?", whereArgs: [songTitleTranslit]);
    if (response.isEmpty) return null;
    Note prevNote = response.map((c) => Note.fromMap(c)).toList().last;
    return prevNote;
  }
}
