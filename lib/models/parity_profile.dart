/// Name: Parity profile
/// Parent: ParityQuizPage, ChartScroller
/// Description: A player's parity weights, fitted to their questionnaire
/// answers. The fit nudges the few weights the questions speak to until the
/// engine reads each moment the way the player chose, staying as close to the
/// defaults as it can. The active profile is what the chart preview solves with.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/parity_labels.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';

/// One answered moment: a stretch of its chart, its lead-in held on the feet
/// every option shares (so the stretch can't start on the opposite foot from
/// the full chart), and the feet the player chose from the key row on.
class FitCase {
  final List<StepNote> notes;
  final Map<StepNote, ParityFoot> leadIn;
  final Map<StepNote, ParityFoot> chosen;

  const FitCase(this.notes, this.leadIn, this.chosen);

  /// Share of the chosen notes the solve under [w] agrees with; 1 is a match.
  double agreement(ParityWeights w) {
    final feet =
        analyseParity(notes, Modes.singles, weights: w, pins: leadIn).feet;
    return chosen.entries.where((e) => feet[e.key] == e.value).length /
        chosen.length;
  }

  bool matches(ParityWeights w) => agreement(w) == 1;
}

class FitResult {
  final ParityWeights weights;
  final List<bool> before;
  final List<bool> after;

  const FitResult(this.weights, this.before, this.after);
}

/// The weights the questions speak to, with how each reads to a player.
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
/// change only if it scores higher, or as high closer to the defaults. Whole
/// matching moments count most; partly matching ones break ties so the search
/// can climb towards a moment before it flips.
FitResult fitProfile(List<FitCase> cases) {
  double score(ParityWeights w) {
    final a = [for (final c in cases) c.agreement(w)];
    return a.where((x) => x == 1).length + a.fold(0.0, (s, x) => s + x) / 100;
  }

  final defaults = ParityWeights.defaults.toJson();
  double drift(Map<String, double> w) => tunableWeights.keys
      .map((k) => (math.log(w[k]! / defaults[k]!)).abs())
      .fold(0, (a, b) => a + b);

  var best = Map<String, double>.of(defaults);
  var bestScore = score(ParityWeights.defaults);
  for (int pass = 0; pass < 3 && bestScore < cases.length; pass++) {
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
    [for (final c in cases) c.matches(ParityWeights.defaults)],
    [for (final c in cases) c.matches(fitted)],
  );
}

/// How often each flagged pattern shows up across [charts] under [w], for
/// showing what a profile does beyond the questions themselves.
Map<ParityFlag, int> flagCounts(List<List<StepNote>> charts, ParityWeights w) {
  final counts = {for (final f in ParityFlag.values) f: 0};
  for (final notes in charts) {
    final flags =
        findFlags(notes, analyseParity(notes, Modes.singles, weights: w), Modes.singles);
    for (final MapEntry(key: f, value: at) in flags.entries) {
      counts[f] = counts[f]! + at.length;
    }
  }
  return counts;
}

/// "Ours" (the shipped weights) or "Yours" (fitted to the questionnaire). The
/// latest fit is always kept, so switching between them never needs a retake.
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
