import 'package:ddr_md/components/session/session_summary.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/visit_model.dart';
import 'package:flutter_test/flutter_test.dart';

final t = DateTime.utc(2026, 10, 1, 18);

extension on RecentPlay {
  RecentPlay copyWithTime(int minutesAgo) => RecentPlay(
      konamiId: konamiId,
      title: title,
      song: song,
      mode: mode,
      difficulty: difficulty,
      playedAt: t.subtract(Duration(minutes: minutesAgo)),
      score: score);
}

RecentPlay play(String id, int hoursAgo, int score) => RecentPlay(
    konamiId: id,
    title: id,
    song: id,
    mode: Modes.singles,
    difficulty: 'EXPERT',
    playedAt: t.subtract(Duration(hours: hoursAgo)),
    score: score);

void main() {
  test('a set is averaged against its charts, blended with the level model',
      () {
    ScoreRecord best(String id, int score) => ScoreRecord(
        id: 'eamuse:$id:singles:EXPERT',
        source: ScoreRecordSource.eamuse,
        song: id,
        konamiId: id,
        title: id,
        mode: Modes.singles,
        difficulty: 'EXPERT',
        score: score,
        rank: '',
        flareRank: '',
        updatedAt: t);
    final history = [
      // Today's set, newest first.
      play('a', 0, 960000),
      play('new', 0, 900000),
      // An earlier visit, 20,000 under its chart's best.
      play('a', 48, 940000),
    ];
    final s = ScoreModel(
      history,
      [best('a', 960000), best('b', 950000), best('c', 940000)],
      (_, __, ___) => 15,
    ).summarize(history.take(2).toList());

    // Level 15 bests average 950,000, less 20,000: a model of 930,000.
    // 'new' takes it outright; 'a' blends its one play of 940,000 with the
    // model counted twice, 933,333.
    expect(s.points.length, 2);
    expect(s.average, 930000);
    expect(s.usual, closeTo((930000 + 933333) / 2, 1));
    expect(s.upscores, 1);
  });

  test('a failed play counts for a quarter of a cleared one', () {
    final history = [
      play('a', 0, 900000),
      RecentPlay(
          konamiId: 'b',
          title: 'b',
          song: 'b',
          mode: Modes.singles,
          difficulty: 'EXPERT',
          playedAt: t,
          score: 860000,
          failed: true),
      play('a', 48, 900000),
      play('b', 48, 900000),
    ];
    final s = ScoreModel(history, [], (_, __, ___) => 15)
        .summarize(history.take(2).toList());
    expect(s.average, (900000 + 0.25 * 860000) / 1.25);
    expect(s.usual, 900000);
  });

  test('a far-off play pulls the average no further than the outlier limit',
      () {
    final history = [
      for (final id in ['a', 'b', 'c']) play(id, 0, 900000),
      play('d', 0, 300000),
      for (final id in ['a', 'b', 'c', 'd']) play(id, 48, 900000),
    ];
    final s = ScoreModel(history, [], (_, __, ___) => 15)
        .summarize(history.take(4).toList());
    // 600,000 under counts for 50,000 / 600,000 of a play.
    expect(s.gap, closeTo(-50000 / (3 + 1 / 12), 1));
  });

  test('plays join the session running when they were played', () {
    const venue = Venue(1, 'Round1');
    final ended = PlaySession(
        'ended',
        venue,
        t.subtract(const Duration(hours: 3)),
        t.subtract(const Duration(hours: 2)));
    // Never ended: it runs until its last credit.
    final open =
        PlaySession('open', venue, t.subtract(const Duration(hours: 30)), null);
    final visits = buildVisits(
      [
        play('a', 1, 1), // inside the hour after 'ended' ends
        play('b', 2, 1),
        play('c', 20, 1), // long after 'open' stopped: a set of its own
        play('d', 29, 1),
        // a minute before 'open' started: still its visit
        RecentPlay(
            konamiId: 'e',
            title: 'e',
            song: 'e',
            mode: Modes.singles,
            difficulty: 'EXPERT',
            playedAt: t.subtract(const Duration(hours: 30, minutes: 1)),
            score: 1),
      ],
      [ended, open],
      {'open': t.subtract(const Duration(hours: 29))},
    );
    expect([
      for (final v in visits) (v.session?.id, v.plays.length)
    ], [
      ('ended', 2),
      (null, 1),
      ('open', 2),
    ]);
  });

  test('plays split into the credit they were played in', () {
    const cab = Cabinet(1, 1, 'Round1', '');
    Credit credit(int n, int hoursAgo) => Credit(
        id: '$n',
        sessionId: 's',
        number: n,
        cabinet: cab,
        side: PadSide.p1,
        startedAt: t.subtract(Duration(hours: hoursAgo)));
    RecentPlay at(int minutesAgo) =>
        play('$minutesAgo', 0, 1).copyWithTime(minutesAgo);
    // Credit 1 at -60 min takes 4 songs; the rest split at the breaks.
    final groups = groupByCredit([
      for (final m in [5, 20, 23, 50, 52, 54, 56, 59]) at(m)
    ], [
      credit(1, 1)
    ]);
    expect([for (final (c, p) in groups) (c?.number, p.length)],
        [(null, 1), (null, 2), (null, 1), (1, 4)]);
  });

  test('timing matches the synced play of its song', () {
    TimingPlay timing(String song, int minutesAgo, String difficulty) =>
        TimingPlay(
            playedAt:
                t.subtract(Duration(minutes: minutesAgo)).toIso8601String(),
            cabinetId: 1,
            side: PadSide.p1,
            song: song,
            mode: Modes.singles,
            difficulty: difficulty,
            songOffsetMs: 0,
            syncUsedMs: 0,
            averageMs: -3,
            variationMs: 10);
    final synced = play('a', 0, 1);
    final (plays, matched) = reconcileTiming(
        [synced], [timing('a', 2, 'beginner'), timing('b', 5, 'hard')]);
    // Logged on the wrong difficulty: the synced chart takes it, and the
    // timing is fixed to that chart.
    expect(matched[synced]?.song, 'a');
    expect([for (final (t, d) in timingFixes(matched)) (t.song, d)],
        [('a', 'hard')]);
    // 'b' was never synced: it stands in without a score.
    expect([for (final p in plays) (p.song, p.score)], [('a', 1), ('b', null)]);
  });
}
