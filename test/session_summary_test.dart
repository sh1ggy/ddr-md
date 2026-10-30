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
  test('a set is averaged against its charts, blended with their models', () {
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
      play('c', 0, 930000),
      // An earlier visit, 20,000 under its chart's best.
      play('a', 48, 940000),
    ];
    final s = ScoreModel(
      history,
      [best('a', 960000), best('b', 950000), best('c', 940000)],
      (_, __, ___) => 15,
    ).summarize(history.take(3).toList());

    // Plays land 20,000 under their best. 'c' is modelled from its own best,
    // 920,000. 'a' set its best today, so like 'new' it falls back to the
    // level: bests averaging 950,000, a model of 930,000, which 'a' blends
    // with its one play of 940,000 counted against the model's two, 933,333.
    expect(s.points.length, 3);
    expect(s.average, 930000);
    expect(s.usual, closeTo((933333 + 930000 + 920000) / 3, 1));
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

  test('a set splits by level, easiest first', () {
    final history = [
      play('hard', 0, 880000),
      play('easy', 0, 990000),
      play('easy2', 0, 970000),
      for (final id in ['hard', 'easy', 'easy2']) play(id, 48, 900000),
    ];
    final s = ScoreModel(history, [], (song, _, __) => song == 'hard' ? 17 : 14)
        .summarize(history.take(3).toList());
    final levels = s.byLevel;
    expect(levels.map((l) => (l.level, l.plays)), [(14, 2), (17, 1)]);
    expect(levels.first.average, 980000);
    expect(levels.first.usual, 900000);
    expect(levels.last.average - levels.last.usual, -20000);
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

  test('long pauses and manual starts cannot create undersized credits', () {
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
    // Eight synced songs form two complete credits, even when individual
    // pauses would previously have split them into one/two-song credits.
    final groups = groupByCredit([
      for (final m in [5, 20, 23, 50, 52, 54, 56, 59]) at(m)
    ], [
      credit(1, 1)
    ]);
    expect([for (final (c, p) in groups) (c?.number, p.length)],
        [(null, 4), (1, 4)]);

    // An extra manual start cannot turn the pair at -23 min into a credit.
    final logged = groupByCredit([
      for (final m in [5, 20, 23, 50, 52, 54, 56, 59]) at(m)
    ], [
      credit(1, 1),
      Credit(
          sessionId: 's',
          number: 2,
          cabinet: cab,
          side: PadSide.p1,
          startedAt: t.subtract(const Duration(minutes: 23))),
    ]);
    expect([for (final (c, p) in logged) (c?.number, p.length)],
        [(null, 4), (1, 4)]);
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

  group('credit reconciliation', () {
    const cab = Cabinet(1, 1, 'Round1', '');
    Credit credit(int n, int minutesAgo) => Credit(
        id: '$n',
        sessionId: 's',
        number: n,
        cabinet: cab,
        side: PadSide.p1,
        startedAt: t.subtract(Duration(minutes: minutesAgo)));
    TimingPlay timing(RecentPlay p, String creditId) => TimingPlay(
        id: 'timing-${p.konamiId}',
        playedAt: p.playedAt.toIso8601String(),
        creditId: creditId,
        cabinetId: cab.id,
        side: PadSide.p1,
        song: p.song!,
        mode: p.mode,
        difficulty: 'hard',
        songOffsetMs: 0,
        syncUsedMs: 0,
        averageMs: -3,
        variationMs: 10);
    List<RecentPlay> sixPlays() =>
        [for (var i = 0; i < 6; i++) play('$i', 0, 1).copyWithTime(i * 2)];

    test('six manual matches cannot overfill their logged credit', () {
      final synced = sixPlays();
      final (played, matched) =
          reconcileTiming(synced, [for (final p in synced) timing(p, '1')]);
      final groups = groupByCredit(played, [credit(1, 12)], matched);

      expect([for (final (c, ps) in groups) (c?.number, ps.length)],
          [(null, 3), (1, 3)]);
      expect(groups.expand((g) => g.$2), orderedEquals(synced));
      expect(matched.length, 6);
    });

    test('conflicting manual credit IDs cannot reorder synced plays', () {
      final synced = [
        for (var i = 0; i < 8; i++) play('$i', 0, 1).copyWithTime(i * 3)
      ];
      // Every timing was accidentally logged against the opposite credit.
      final (played, matched) = reconcileTiming(synced,
          [for (final (i, p) in synced.indexed) timing(p, i < 4 ? '1' : '2')]);
      final groups =
          groupByCredit(played, [credit(2, 9), credit(1, 23)], matched);

      expect([for (final (c, ps) in groups) (c?.number, ps.length)],
          [(2, 4), (1, 4)]);
      expect(groups.expand((g) => g.$2), orderedEquals(synced));
      expect(matched.length, 8);
    });

    test('overflow on either side of a logged credit stays separate', () {
      final synced = [
        for (var i = 0; i < 12; i++) play('$i', 0, 1).copyWithTime(i * 3)
      ];
      final groups = groupByCredit(synced, [credit(1, 21)]);

      expect([for (final (c, ps) in groups) (c?.number, ps.length)],
          [(null, 4), (1, 4), (null, 4)]);
      expect(groups.expand((g) => g.$2), orderedEquals(synced));
    });

    test('tied timestamps retain scraped order through reconciliation', () {
      // Enough ties to catch an unstable sort, including matched plays
      // whose insertion order differs from the scrape's.
      final synced = [for (var i = 0; i < 32; i++) play('$i', 0, 1)];
      final (played, matched) = reconcileTiming(
          synced, [for (final p in synced.reversed) timing(p, '1')]);
      final groups = groupByCredit(played, [credit(1, 1)], matched);

      expect(played, orderedEquals(synced));
      expect(groups.expand((g) => g.$2), orderedEquals(synced));
      expect(groups.map((g) => g.$2.length), everyElement(4));
      expect(groups.where((g) => g.$1 != null), hasLength(1));
    });

    test('six manual-only plays form three plus three without losing timing',
        () {
      final (played, matched) =
          reconcileTiming([], [for (final p in sixPlays()) timing(p, '1')]);
      final groups = groupByCredit(played, [credit(1, 12)], matched);

      expect([for (final (c, ps) in groups) (c?.number, ps.length)],
          [(null, 3), (1, 3)]);
      expect(groups.expand((g) => g.$2), orderedEquals(played));
      expect(matched.length, 6);
    });

    test('empty logged credits remain visible in chronological order', () {
      final groups = groupByCredit([], [credit(1, 12), credit(2, 1)]);
      expect([for (final (c, ps) in groups) (c?.number, ps.length)],
          [(2, 0), (1, 0)]);
    });

    test('extra and early manual credit starts do not split synced credits',
        () {
      final synced = [
        for (var i = 0; i < 8; i++) play('$i', 0, 1).copyWithTime(i * 3)
      ];
      final manual = [
        credit(1, 23),
        credit(2, 19), // Accidental Next Credit during the first credit.
        credit(3, 16),
        credit(4, 13), // Logged the next real credit a song too early.
        credit(5, 2),
        credit(6, 0), // Extra tap after the last song.
      ];
      final (played, matched) = reconcileTiming(synced,
          [for (final (i, p) in synced.indexed) timing(p, '${i % 6 + 1}')]);
      final groups = groupByCredit(played, manual, matched);

      expect(groups, hasLength(2));
      expect(groups.map((g) => g.$2.length), [4, 4]);
      expect(groups.map((g) => g.$2),
          [orderedEquals(synced.take(4)), orderedEquals(synced.skip(4))]);
      expect(matched.length, 8);
    });

    test('missing manual credits cannot merge or shift synced credits', () {
      final synced = [
        for (var i = 0; i < 12; i++) play('$i', 0, 1).copyWithTime(i * 3)
      ];
      final (played, matched) =
          reconcileTiming(synced, [for (final p in synced) timing(p, '1')]);
      final groups = groupByCredit(played, [credit(1, 35)], matched);

      expect(groups, hasLength(3));
      expect(groups.map((g) => g.$2.length), [4, 4, 4]);
      expect(groups.expand((g) => g.$2), orderedEquals(synced));
      expect(matched.length, 12);
    });

    test('unmatched manual entries cannot consume synced credit slots', () {
      final synced = [
        for (var i = 0; i < 8; i++) play('$i', 0, 1).copyWithTime(i * 3)
      ];
      final unmatched = timing(play('manual-only', 0, 1).copyWithTime(17), '1');
      final (played, matched) = reconcileTiming(synced, [unmatched]);
      final groups = groupByCredit(played, [credit(1, 23)], matched);
      final syncedGroups = [
        for (final (_, ps) in groups)
          if (ps.any(synced.contains)) ps.where(synced.contains).toList(),
      ];

      expect(syncedGroups,
          [orderedEquals(synced.take(4)), orderedEquals(synced.skip(4))]);
      expect(
          groups.map((g) => g.$2.length), everyElement(lessThanOrEqualTo(4)));
      expect(groups.expand((g) => g.$2), hasLength(9));
      expect(matched.values, contains(unmatched));
    });

    test('complete histories always partition into three/four-song credits',
        () {
      for (var count = 3; count <= 64; count++) {
        if (count == 5) continue; // This count cannot be a complete history.
        final synced = [
          for (var i = 0; i < count; i++) play('$i', 0, 1).copyWithTime(i * 3)
        ];
        final groups = groupByCredit(synced, [credit(1, count * 3)]);
        expect(groups.map((g) => g.$2.length),
            everyElement(inInclusiveRange(3, 4)),
            reason: '$count songs');
        expect(groups.expand((g) => g.$2), orderedEquals(synced));
      }
    });

    test(
        'nine songs form three credits of three, never four plus four plus one',
        () {
      final synced = [
        for (var i = 0; i < 9; i++) play('$i', 0, 1).copyWithTime(i * 3)
      ];
      expect(groupByCredit(synced, []).map((g) => g.$2.length), [3, 3, 3]);
    });

    test('timestamp gaps choose between three plus four and four plus three',
        () {
      for (final (times, expected) in [
        ([0, 3, 6, 9, 18, 21, 24], [4, 3]),
        ([0, 3, 6, 18, 21, 24, 27], [3, 4]),
      ]) {
        final synced = [
          for (final (i, minutes) in times.indexed)
            play('$i', 0, 1).copyWithTime(minutes)
        ];
        final groups = groupByCredit(synced, [
          credit(1, 30),
          credit(2, 20),
          credit(3, 19),
          credit(4, 0),
        ]);
        expect(groups.map((g) => g.$2.length), expected);
        expect(groups.expand((g) => g.$2), orderedEquals(synced));
      }
    });

    test('a manual start corroborates a larger re-entry gap', () {
      final synced = [
        for (final minutes in [0, 3, 6, 11, 15, 18, 21])
          play('$minutes', 0, 1).copyWithTime(minutes)
      ];
      // The two candidate gaps are 4 and 5 minutes (usual interval 3).
      // Starting the next credit during the 4-minute gap supports 3 + 4.
      expect(groupByCredit(synced, []).map((g) => g.$2.length), [3, 4]);
      final groups = groupByCredit(synced, [credit(1, 23), credit(2, 13)]);
      expect(groups.map((g) => g.$2.length), [4, 3]);
      expect(groups.expand((g) => g.$2), orderedEquals(synced));
    });

    test('sparse matched timing changes can corroborate a larger gap', () {
      final synced = [
        for (final minutes in [0, 3, 6, 11, 15, 18, 21])
          play('$minutes', 0, 1).copyWithTime(minutes)
      ];
      // Neither credit start lies near the gap; the matched timing records
      // on either side carry the change, with an unlogged song in between.
      final (played, matched) = reconcileTiming(
          synced, [timing(synced[5], '1'), timing(synced[3], '2')]);
      final groups =
          groupByCredit(played, [credit(1, 24), credit(2, 23)], matched);
      expect(groups.map((g) => g.$2.length), [4, 3]);
      expect(groups.expand((g) => g.$2), orderedEquals(synced));
    });

    test('supported modest gaps can distinguish four triples from three fours',
        () {
      final synced = [
        for (final minutes in [0, 3, 6, 10, 13, 16, 20, 23, 26, 30, 33, 36])
          play('$minutes', 0, 1).copyWithTime(minutes)
      ];
      expect(groupByCredit(synced, []).map((g) => g.$2.length), [4, 4, 4]);
      final groups = groupByCredit(synced, [
        credit(1, 38),
        credit(2, 28),
        credit(3, 18),
        credit(4, 8),
      ]);
      expect(groups.map((g) => g.$2.length), [3, 3, 3, 3]);
      expect(groups.expand((g) => g.$2), orderedEquals(synced));
    });

    test('manual inputs alone cannot create a gap in evenly timed songs', () {
      final synced = [
        for (var i = 0; i < 7; i++) play('$i', 0, 1).copyWithTime(i * 3)
      ];
      final (played, matched) = reconcileTiming(synced, [
        for (final (i, p) in synced.indexed) timing(p, i < 4 ? '2' : '1'),
      ]);
      final groups =
          groupByCredit(played, [credit(1, 20), credit(2, 11)], matched);
      expect(groups.map((g) => g.$2.length), [3, 4]);
      expect(groups.expand((g) => g.$2), orderedEquals(synced));
    });

    test('a stronger synced gap outweighs misleading or repeated manual taps',
        () {
      final synced = [
        for (final minutes in [0, 3, 6, 14, 18, 21, 24])
          play('$minutes', 0, 1).copyWithTime(minutes)
      ];
      // The wrong manual start is in a 4-minute gap. The 8-minute synced
      // gap wins; twenty taps in the wrong gap must not stack twenty votes.
      for (final count in [1, 20]) {
        final groups = groupByCredit(synced, [
          credit(1, 26),
          for (var i = 0; i < count; i++) credit(i + 2, 16),
        ]);
        expect(groups.map((g) => g.$2.length), [3, 4]);
        expect(groups.expand((g) => g.$2), orderedEquals(synced));
      }
    });

    test('pauses can distinguish four triples from three quadruples', () {
      final synced = [
        for (final minutes in [0, 3, 6, 18, 21, 24, 36, 39, 42, 54, 57, 60])
          play('$minutes', 0, 1).copyWithTime(minutes)
      ];
      expect(groupByCredit(synced, []).map((g) => g.$2.length), [3, 3, 3, 3]);
    });

    test('an unmatched manual entry cannot turn three synced songs into four',
        () {
      final synced = [
        for (var i = 0; i < 3; i++) play('$i', 0, 1).copyWithTime(i * 3)
      ];
      final unmatched = timing(play('manual-only', 0, 1).copyWithTime(2), '1');
      final (played, matched) = reconcileTiming(synced, [unmatched]);
      final groups = groupByCredit(played, [credit(1, 8)], matched);
      final syncedGroup =
          groups.singleWhere((g) => g.$2.contains(synced.first));
      expect(syncedGroup.$2, orderedEquals(synced));
      expect(groups.singleWhere((g) => g != syncedGroup).$2, hasLength(1));
      expect(matched.values, contains(unmatched));
    });

    test('incomplete edge records retain their plays without a credit label',
        () {
      for (final count in [1, 2, 5]) {
        final synced = [
          for (var i = 0; i < count; i++) play('$i', 0, 1).copyWithTime(i * 3)
        ];
        final groups = groupByCredit(synced, [credit(1, count * 3)]);
        expect(groups.expand((g) => g.$2), orderedEquals(synced));
        for (final (c, ps) in groups) {
          if (ps.length < kMinSongsPerCredit) expect(c, isNull);
        }
      }
    });
  });
}
