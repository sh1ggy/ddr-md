/// Name: TimingCheckProtocolTest
/// Parent: TimingCheckProtocol
/// Description: Covers offset direction, judgement windows and the player type.
library;

import 'dart:math';

import 'package:ddr_md/components/settings/timing_check/timing_check_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const current = (judgement: 0, visual: 0);

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

  test('the type comes from how far taps follow the hidden shifts', () {
    final rounds = TimingProtocol.rounds(Random(1));
    expect(rounds, hasLength(baselineRounds));
    List<TimingResult> play(double follow) => [
          for (final round in rounds)
            TimingResult(
                round, List.filled(scoredBeats, -12 + round.pullMs * follow)),
        ];
    expect(TimingProtocol.type(play(.8)), PlayerType.visual);
    expect(TimingProtocol.type(play(.1)), PlayerType.audio);
    expect(TimingProtocol.type(play(.45)), PlayerType.both);
    expect(
        TimingProtocol.type([
          for (final round in rounds)
            TimingResult(round, List.filled(scoredBeats, null)),
        ]),
        isNull);
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
