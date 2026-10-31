/// Name: EditionRules
/// Parent: JacketEdition
/// Description: Pure achievement/axis to material selection.
library;

import 'dart:math' as math;

import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks, kInGameDifficultyNames;
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/version_group.dart';
import 'edition_model.dart';
import 'edition_catalog.dart';

// As the grade badges: only AAA is foiled; the rest leave the art clean.
EditionFinish finishFor(Grade? grade) =>
    grade == Grade.aaa ? EditionFinish.prism : EditionFinish.print;

EditionRecipe resolveEdition(EditionFacts facts,
    [EditionOptions options = defaultEditionOptions]) {
  final precision = facts.precision?.award;
  final lamp = facts.lamp;
  // Frames run bronze (FC) to gold (PFC) in the lamp's tiers; SDP lifts
  // PFC's to platinum and MFC's is rainbow.
  final frame = lamp == ClearLamp.mfc || precision == PrecisionAward.mfc
      ? EditionFrame.rainbow
      : precision == PrecisionAward.sdp
          ? EditionFrame.platinum
          : EditionFrame.values[math.max(
              cardFrameTier(lamp), precision == PrecisionAward.pfc ? 3 : 0)];
  final tier = facts.tier;
  final difficulty = kInGameDifficultyNames[facts.chart.difficulty];
  final flare = kFlareRanks.indexOf(facts.flare ?? '');
  return (
    finish: finishFor(facts.grade),
    frame: frame,
    motif: switch (facts.version) {
      FlareGroup.classic => EditionMotif.classic,
      FlareGroup.white => EditionMotif.white,
      FlareGroup.gold => EditionMotif.gold,
      null => EditionMotif.neutral
    },
    cut: tier == null ? EditionCut.neutral : EditionCut.values[tier + 1],
    border: editionBorders[options.borderId] ?? EditionBorder.gilded,
    tier: tier,
    difficultyShape: difficulty == null
        ? 0
        : kInGameDifficultyNames.values.toList().indexOf(difficulty) + 1,
    flareIndex: flare,
    ex: facts.flare == 'EX',
    failed: lamp == ClearLamp.failed || facts.grade == Grade.e,
    negative: facts.hardestTop,
    strength: facts.grade?.label.endsWith('-') == true
        ? .65
        : facts.grade?.label.endsWith('+') == true
            ? 1.0
            : .85,
    effects: options.effects,
    motion: options.motion,
    modeStamp: options.modeStamp &&
            const ['singles', 'doubles'].contains(facts.chart.mode)
        ? facts.chart.mode
        : null,
    gradeStamp: options.gradeStamp ? facts.grade : null,
    scoreStamp: options.gradeStamp ? facts.score : null,
    flareStamp: options.gradeStamp && flare >= 0 ? facts.flare : null,
    difficultyStamp: options.difficultyStamp ? difficulty : null,
    levelStamp: options.difficultyStamp ? facts.level : null,
    tierSuffix: options.tierSuffix && options.difficultyStamp ? tier : null,
  );
}
