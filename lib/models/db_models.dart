class Note {
  final String date;
  final String contents;

  const Note({
    required this.date,
    required this.contents,
  });

  Map<String, Object?> toMap() {
    return {
      'date': date,
      'contents': contents,
    };
  }

  factory Note.fromMap(Map<String, dynamic> json) => Note(
        date: json["date"],
        contents: json["contents"],
      );

  @override
  String toString() {
    return 'Note{date: $date, contents: $contents}';
  }
}
