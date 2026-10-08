/// Name: Parity profile
/// Parent: FootingStylePage, ChartScroller
/// Description: A player's parity weights, learned from the feet they set by
/// hand while studying charts. The fit nudges a few weights until the unpinned
/// engine places as many of those feet as it can, staying as close to the
/// defaults as possible, so corrections on one chart carry to the rest. The
/// active profile is what the chart preview solves with.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/parity_labels.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';

/// One edited chart: its notes and the feet the player set by hand.
class FitCase {
  final List<StepNote> notes;
  final Modes mode;
  final Map<StepNote, ParityFoot> chosen;

  const FitCase(this.notes, this.mode, this.chosen);

  /// How many of the hand-set feet the unpinned solve under [w] agrees with.
  int matched(ParityWeights w) {
    final feet = analyseParity(notes, mode, weights: w).feet;
    return chosen.entries.where((e) => feet[e.key] == e.value).length;
  }
}

class FitResult {
  final ParityWeights weights;
  final List<int> before;
  final List<int> after;

  const FitResult(this.weights, this.before, this.after);
}

/// The weights the fit may move, with how each reads to a player.
const Map<String, String> tunableWeights = {
  'doublestep': 'Doublesteps',
  'footswitch': 'Footswitches',
  'facing': 'Turning',
  'spin': 'Spins',
  'bracket': 'Brackets',
  'jack': 'Jacks',
  'distance': 'Reaching',
  'sideswitch': 'Side switches',
};

const List<double> _steps = [0.25, 0.5, 0.75, 1.5, 2, 4];

/// Coordinate search over [tunableWeights] in multiplicative steps: keep a
/// change only if the engine gets more hand-set feet right, or as many closer
/// to the defaults.
FitResult fitProfile(List<FitCase> cases) {
  int score(ParityWeights w) =>
      cases.fold(0, (sum, c) => sum + c.matched(w));
  final total = cases.fold(0, (sum, c) => sum + c.chosen.length);
  final defaults = ParityWeights.defaults.toJson();
  double drift(Map<String, double> w) => tunableWeights.keys
      .map((k) => (math.log(w[k]! / defaults[k]!)).abs())
      .fold(0, (a, b) => a + b);

  var best = Map<String, double>.of(defaults);
  var bestScore = score(ParityWeights.defaults);
  for (int pass = 0; pass < 3 && bestScore < total; pass++) {
    var improved = false;
    for (final k in tunableWeights.keys) {
      for (final step in _steps) {
        final trial = {...best, k: best[k]! * step};
        final s = score(ParityWeights.fromJson(trial));
        if (s > bestScore || (s == bestScore && drift(trial) < drift(best))) {
          best = trial;
          bestScore = s;
          improved = true;
        }
      }
    }
    if (!improved) break;
  }
  final fitted = ParityWeights.fromJson(best);
  return FitResult(
    fitted,
    [for (final c in cases) c.matched(ParityWeights.defaults)],
    [for (final c in cases) c.matched(fitted)],
  );
}

/// "Default" (the shipped weights) or "Yours" (fitted to the player's footing
/// edits). The latest fit is always kept, so switching never loses it.
class ParityProfile {
  static ParityWeights? get yours {
    final raw = Settings.getString(Settings.parityProfileKey);
    if (raw.isEmpty) return null;
    return ParityWeights.fromJson(json.decode(raw) as Map<String, dynamic>);
  }

  static void saveYours(ParityWeights weights) => Settings.setString(
      Settings.parityProfileKey, json.encode(weights.toJson()));

  static bool get usingYours =>
      Settings.getInt(Settings.parityProfileOnKey) == 1 && yours != null;

  static set usingYours(bool on) =>
      Settings.setInt(Settings.parityProfileOnKey, on ? 1 : 0);

  /// What the chart preview solves with.
  static ParityWeights get active =>
      usingYours ? yours! : ParityWeights.defaults;
}

/// The latest fit over every edited chart, for the Footing Style page.
class FootingFit {
  final List<ChartRef> charts;
  final List<int> pinCounts;
  final FitResult result;

  const FootingFit(this.charts, this.pinCounts, this.result);
}

/// Re-fit Yours from every hand-set foot, off the UI isolate, and keep it.
/// Null when nothing has been edited yet.
Future<FootingFit?> refitFromEdits() async {
  final charts = <ChartRef>[];
  final cases = <FitCase>[];
  for (final MapEntry(key: (ref, hash), value: pins)
      in (await DatabaseProvider.getAllParityPins()).entries) {
    final mode = ref.mode == 'dp' ? Modes.doubles : Modes.singles;
    final notes =
        (await StepsLoader.load(ref.song))?.chartFor(mode, ref.difficulty)?.notes;
    // Pins from an older version of the chart can't be placed on this one.
    if (notes == null || chartHash(notes) != hash) continue;
    charts.add(ref);
    cases.add(FitCase(notes, mode, pinsByNote(pins, notes)));
  }
  if (cases.isEmpty) return null;
  final result = await compute(fitProfile, cases);
  ParityProfile.saveYours(result.weights);
  return FootingFit(charts, [for (final c in cases) c.chosen.length], result);
}
