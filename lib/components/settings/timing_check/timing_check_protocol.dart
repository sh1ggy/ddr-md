/// Name: TimingCheckProtocol
/// Parent: TimingCheckPage
/// Description: Tap matching, cue experiments and the short face-off.
library;

import 'dart:math' as math;

const beatMs = 400;
const countInBeats = 4;
const scoredBeats = 16;
const practiceLoopMs = scoredBeats * beatMs;
const firstBeatMs = (countInBeats + 1) * beatMs;
const roundEndMs = firstBeatMs + (scoredBeats - 1) * beatMs + beatMs;
const baselineRounds = 3;
const faceOffRounds = 3;
const _minimumHits = 12;
const pullShiftMs = 20;

enum Cue {
  sound('Sound only'),
  both('Sound + arrows');

  const Cue(this.label);
  final String label;
}

enum TimingDial {
  current('Your settings'),
  judgement('Judgement timing'),
  visual('Visual timing');

  const TimingDial(this.label);
  final String label;
}

enum TapJudgement {
  marvelous('Marvelous', 17),
  perfect('Perfect', 34),
  great('Great', 84),
  good('Good', 124),
  miss('Miss', 160);

  const TapJudgement(this.label, this.limitMs);
  final String label;
  final int limitMs;

  // Like the cabinet result, count taps outside Good with misses.
  static TapJudgement forError(double? error) {
    if (error == null) return miss;
    return values.firstWhere((grade) => error.abs() <= grade.limitMs,
        orElse: () => miss);
  }
}

typedef TimingOptions = ({int judgement, int visual});

class TimingRound {
  const TimingRound(this.cue, this.options, {this.pullMs = 0, this.dial});

  final Cue cue;
  final TimingOptions options;
  final int pullMs;
  final TimingDial? dial;

  // Positive judgement advances both targets. Positive visual delays only
  // the receptor crossing. The drum always stays on the music timeline.
  int get judgementMs => -options.judgement;
  int get crossingMs => judgementMs + options.visual + pullMs;

  ({int index, double error}) matchTap(double elapsedMs,
      {int firstMs = firstBeatMs}) {
    // Match around the active cue (or the midpoint of both cues), then
    // measure the tap against judgement independently of arrow position.
    final cueOffset = cue == Cue.sound ? 0 : crossingMs / 2;
    final index = ((elapsedMs - firstMs - cueOffset) / beatMs).round();
    final beat = firstMs + index * beatMs;
    return (index: index, error: elapsedMs - beat - judgementMs);
  }
}

class TimingResult {
  TimingResult(this.round, this.taps);

  final TimingRound round;
  // Signed errors relative to the judgement target, one entry per beat.
  final List<double?> taps;

  List<double> get hits => taps.whereType<double>().toList();
  Iterable<double> get timedHits =>
      hits.where((t) => TapJudgement.forError(t) != TapJudgement.miss);
  bool get usable => timedHits.length >= _minimumHits;

  Map<TapJudgement, int> get judgements {
    final counts = {for (final grade in TapJudgement.values) grade: 0};
    for (final tap in taps) {
      final grade = TapJudgement.forError(tap);
      counts.update(grade, (count) => count + 1);
    }
    return counts;
  }

  double? get center => median(timedHits);

  // Use every beat, and cap very late or absent taps at the miss penalty.
  // A continuous measure detects improvement within a judgement window.
  double get meanError => _meanError(taps);
  List<double> get halfErrors => [
        _meanError(taps.take(scoredBeats ~/ 2)),
        _meanError(taps.skip(scoredBeats ~/ 2)),
      ];

  static double _meanError(Iterable<double?> taps) {
    final miss = TapJudgement.miss.limitMs;
    return taps.fold(
            0.0, (sum, tap) => sum + math.min(tap?.abs() ?? miss, miss)) /
        taps.length;
  }
}

class TimingTaps {
  TimingTaps(this.round);

  final TimingRound round;
  final _taps = List<double?>.filled(scoredBeats, null);

  void add(double elapsedMs) {
    final (:index, :error) = round.matchTap(elapsedMs);
    if (index < 0 || index >= scoredBeats) return;
    // Half-beat matching gives each tap one slot. Count the first tap only.
    _taps[index] ??= error;
  }

  TimingResult finish() => TimingResult(round, List.unmodifiable(_taps));
}

double? median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return null;
  return (sorted[(sorted.length - 1) ~/ 2] + sorted[sorted.length ~/ 2]) / 2;
}

class TimingProtocol {
  TimingProtocol(this.current, this.random);

  final TimingOptions current;
  final math.Random random;

  List<TimingRound> baseline() => [
        TimingRound(Cue.sound, current),
        ...[
          TimingRound(Cue.both, current, pullMs: -pullShiftMs),
          TimingRound(Cue.both, current, pullMs: pullShiftMs),
        ]..shuffle(random),
      ];

  Map<TimingDial, TimingOptions> candidates(List<TimingResult> baseline) {
    final sound = baseline.first;
    final bias = estimatedCenter(baseline);
    final weight = follow(baseline);
    final visualDelta = bias == null || weight == null || weight < 0.25
        ? 0
        : (-bias / weight).round().clamp(-40, 40);
    final judgementDelta =
        sound.usable ? -sound.center!.round().clamp(-40, 40) : 0;
    return {
      TimingDial.current: current,
      TimingDial.judgement: (
        judgement: (current.judgement + judgementDelta).clamp(-100, 100),
        visual: current.visual,
      ),
      TimingDial.visual: (
        judgement: current.judgement,
        visual: (current.visual + visualDelta).clamp(-100, 100),
      ),
    };
  }

  // The two opposite shifts estimate the unshifted center without an extra
  // round. The actual unshifted setting is still played in the face-off.
  static double? estimatedCenter(List<TimingResult> baseline) {
    final early = baseline.firstWhere((r) => r.round.pullMs == -pullShiftMs);
    final late = baseline.firstWhere((r) => r.round.pullMs == pullShiftMs);
    return early.usable && late.usable
        ? (early.center! + late.center!) / 2
        : null;
  }

  static double? follow(List<TimingResult> baseline) {
    final early = baseline.firstWhere((r) => r.round.pullMs == -pullShiftMs);
    final late = baseline.firstWhere((r) => r.round.pullMs == pullShiftMs);
    if (!early.usable || !late.usable) return null;
    return (late.center! - early.center!) / (2 * pullShiftMs);
  }

  List<TimingRound> faceOff(Map<TimingDial, TimingOptions> options) => [
        for (final dial in TimingDial.values)
          TimingRound(Cue.both, options[dial]!, dial: dial),
      ]..shuffle(random);

  static TimingDial? winner(List<TimingResult> results) {
    final current =
        results.singleWhere((r) => r.round.dial == TimingDial.current);
    if (!current.usable) return null;
    final halves = current.halfErrors;
    int topHits(TimingResult result) {
      final counts = result.judgements;
      return counts[TapJudgement.marvelous]! + counts[TapJudgement.perfect]!;
    }

    final contenders = results.where((r) {
      if (r.round.options == current.round.options || !r.usable) return false;
      final errors = r.halfErrors;
      return current.meanError - r.meanError >= 5 &&
          errors[0] < halves[0] &&
          errors[1] < halves[1] &&
          topHits(r) >= topHits(current);
    }).toList()
      ..sort((a, b) => a.meanError.compareTo(b.meanError));
    if (contenders.isEmpty ||
        (contenders.length > 1 &&
            contenders[1].meanError - contenders[0].meanError < 3)) {
      return null;
    }
    return contenders.first.round.dial;
  }
}
