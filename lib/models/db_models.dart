class Note {
  final String date;
  final String contents;
  final String songTitle;

  const Note({
    required this.date,
    required this.contents,
    required this.songTitle,
  });

  Map<String, Object?> toMap() {
    return {
      'date': date,
      'contents': contents,
      'songTitle': songTitle,
    };
  }

  factory Note.fromMap(Map<String, dynamic> json) => Note(
        date: json["date"],
        contents: json["contents"],
        songTitle: json["songTitle"],
      );

  @override
  String toString() {
    return 'Note{date: $date, contents: $contents, song: $songTitle}';
  }
}

class Score {
  final String date;
  // titletranslit of the matched song, matching the notes/favorites key.
  final String songTitle;
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

  const Score({
    required this.date,
    required this.songTitle,
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
  });

  Map<String, Object?> toMap() {
    return {
      'date': date,
      'songTitle': songTitle,
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
    };
  }

  factory Score.fromMap(Map<String, dynamic> json) => Score(
        date: json["date"],
        songTitle: json["songTitle"],
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
      );

  @override
  String toString() {
    return 'Score{date: $date, song: $songTitle, difficulty: $difficulty, score: $score}';
  }
}

class Favorite {
  final int id;
  final bool isFav;
  final String songTitle;

  const Favorite({
    required this.id,
    required this.isFav,
    required this.songTitle,
  });

  Map<String, Object?> toMap() {
    return {
      'isFav': isFav ? 1 : 0,
      'songTitle': songTitle,
    };
  }

  factory Favorite.fromMap(Map<String, dynamic> json) => Favorite(
        id: json["id"],
        isFav: (json["isFav"] as int) == 1 ? true : false,
        songTitle: json["songTitle"],
      );

  @override
  String toString() {
    return 'Favorite{id: $id, isFav: $isFav, song: $songTitle}';
  }
}
