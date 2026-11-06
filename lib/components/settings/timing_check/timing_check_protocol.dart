/// Name: TimingCheckProtocol
/// Parent: TimingCheckPage
/// Description: Tap timing, cue experiments and the repeated face-off.
library;

import 'dart:math' as math;

const beatMs = 400;
const countInBeats = 4;
const scoredBeats = 16;
const practiceLoopMs = scoredBeats * beatMs;
const firstBeatMs = (countInBeats + 1) * beatMs;
const roundEndMs = firstBeatMs + (scoredBeats - 1) * beatMs + beatMs;
const baselineRounds = 8;
const faceOffRuns = 2;
const _minimumHits = 12;
const _minimumGain = 3;
const _minimumLead = 2;
const pullShiftMs = 20;

enum Cue {
  sound('Sound only'),
  arrows('Arrows only'),
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

enum Aim {
  early('Aimed early'),
  natural('Felt natural'),
  late('Aimed late');

  const Aim(this.label);
  final String label;
}

typedef TimingOptions = ({int judgement, int visual});

class TimingRound {
  const TimingRound(this.cue, this.options,
      {this.pullMs = 0, this.dial, this.run = 0});

  final Cue cue;
  final TimingOptions options;
  final int pullMs;
  final TimingDial? dial;
  final int run;

  // Positive judgement advances both targets. Positive visual delays only
  // the receptor crossing. The drum always stays on the music timeline.
  int get judgementMs => -options.judgement;
  int get crossingMs => judgementMs + options.visual + pullMs;

  ({int index, double error}) matchTap(double elapsedMs,
      {int firstMs = firstBeatMs}) {
    // Match around the active cue (or the midpoint of both cues), then
    // measure the tap against judgement independently of arrow position.
    final cueOffset = switch (cue) {
      Cue.sound => 0.0,
      Cue.arrows => crossingMs.toDouble(),
      Cue.both => crossingMs / 2,
    };
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

  // Share of all notes in the Marvelous window, misses in the denominator.
  int get tightHits => judgements[TapJudgement.marvelous]!;

  double? get spread {
    final middle = center;
    return middle == null
        ? null
        : median(timedHits.map((t) => (t - middle).abs()));
  }

  Aim? aim;
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

  // Two blocks of every cue, in different orders. One hidden arrow shift sits
  // in each block among rounds labelled the same.
  List<TimingRound> baseline() {
    final pulls = [-pullShiftMs, pullShiftMs]..shuffle(random);
    List<TimingRound> block(int pull) => [
          TimingRound(Cue.sound, current),
          TimingRound(Cue.arrows, current),
          TimingRound(Cue.both, current),
          TimingRound(Cue.both, current, pullMs: pull),
        ]..shuffle(random);
    final first = block(pulls[0]);
    var second = block(pulls[1]);
    while (second.first.cue == first.first.cue) {
      second = block(pulls[1]);
    }
    return [...first, ...second];
  }

  Map<TimingDial, TimingOptions> candidates(List<TimingResult> baseline) {
    final sound = cueCenter(baseline, Cue.sound);
    final bias = cueCenter(baseline, Cue.both);
    final weight = follow(baseline);
    final visualDelta = bias == null || weight == null || weight < 0.25
        ? 0
        : (-bias / weight).round().clamp(-40, 40);
    final judgementDelta = sound == null ? 0 : (-sound).round().clamp(-40, 40);
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

  // The average center of a cue's usable, unshifted rounds.
  static double? cueCenter(List<TimingResult> baseline, Cue cue) {
    final centers = [
      for (final r in baseline)
        if (r.round.cue == cue && r.round.pullMs == 0 && r.usable) r.center!,
    ];
    return centers.isEmpty
        ? null
        : centers.reduce((a, b) => a + b) / centers.length;
  }

  static double? follow(List<TimingResult> baseline) {
    final early = baseline.firstWhere((r) => r.round.pullMs == -pullShiftMs);
    final late = baseline.firstWhere((r) => r.round.pullMs == pullShiftMs);
    if (!early.usable || !late.usable) return null;
    return (late.center! - early.center!) / (2 * pullShiftMs);
  }

  List<TimingRound> faceOff(Map<TimingDial, TimingOptions> options) => [
        for (var run = 0; run < faceOffRuns; run++)
          ...[
            for (final dial in TimingDial.values)
              TimingRound(Cue.both, options[dial]!, dial: dial, run: run),
          ]..shuffle(random),
      ];

  // A dial wins only by beating the current settings in every run, by a real
  // margin overall and clear of the other dial.
  static TimingDial? winner(List<TimingResult> results) {
    Iterable<TimingResult> runs(TimingDial dial) =>
        results.where((r) => r.round.dial == dial);
    int total(TimingDial dial) =>
        runs(dial).fold(0, (sum, r) => sum + r.tightHits);
    final current = runs(TimingDial.current).toList();
    final contenders = [TimingDial.judgement, TimingDial.visual].where((dial) {
      final trial = runs(dial).toList();
      if (trial.first.round.options == current.first.round.options) {
        return false;
      }
      return trial.every((r) =>
              r.usable && r.tightHits > current[r.round.run].tightHits) &&
          total(dial) - total(TimingDial.current) >= _minimumGain;
    }).toList()
      ..sort((a, b) => total(b).compareTo(total(a)));
    if (contenders.isEmpty ||
        (contenders.length > 1 &&
            total(contenders[0]) - total(contenders[1]) < _minimumLead)) {
      return null;
    }
    return contenders.first;
  }
}

/// Puts taps on the music's timeline. The audio clock says when the track
/// really started, input timestamps say when a finger landed rather than when
/// the frame handled it, and the device delay covers output no API reports.
class TapClock {
  TapClock(this.delayMs);

  int delayMs;
  double? _audioStart;
  double? _inputGap;
  final _taps = <({double elapsed, double? at})>[];

  // Position advances a buffer at a time, so the smallest gap is the truest.
  void audioAt(double elapsedMs, Duration position) {
    if (position == Duration.zero) return;
    final start = elapsedMs - position.inMicroseconds / 1000;
    _audioStart = math.min(_audioStart ?? start, start);
  }

  double music(double elapsedMs) => elapsedMs - (_audioStart ?? 0) - delayMs;

  double tap(double elapsedMs, Duration? at) {
    final atMs = at == null ? null : at.inMicroseconds / 1000;
    if (atMs != null) {
      final gap = elapsedMs - atMs;
      _inputGap = math.min(_inputGap ?? gap, gap);
    }
    final tap = (elapsed: elapsedMs, at: atMs);
    _taps.add(tap);
    return _musicOf(tap);
  }

  double _musicOf(({double elapsed, double? at}) tap) =>
      music(tap.at == null ? tap.elapsed : tap.at! + _inputGap!);

  // Later taps sharpen the input gap, so a round is timed once it's over.
  Iterable<double> get taps => _taps.map(_musicOf);
}
