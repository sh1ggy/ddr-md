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
    return await openDatabase(path, version: 1, onCreate: (db, version) {
      return db.execute(
        'CREATE TABLE notes(date string PRIMARY KEY, contents TEXT)',
      );
    });
  }

  static addNote(Note note) async {
    final db = await _instance;
    var raw = await db.insert(
      "notes",
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return raw;
  }

  static Future<List<Note>> getAllNotes() async {
    final db = await _instance;
    var response = await db.query("notes");
    List<Note> list = response.map((c) => Note.fromMap(c)).toList();
    return list;
  }
}
