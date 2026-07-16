import 'package:ddr_md/components/song_json.dart';

// Rows saved before the mode column existed (db v4) default to singles.
Modes _modeFromMap(Map<String, dynamic> json) =>
    Modes.values.asNameMap()[json["mode"]] ?? Modes.singles;

class Note {
  final String date;
  final String contents;
  final String songTitle;
  final Modes mode;

  const Note({
    required this.date,
    required this.contents,
    required this.songTitle,
    required this.mode,
  });

  Map<String, Object?> toMap() {
    return {
      'date': date,
      'contents': contents,
      'songTitle': songTitle,
      'mode': mode.name,
    };
  }

  factory Note.fromMap(Map<String, dynamic> json) => Note(
        date: json["date"],
        contents: json["contents"],
        songTitle: json["songTitle"],
        mode: _modeFromMap(json),
      );

  @override
  String toString() {
    return 'Note{date: $date, contents: $contents, song: $songTitle, mode: ${mode.name}}';
  }
}

class Score {
  final String date;
  // titletranslit of the matched song, matching the notes/favorites key.
  final String songTitle;
  final Modes mode;
  final String difficulty;
  final String username;
  final String flare;
  final int? score;
  final int? marvelous;
  final int? perfect;
  final int? great;
  final int? good;
  final int? miss;
  final int? maxCombo;
  // Path of the proof image captured when the score was saved, relative to
  // the app documents dir (e.g. "scores/xxx.png") — the documents dir itself
  // moves across iOS app updates so only the relative part is stored. Empty
  // when no image was available at save time (rows from before v5 included).
  final String imagePath;

  const Score({
    required this.date,
    required this.songTitle,
    required this.mode,
    this.difficulty = '',
    this.username = '',
    this.flare = '',
    this.score,
    this.marvelous,
    this.perfect,
    this.great,
    this.good,
    this.miss,
    this.maxCombo,
    this.imagePath = '',
  });

  Map<String, Object?> toMap() {
    return {
      'date': date,
      'songTitle': songTitle,
      'mode': mode.name,
      'difficulty': difficulty,
      'username': username,
      'flare': flare,
      'score': score,
      'marvelous': marvelous,
      'perfect': perfect,
      'great': great,
      'good': good,
      'miss': miss,
      'maxCombo': maxCombo,
      'imagePath': imagePath,
    };
  }

  factory Score.fromMap(Map<String, dynamic> json) => Score(
        date: json["date"],
        songTitle: json["songTitle"],
        mode: _modeFromMap(json),
        difficulty: json["difficulty"] ?? '',
        username: json["username"] ?? '',
        flare: json["flare"] ?? '',
        score: json["score"],
        marvelous: json["marvelous"],
        perfect: json["perfect"],
        great: json["great"],
        good: json["good"],
        miss: json["miss"],
        maxCombo: json["maxCombo"],
        imagePath: json["imagePath"] ?? '',
      );

  @override
  String toString() {
    return 'Score{date: $date, song: $songTitle, mode: ${mode.name}, difficulty: $difficulty, score: $score}';
  }
}

class Favorite {
  final int id;
  final bool isFav;
  final String songTitle;
  final Modes mode;

  const Favorite({
    required this.id,
    required this.isFav,
    required this.songTitle,
    required this.mode,
  });

  Map<String, Object?> toMap() {
    return {
      'isFav': isFav ? 1 : 0,
      'songTitle': songTitle,
      'mode': mode.name,
    };
  }

  factory Favorite.fromMap(Map<String, dynamic> json) => Favorite(
        id: json["id"],
        isFav: (json["isFav"] as int) == 1 ? true : false,
        songTitle: json["songTitle"],
        mode: _modeFromMap(json),
      );

  @override
  String toString() {
    return 'Favorite{id: $id, isFav: $isFav, song: $songTitle, mode: ${mode.name}}';
  }
}
