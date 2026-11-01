/// Name: SessionGoal
/// Parent: SessionState, GoalCard, SessionWrapPage, Visits
/// Description: What a session sets out to do, like "AAAs on 15s", and how
/// far its synced plays got: every play that reaches a grade or clears, every
/// chart a play upscored, or each chart whose card first gained the grade,
/// lamp or flare. Optionally a number to reach. Counted over the whole
/// session, so changing the goal mid-session recounts it.
library;

import 'dart:convert';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks;
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/db_models.dart';

enum GoalKind {
  grade('Grade'),
  newGrade('New grade'),
  lamp('Lamp'),
  flare('Flare'),
  upscore('Upscore'),
  clear('Clear');

  const GoalKind(this.label);
  final String label;

  /// The values a goal of this kind can aim for, best first; empty when it
  /// has none. New grade is AAA only: that's the grade a card keeps.
  List<String> get aims => switch (this) {
        grade => [
            for (final g in const [Grade.aaa, Grade.aaPlus, Grade.aa, Grade.a])
              g.label
          ],
        newGrade => [Grade.aaa.label],
        lamp => [
            for (final l in const [
              ClearLamp.mfc,
              ClearLamp.pfc,
              ClearLamp.gfc,
              ClearLamp.fc
            ])
              l.name
          ],
        flare => kFlareRanks.reversed.toList(),
        upscore || clear => const [],
      };
}

class SessionGoal {
  const SessionGoal({
    required this.kind,
    this.value = '',
    this.level,
    this.andUp = false,
    this.mode = Modes.singles,
    this.target,
  });

  final GoalKind kind;
  // A grade's label, a lamp's name or a flare rank; '' for upscores and clears.
  final String value;
  // Null for any level.
  final int? level;
  final bool andUp;
  final Modes mode;
  // Null for an open goal.
  final int? target;

  bool levelCounts(int? l) =>
      level == null || (l != null && (andUp ? l >= level! : l == level));

  /// "AAAs on 15s", "New PFCs on 14+".
  String get title {
    final what = switch (kind) {
      GoalKind.grade => '${value}s',
      GoalKind.newGrade => 'New ${value}s',
      GoalKind.lamp => 'New ${value.toUpperCase()}s',
      GoalKind.flare => 'Flare $value',
      GoalKind.upscore => 'Upscores',
      GoalKind.clear => 'Clears',
    };
    return level == null ? what : '$what on $level${andUp ? '+' : 's'}';
  }

  SessionGoal copyWith(
          {GoalKind? kind,
          String? value,
          int? Function()? level,
          bool? andUp,
          Modes? mode,
          int? Function()? target}) =>
      SessionGoal(
        kind: kind ?? this.kind,
        value: value ?? this.value,
        level: level == null ? this.level : level(),
        andUp: andUp ?? this.andUp,
        mode: mode ?? this.mode,
        target: target == null ? this.target : target(),
      );

  String toJson() => jsonEncode({
        'kind': kind.name,
        'value': value,
        'level': level,
        'andUp': andUp,
        'mode': mode.name,
        'target': target,
      });

  /// Null for none, or a goal from a newer app this one can't count.
  static SessionGoal? fromJson(String? s) {
    if (s == null || s.isEmpty) return null;
    final m = jsonDecode(s) as Map<String, dynamic>;
    final kind = GoalKind.values.asNameMap()[m['kind']];
    if (kind == null) return null;
    return SessionGoal(
      kind: kind,
      value: m['value'] as String? ?? '',
      level: m['level'] as int?,
      andUp: m['andUp'] as bool? ?? false,
      mode: Modes.values.asNameMap()[m['mode']] ?? Modes.singles,
      target: m['target'] as int?,
    );
  }
}

/// A play or chart that counted towards a goal.
typedef GoalHit = ({
  String title,
  String? song,
  Modes mode,
  String difficulty,
  int? score,
  // A chart counting for the first time, rather than a repeat play.
  bool fresh,
});

class GoalProgress {
  const GoalProgress(this.goal, this.hits);
  final SessionGoal goal;
  // Oldest first.
  final List<GoalHit> hits;

  int get count => hits.length;
  bool get reached => goal.target != null && count >= goal.target!;
}

