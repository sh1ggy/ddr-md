/// Name: NoteDensity
/// Parent: SongChart
/// Description: A chart's steps per second over the song, split by note colour
library;

import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/models/steps_model.dart';

/// The rate at which the ribbon reaches full brightness, for every chart, so
/// harder charts visibly burn brighter.
const kDensityScale = 12.0;

/// Stacking order, slowest colours first.
const kDensityColours = [
  QuantColors.quarter,
  QuantColors.eighth,
  QuantColors.twelfth,
  QuantColors.sixteenth,
  QuantColors.twentyfourth,
  QuantColors.thirtysecond,
  QuantColors.other,
];

class NoteDensity {
  /// Per bin, a count per [kDensityColours] entry.
  final List<List<int>> bins;
  final double binSeconds;

  const NoteDensity._(this.bins, this.binSeconds);

  /// A jump is one step, a hold counts once at its start, mines don't count.
  factory NoteDensity.of(List<StepNote> notes, double length,
      {int binCount = 48}) {
    final bins = List.generate(
        binCount, (_) => List<int>.filled(kDensityColours.length, 0));
    final binSeconds = length / binCount;
    final seen = <double>{};
    for (final n in notes) {
      if (n.type == StepType.mine || !seen.add(n.beat)) continue;
      final colour = kDensityColours.indexOf(QuantColors.forBeat(n.beat));
      bins[(n.second / binSeconds).floor().clamp(0, binCount - 1)][colour]++;
    }
    return NoteDensity._(bins, binSeconds);
  }

  double rate(int bin) => bins[bin].fold<int>(0, (a, b) => a + b) / binSeconds;
}
