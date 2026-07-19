import 'package:ddr_md/components/song_json.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// Rows saved before the mode column existed (db v4) default to singles.
Modes _modeFromMap(Map<String, dynamic> json) =>
    Modes.values.asNameMap()[json["mode"]] ?? Modes.singles;

// How a score was captured. A screenshot imported via load-image carries no
// inherent capture time, so its play date is user-set and stays editable; a
// live camera score is stamped at capture and its date is fixed.
enum ScoreSource { loadImage, camera }

ScoreSource _sourceFromMap(Map<String, dynamic> json) =>
    ScoreSource.values.asNameMap()[json["source"]] ?? ScoreSource.camera;

class Note {
  // Stable identity, generated once at creation. Separate from [createdAt] so
  // the note can be edited without its identity changing.
  final String id;
  // When the note was first written (ISO-8601). Display and sort only; never
  // regenerated on edit.
  final String createdAt;
  final String contents;
  final String songTitle;
  final Modes mode;

  Note({
    String? id,
    required this.createdAt,
    required this.contents,
    required this.songTitle,
    required this.mode,
  }) : id = id ?? _uuid.v4();

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'createdAt': createdAt,
      'contents': contents,
      'songTitle': songTitle,
      'mode': mode.name,
    };
  }

  factory Note.fromMap(Map<String, dynamic> json) => Note(
        id: json["id"],
        createdAt: json["createdAt"],
        contents: json["contents"],
        songTitle: json["songTitle"],
        mode: _modeFromMap(json),
      );

  @override
  String toString() {
    return 'Note{id: $id, createdAt: $createdAt, contents: $contents, song: $songTitle, mode: ${mode.name}}';
  }
}

class Score {
  // Stable identity, generated once at creation. Doubles as the proof-image
  // filename. Separate from [playedAt] so the play date can be corrected in
  // edit mode without breaking the row identity or orphaning its image.
  final String id;
  // When the score was played (ISO-8601). Display and sort. Editable only for
  // load-image scores (see [source]).
  final String playedAt;
  // How the score was captured; gates whether [playedAt] can be edited.
  final ScoreSource source;
  // titletranslit of the matched song, matching the notes/favorites key.
  final String songTitle;
  final Modes mode;
  final String difficulty;
  final String username;
  final String flare;
  final int? score;
  final int? exScore;
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

  Score({
    String? id,
    required this.playedAt,
    required this.source,
    required this.songTitle,
    required this.mode,
    this.difficulty = '',
    this.username = '',
    this.flare = '',
    this.score,
    this.exScore,
    this.marvelous,
    this.perfect,
    this.great,
    this.good,
    this.miss,
    this.maxCombo,
    this.imagePath = '',
  }) : id = id ?? _uuid.v4();

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'playedAt': playedAt,
      'source': source.name,
      'songTitle': songTitle,
      'mode': mode.name,
      'difficulty': difficulty,
      'username': username,
      'flare': flare,
      'score': score,
      'exScore': exScore,
      'marvelous': marvelous,
      'perfect': perfect,
      'great': great,
      'good': good,
      'miss': miss,
      'maxCombo': maxCombo,
      'imagePath': imagePath,
    };
  }

  // Returns a copy carrying the same identity ([id]). Every attribute can be
  // overridden; omitted ones keep this instance's value. Passing null for a
  // nullable count leaves it unchanged rather than clearing it — the edit flow
  // always supplies the full set of counts, so it never needs to null one out.
  Score copyWith({
    String? playedAt,
    ScoreSource? source,
    String? songTitle,
    Modes? mode,
    String? difficulty,
    String? username,
    String? flare,
    int? score,
    int? exScore,
    int? marvelous,
    int? perfect,
    int? great,
    int? good,
    int? miss,
    int? maxCombo,
    String? imagePath,
  }) =>
      Score(
        id: id,
        playedAt: playedAt ?? this.playedAt,
        source: source ?? this.source,
        songTitle: songTitle ?? this.songTitle,
        mode: mode ?? this.mode,
        difficulty: difficulty ?? this.difficulty,
        username: username ?? this.username,
        flare: flare ?? this.flare,
        score: score ?? this.score,
        exScore: exScore ?? this.exScore,
        marvelous: marvelous ?? this.marvelous,
        perfect: perfect ?? this.perfect,
        great: great ?? this.great,
        good: good ?? this.good,
        miss: miss ?? this.miss,
        maxCombo: maxCombo ?? this.maxCombo,
        imagePath: imagePath ?? this.imagePath,
      );

  factory Score.fromMap(Map<String, dynamic> json) => Score(
        id: json["id"],
        playedAt: json["playedAt"],
        source: _sourceFromMap(json),
        songTitle: json["songTitle"],
        mode: _modeFromMap(json),
        difficulty: json["difficulty"] ?? '',
        username: json["username"] ?? '',
        flare: json["flare"] ?? '',
        score: json["score"],
        exScore: json["exScore"],
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
    return 'Score{id: $id, playedAt: $playedAt, song: $songTitle, mode: ${mode.name}, difficulty: $difficulty, score: $score}';
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
