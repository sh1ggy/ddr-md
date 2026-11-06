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

  test('cue rounds set both candidate dials from each cue', () {
    final protocol = TimingProtocol(current, Random(1));
    final rounds = protocol.baseline();
    expect(rounds, hasLength(baselineRounds));
    expect(rounds.map((r) => r.pullMs).where((p) => p != 0),
        unorderedEquals([-20, 20]));
    final results = [
      for (final round in rounds)
        TimingResult(
          round,
          List.filled(scoredBeats, -12 + round.pullMs * 0.5),
        ),
    ];
    expect(TimingProtocol.follow(results), 0.5);
    expect(protocol.candidates(results), {
      TimingDial.current: current,
      TimingDial.judgement: judgement,
      TimingDial.visual: (judgement: 0, visual: 24),
    });
  });

  test('a dial must win every run of the face-off', () {
    final rounds = TimingProtocol(current, Random(1)).faceOff({
      TimingDial.current: current,
      TimingDial.judgement: judgement,
      TimingDial.visual: visual,
    });
    expect(rounds, hasLength(faceOffRuns * TimingDial.values.length));

    List<TimingResult> results(int secondRunTight) => [
          for (final round in rounds)
            TimingResult(round, [
              for (var i = 0; i < scoredBeats; i++)
                i <
                        switch (round.dial!) {
                          TimingDial.current => 6,
                          TimingDial.judgement => 6,
                          TimingDial.visual =>
                            round.run == 0 ? 12 : secondRunTight,
                        }
                    ? 5
                    : 30,
            ]),
        ];

    expect(TimingProtocol.winner(results(9)), TimingDial.visual);
    expect(TimingProtocol.winner(results(6)), isNull);
  });

  test('taps use the audio start and when the finger landed', () {
    final clock = TapClock(10)
      ..audioAt(100, const Duration(milliseconds: 60))
      ..audioAt(120, const Duration(milliseconds: 90));
    expect(clock.music(1000), 960);
    clock
      ..tap(1016, const Duration(milliseconds: 1000))
      ..tap(1503, const Duration(milliseconds: 1500));
    expect(clock.taps, [963, 1463]);
  });
}
