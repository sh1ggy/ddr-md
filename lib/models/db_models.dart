class Note {
  final DateTime date;
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

  @override
  String toString() {
    return 'Note{id: ${date.toIso8601String()}, contents: $contents}';
  }
}

