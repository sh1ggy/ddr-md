/// Name: Parity quiz
/// Parent: ParityQuizPage
/// Description: The footing-style questionnaire: real-chart moments the parity
/// engine finds divisive, each with two or three footings to choose between
/// (the engine's first in the data). Answers persist in settings and become
/// labels for fitting a player's weight profile.
library;

import 'dart:convert';

import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/services.dart';

class QuizNote {
  final double beat;
  final int col;
  final bool hold;
  final double? endSecond;

  /// The foot each option gives this note; option 0 is the engine's.
  final List<ParityFoot> feet;

  const QuizNote(this.beat, this.col, this.hold, this.endSecond, this.feet);
}

class QuizRow {
  final double second;
  final bool key;
  final List<QuizNote> notes;

  const QuizRow(this.second, this.key, this.notes);
}

class QuizQuestion {
  final String pattern;
  final String song;
  final String difficulty;
  final double second;
  final List<QuizRow> rows;

  QuizQuestion(
      this.pattern, this.song, this.difficulty, this.second, this.rows);

  /// Stable id for storing the answer.
  String get id => '$song@$second';

  int get optionCount => rows.first.notes.first.feet.length;

  /// The moment as chart notes, ascending, for the preview's painter; each
  /// paired with its [QuizNote] so an option's feet can be keyed to it.
  late final List<(StepNote, QuizNote)> chartNotes = [
    for (final row in rows)
      for (final n in row.notes)
        (
          StepNote(
            beat: n.beat,
            second: row.second,
            col: n.col,
            type: n.hold ? StepType.hold : StepType.tap,
            endSecond: n.endSecond,
          ),
          n
        )
  ];

  /// Where [option] stands the player after each row, for the dancing pad.
  /// Each foot starts on the first panel it steps on, rather than off the pad.
  List<ParityStance> stancesFor(int option) {
    List<int> colsOf(QuizRow row, ParityFoot foot) =>
        [for (final n in row.notes) if (n.feet[option] == foot) n.col];
    int firstCol(ParityFoot foot) => rows
        .map((r) => colsOf(r, foot))
        .firstWhere((c) => c.isNotEmpty, orElse: () => const [-1])
        .first;
    var left = [firstCol(ParityFoot.left)];
    var right = [firstCol(ParityFoot.right)];
    return [
      for (final row in rows)
        () {
          final l = colsOf(row, ParityFoot.left);
          final r = colsOf(row, ParityFoot.right);
          if (l.isNotEmpty) left = l;
          if (r.isNotEmpty) right = r;
          return ParityStance(
            second: row.second,
            leftHeel: left.first,
            leftToe: left.length > 1 ? left[1] : -1,
            rightHeel: right.first,
            rightToe: right.length > 1 ? right[1] : -1,
            stepped: {for (final n in row.notes) n.col},
          );
        }()
    ];
  }

  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
        j['pattern'] as String,
        j['song'] as String,
        j['difficulty'] as String,
        (j['second'] as num).toDouble(),
        [
          for (final r in j['rows'] as List)
            QuizRow(
              (r['s'] as num).toDouble(),
              r['key'] as bool,
              [
                for (final n in r['notes'] as List)
                  QuizNote(
                    (n['b'] as num).toDouble(),
                    n['c'] as int,
                    n['hold'] as bool,
                    (n['e'] as num?)?.toDouble(),
                    [
                      for (final f in n['feet'] as List)
                        f == 'L' ? ParityFoot.left : ParityFoot.right
                    ],
                  )
              ],
            )
        ],
      );

  static Future<List<QuizQuestion>> load() async => [
        for (final q in json.decode(
            await rootBundle.loadString('assets/parity_quiz.json')) as List)
          QuizQuestion.fromJson(q as Map<String, dynamic>)
      ];
}

/// Chosen option per question id.
class QuizAnswers {
  static Map<String, int> read() {
    final raw = Settings.getString(Settings.parityQuizKey);
    if (raw.isEmpty) return {};
    return (json.decode(raw) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));
  }

  static void write(Map<String, int> answers) =>
      Settings.setString(Settings.parityQuizKey, json.encode(answers));
}
