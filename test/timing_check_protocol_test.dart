/// Name: TimingCheckProtocolTest
/// Parent: TimingCheckProtocol
/// Description: Covers offset direction, judgement windows and short comparisons.
library;

import 'dart:math';

import 'package:ddr_md/components/settings/timing_check/timing_check_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const current = (judgement: 0, visual: 0);
  const judgement = (judgement: 12, visual: 0);
  const visual = (judgement: 0, visual: 10);

  test('judgement moves both targets and visual moves only the crossing', () {
    const round = TimingRound(Cue.both, (judgement: 12, visual: 10));
    expect(round.judgementMs, -12);
    expect(round.crossingMs, -2);

    final taps = TimingTaps(round)
      ..add(firstBeatMs - 2)
      ..add(firstBeatMs - 12);
    final result = taps.finish();
    expect(result.hits, [10]);
    expect(result.judgements[TapJudgement.marvelous], 1);
    expect(result.judgements[TapJudgement.miss], 15);
  });

  test('practice keeps matching the continuous beat across the loop seam', () {
    const visualOnly = TimingRound(Cue.both, (judgement: 0, visual: 20));
    const judgementOnly = TimingRound(Cue.both, (judgement: -20, visual: 0));
    const tap = practiceLoopMs + 12.0;
    expect(visualOnly.crossingMs, judgementOnly.crossingMs);
    expect(visualOnly.matchTap(tap, firstMs: 0),
        (index: scoredBeats, error: 12.0));
    expect(judgementOnly.matchTap(tap, firstMs: 0),
        (index: scoredBeats, error: -8.0));
  });

  test('DDR grades use symmetric windows and account for every beat', () {
    final result = TimingResult(const TimingRound(Cue.both, current), [
      -17,
      17,
      -17.01,
      34,
      -34.01,
      84,
      -84.01,
      124,
      -124.01,
      null,
    ]);
    expect(result.judgements, {
      TapJudgement.marvelous: 2,
      TapJudgement.perfect: 2,
      TapJudgement.great: 2,
      TapJudgement.good: 2,
      TapJudgement.miss: 2,
    });
  });

  test('three cue rounds estimate the center and both candidate dials', () {
    final protocol = TimingProtocol(current, Random(1));
    final rounds = protocol.baseline();
    expect(rounds, hasLength(3));
    expect(rounds.first.cue, Cue.sound);
    expect(rounds.skip(1).map((r) => r.pullMs), unorderedEquals([-20, 20]));
    final results = [
      for (final round in rounds)
        TimingResult(
          round,
          List.filled(scoredBeats, -12 + round.pullMs * 0.5),
        ),
    ];
    expect(TimingProtocol.estimatedCenter(results), -12);
    expect(TimingProtocol.follow(results), 0.5);
    expect(protocol.candidates(results), {
      TimingDial.current: current,
      TimingDial.judgement: judgement,
      TimingDial.visual: (judgement: 0, visual: 24),
    });
  });

  test('a face-off can see gains within a grade and rejects uneven gains', () {
    final rounds = TimingProtocol(current, Random(1)).faceOff({
      TimingDial.current: current,
      TimingDial.judgement: judgement,
      TimingDial.visual: visual,
    });
    expect(rounds, hasLength(3));
    expect(rounds.map((r) => r.dial), unorderedEquals(TimingDial.values));

    List<TimingResult> results(double secondVisual, {int misses = 0}) => [
          for (final round in rounds)
            TimingResult(round, [
              for (var i = 0; i < scoredBeats; i++)
                if (round.dial == TimingDial.visual &&
                    i >= scoredBeats - misses)
                  null
                else
                  switch (round.dial!) {
                    TimingDial.current => 16,
                    TimingDial.judgement => i < scoredBeats ~/ 2 ? 2 : 20,
                    TimingDial.visual =>
                      i < scoredBeats ~/ 2 ? 8 : secondVisual,
                  },
            ]),
        ];

    expect(TimingProtocol.winner(results(8)), TimingDial.visual);
    expect(TimingProtocol.winner(results(16)), isNull);
    expect(TimingProtocol.winner(results(8, misses: 5)), isNull);
  });
}
