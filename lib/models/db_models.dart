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
