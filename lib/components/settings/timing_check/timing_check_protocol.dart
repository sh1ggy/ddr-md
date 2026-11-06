/// Name: TimingCheckProtocol
/// Parent: TimingCheckPage
/// Description: Tap timing and the hidden arrow shifts that show which cue a player follows.
library;

import 'dart:math' as math;

const beatMs = 400;
const countInBeats = 4;
const scoredBeats = 16;
const practiceLoopMs = scoredBeats * beatMs;
const firstBeatMs = (countInBeats + 1) * beatMs;
const roundEndMs = firstBeatMs + (scoredBeats - 1) * beatMs + beatMs;
const baselineRounds = 8;
const _minimumHits = 12;
const pullShiftMs = 20;

enum Cue {
  sound('Sound only'),
  arrows('Arrows only'),
  both('Sound + arrows');

  const Cue(this.label);
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
  const TimingRound(this.cue, this.options, {this.pullMs = 0});

  final Cue cue;
  final TimingOptions options;
  final int pullMs;

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

enum PlayerType { visual, audio, both }

class TimingProtocol {
  const TimingProtocol._();

  static const _shiftsEachWay = 3;
  static const _minimumShifts = 2;
  static const _visualFollow = 0.6;
  static const _audioFollow = 0.3;

  // Mostly hidden arrow shifts, labelled like any other round. The player's
  // cabinet dials don't matter: only how far taps move with the arrows does.
  static List<TimingRound> rounds(math.Random random) {
    const none = (judgement: 0, visual: 0);
    return [
      for (var i = 0; i < _shiftsEachWay; i++) ...[
        const TimingRound(Cue.both, none, pullMs: -pullShiftMs),
        const TimingRound(Cue.both, none, pullMs: pullShiftMs),
      ],
      const TimingRound(Cue.sound, none),
      const TimingRound(Cue.arrows, none),
    ]..shuffle(random);
  }

  static double? _shiftCenter(List<TimingResult> results, int pull) {
    final centers = [
      for (final r in results)
        if (r.round.pullMs == pull && r.usable) r.center!,
    ];
    return centers.length < _minimumShifts
        ? null
        : centers.reduce((a, b) => a + b) / centers.length;
  }

  // How much of an arrow shift the taps moved with: 0 stays on the beat.
  static double? follow(List<TimingResult> results) {
    final early = _shiftCenter(results, -pullShiftMs);
    final late = _shiftCenter(results, pullShiftMs);
    return early == null || late == null
        ? null
        : (late - early) / (2 * pullShiftMs);
  }

  static PlayerType? type(List<TimingResult> results) =>
      switch (follow(results)) {
        null => null,
        final f when f >= _visualFollow => PlayerType.visual,
        final f when f <= _audioFollow => PlayerType.audio,
        _ => PlayerType.both,
      };
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