/// How far [plays] (a session's, newest first) and the card [gains] they
/// made got towards [goal]. [levelOf] gives a chart's level; [bestOf] its
/// best score now.
GoalProgress goalProgress(
  SessionGoal goal,
  List<RecentPlay> plays,
  List<CardGain> gains, {
  required int? Function(String? song, Modes mode, String difficulty) levelOf,
  required int? Function(String song, Modes mode, String difficulty) bestOf,
}) {
  final mine = [
    for (final p in plays.reversed)
      if (p.mode == goal.mode &&
          goal.levelCounts(levelOf(p.song, p.mode, p.difficulty)))
        p
  ];
  GoalHit hit(RecentPlay p, {bool fresh = false}) => (
        title: p.title,
        song: p.song,
        mode: p.mode,
        difficulty: p.difficulty,
        score: p.score,
        fresh: fresh,
      );
  // Charts seen before in the session, so a repeat reads as one.
  final seen = <String>{};
  bool first(String id) => seen.add(id);

  switch (goal.kind) {
    case GoalKind.grade:
      final want = Grade.values.indexWhere((g) => g.label == goal.value);
      return GoalProgress(goal, [
        for (final p in mine)
          if (!p.failed &&
              p.score != null &&
              gradeForScore(p.score!).index <= want)
            hit(p, fresh: first(p.recordId)),
      ]);
    case GoalKind.clear:
      return GoalProgress(goal, [
        for (final p in mine)
          if (!p.failed && p.score != null) hit(p, fresh: first(p.recordId)),
      ]);
    case GoalKind.upscore:
      // Each chart once, at the play that set the best it has now.
      final best = <String, RecentPlay>{};
      for (final p in mine) {
        final now =
            p.song == null ? null : bestOf(p.song!, p.mode, p.difficulty);
        if (p.score != null && now != null && p.score! >= now) {
          best[p.recordId] = p;
        }
      }
      return GoalProgress(
          goal, [for (final p in best.values) hit(p, fresh: true)]);
    case GoalKind.newGrade || GoalKind.lamp || GoalKind.flare:
      final layer = switch (goal.kind) {
        GoalKind.newGrade => CardLayer.finish,
        GoalKind.lamp => CardLayer.frame,
        _ => CardLayer.aura,
      };
      bool reaches(String? v) =>
          v != null &&
          v.isNotEmpty &&
          switch (goal.kind) {
            GoalKind.newGrade => v == goal.value,
            GoalKind.lamp => cardFrameTier(ClearLamp.values.asNameMap()[v]) >=
                cardFrameTier(ClearLamp.values.asNameMap()[goal.value]),
            _ => kFlareRanks.indexOf(v) >= kFlareRanks.indexOf(goal.value),
          };
      String? now(ChartBest b) => switch (goal.kind) {
            GoalKind.newGrade => b.grade?.label,
            GoalKind.lamp => b.lamp?.name,
            _ => b.flare,
          };
      final titles = {
        for (final p in mine)
          '${p.song}:${p.mode.name}:${p.difficulty}': p.title
      };
      final sorted = [...gains]
        ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
      return GoalProgress(goal, [
        for (final g in sorted)
          if (titles['${g.song}:${g.mode.name}:${g.difficulty}']
              case final title?)
            if ((g.layer == CardLayer.card && reaches(now(g.best))) ||
                (g.layer == layer && reaches(g.to) && !reaches(g.from)))
              if (first('${g.song}:${g.mode.name}:${g.difficulty}'))
                (
                  title: title,
                  song: g.song,
                  mode: g.mode,
                  difficulty: g.difficulty,
                  score: g.best.score,
                  fresh: true,
                ),
      ]);
  }
}

/// [goalProgress] against the song list's levels and the loaded bests.
GoalProgress goalProgressNow(
        SessionGoal goal,
        List<RecentPlay> plays,
        List<CardGain> gains,
        int? Function(String? song, Modes mode, String difficulty) levelOf) =>
    goalProgress(goal, plays, gains,
        levelOf: levelOf,
        bestOf: (song, mode, difficulty) =>
            ChartBests.forChart(song, mode, difficulty)?.score);

/// "3 AAA plays on 2 charts."
String goalSummary(GoalProgress p) {
  final n = p.count;
  final fresh = p.hits.where((h) => h.fresh).length;
  final goal = p.goal;
  final what = switch (goal.kind) {
    GoalKind.grade => '${goal.value} ${n == 1 ? 'play' : 'plays'}',
    GoalKind.clear => n == 1 ? 'clear' : 'clears',
    GoalKind.upscore => n == 1 ? 'upscore' : 'upscores',
    _ => n == 1 ? 'chart' : 'charts',
  };
  final repeats = goal.kind == GoalKind.grade || goal.kind == GoalKind.clear;
  final charts = !repeats || n == 0
      ? ''
      : fresh == n
          ? ', each a different chart'
          : ' on $fresh ${fresh == 1 ? 'chart' : 'charts'}';
  return '$n $what$charts.';
}
