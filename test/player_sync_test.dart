import 'dart:math';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:flutter_test/flutter_test.dart';

TimingPlay play(String song, String diff, double avg, double variation,
        {double sync = 0}) =>
    TimingPlay(
      playedAt: '',
      cabinetId: 1,
      side: PadSide.p1,
      song: song,
      mode: Modes.singles,
      difficulty: diff,
      songOffsetMs: 0,
      syncUsedMs: sync,
      averageMs: avg,
      variationMs: variation,
    );

void main() {
  test(
      'player sync: chart plays first, tighter plays weigh more, then song, '
      'then cabinet; override wins', () {
    final plays = [
      play('a', 'hard', -8, 5), // 8 FAST → +8
      play('a', 'hard', 4, 10, sync: 2), // 4 SLOW on +2 → −2
      play('b', 'hard', 6, 5), // 6 SLOW → −6
    ];
    PlayerSync resolve(String song, String diff, {double? override}) =>
        resolvePlayerSync(
            songOffset: 3,
            plays: plays,
            song: song,
            mode: Modes.singles,
            difficulty: diff,
            overrideMs: override);

    final chart = resolve('a', 'hard');
    expect(chart.source, SyncSource.chart);
    expect(chart.ms, closeTo(3 + (8 * 4 - 2) / 5, 1e-9));
    expect(resolve('a', 'easy').source, SyncSource.song);
    expect(resolve('c', 'hard').source, SyncSource.cabinet);
    expect(resolve('c', 'hard', override: -1).ms, -1);
  });

  test('far off the beat, the steps that missed every note are put back', () {
    final rng = Random(1);
    for (final (mu, sigma) in [(4.0, 12.0), (-90.0, 40.0), (130.0, 35.0)]) {
      // Box-Muller draws, kept only where they land on a note.
      final hits = [
        for (var i = 0; i < 400000; i++)
          mu +
              sigma *
                  sqrt(-2 * log(1 - rng.nextDouble())) *
                  cos(2 * pi * rng.nextDouble())
      ].where((x) => x.abs() <= kJudgeWindowMs).toList();
      final mean = hits.reduce((a, b) => a + b) / hits.length;
      final sd = sqrt(
          hits.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
              hits.length);
      final (m, s) = untruncate(mean, sd);
      expect(m, closeTo(mu, 0.5), reason: '$mu ± $sigma shown as $mean ± $sd');
      expect(s, closeTo(sigma, 0.5));
    }
  });
}
