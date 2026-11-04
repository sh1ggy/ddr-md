import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/session_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('goals count plays, upscores and first-time card gains by level', () {
    final t = DateTime(2026, 11, 1, 19);
    RecentPlay play(String song, int score, int minute,
            {bool failed = false}) =>
        RecentPlay(
            konamiId: song,
            title: song,
            song: song,
            mode: Modes.singles,
            difficulty: 'EXPERT',
            playedAt: t.add(Duration(minutes: minute)),
            score: score,
            failed: failed);
    // Newest first, as a visit holds them.
    final plays = [
      play('a', 993000, 4),
      play('b', 991000, 3),
      play('c', 999000, 2), // a 16
      play('a', 990500, 1),
      play('b', 400000, 0, failed: true),
    ];
    CardGain gain(String song, CardLayer layer, String from, String to,
            ChartBest best, int minute) =>
        CardGain(
            song: song,
            mode: Modes.singles,
            difficulty: 'EXPERT',
            layer: layer,
            from: from,
            to: to,
            best: best,
            playedAt: t.add(Duration(minutes: minute)),
            syncedAt: t);
    final gains = [
      gain(
          'a',
          CardLayer.finish,
          'AA+',
          'AAA',
          (score: 990500, grade: Grade.aaa, lamp: ClearLamp.gfc, flare: null),
          1),
      // A new card that's AAA already counts as a new AAA.
      gain(
          'b',
          CardLayer.card,
          '',
          '',
          (score: 991000, grade: Grade.aaa, lamp: ClearLamp.pfc, flare: null),
          3),
      gain(
          'a',
          CardLayer.frame,
          'gfc',
          'pfc',
          (score: 993000, grade: Grade.aaa, lamp: ClearLamp.pfc, flare: null),
          4),
    ];
    int? count(SessionGoal goal) => goalProgress(goal, plays, gains,
        levelOf: (song, _, __) => song == 'c' ? 16 : 15,
        bestOf: (song, _, __) => song == 'a' ? 993000 : 991000).count;

    const on15 = SessionGoal(kind: GoalKind.grade, value: 'AAA', level: 15);
    expect(count(on15), 3);
    expect(count(on15.copyWith(andUp: true)), 4);
    expect(count(const SessionGoal(kind: GoalKind.clear, level: 15)), 3);
    expect(count(const SessionGoal(kind: GoalKind.newGrade, value: 'AAA')), 2);
    expect(count(const SessionGoal(kind: GoalKind.lamp, value: 'pfc')), 2);
    expect(count(const SessionGoal(kind: GoalKind.lamp, value: 'mfc')), 0);
    expect(count(const SessionGoal(kind: GoalKind.upscore, level: 15)), 2);
    expect(SessionGoal.fromJson(on15.copyWith(target: () => 5).toJson())!.title,
        'AAAs on 15s');
  });
}
