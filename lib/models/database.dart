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
      print('test');
      await db.execute(
        'CREATE TABLE IF NOT EXISTS notes(date TEXT PRIMARY KEY, contents TEXT, songTitle TEXT)',
      );
      print('test22');
      await db.execute(
          'CREATE TABLE IF NOT EXISTS favorites(id INTEGER PRIMARY KEY, isFav INT, songTitle TEXT)');
    });
  }

  // -- FAVS FUNCTIONS
  static addFavorite(Favorite favorite) async {
    final db = await _instance;
    var raw = await db.insert(
      "favorites",
      favorite.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return raw;
  }

  static Future<List<Favorite>> getAllFavorites() async {
    final db = await _instance;
    var response = await db.query("favorites");
    List<Favorite> list = response.map((c) => Favorite.fromMap(c)).toList();
    return list;
  }

  static updateFavorite(Favorite oldFav) async {
    final db = await _instance;
    Favorite updatedFavorite = Favorite(
        id: oldFav.id, isFav: !oldFav.isFav, songTitle: oldFav.songTitle);
    var raw = await db.update("favorites", updatedFavorite.toMap(),
        where: "id = ?",
        whereArgs: [oldFav.id],
        conflictAlgorithm: ConflictAlgorithm.replace);
    return updatedFavorite;
  }

  static Future<Favorite?> getFavoriteBySong(String songTitleTranslit) async {
    final db = await _instance;
    var response = await db.query("favorites",
        where: "songTitle = ?", whereArgs: [songTitleTranslit]);
    var list = response.map((c) => Favorite.fromMap(c)).firstOrNull;
    return list;
  }

  // --- NOTES FUNCTIONS
  static addNote(Note note) async {
    final db = await _instance;
    var raw = await db.insert(
      "notes",
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return raw;
  }

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

  static deleteNote(String date) async {
    final db = await _instance;
    var raw = await db.delete("notes", where: "date = ?", whereArgs: [date]);
    return raw;
  }

  static Future<List<Note>> getAllNotes() async {
    final db = await _instance;
    var response = await db.query("notes");
    List<Note> list = response.map((c) => Note.fromMap(c)).toList();
    return list;
  }

  static Future<List<Note>> getAllNotesBySong(String songTitleTranslit) async {
    final db = await _instance;
    var response = await db
        .query("notes", where: "songTitle = ?", whereArgs: [songTitleTranslit]);
    List<Note> list = response.map((c) => Note.fromMap(c)).toList();
    return list;
  }
}
