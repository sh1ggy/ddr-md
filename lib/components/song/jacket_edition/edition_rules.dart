/// Name: EditionRules
/// Parent: JacketEdition, EditionLabPage
/// Description: Pure achievement/axis to material selection.
library;

import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks, kInGameDifficultyNames;
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/version_group.dart';
import 'edition_model.dart';
import 'edition_catalog.dart';

// As the grade badges: only AAA is foiled; the rest leave the art clean.
EditionFinish finishFor(Grade? grade) =>
    grade == Grade.aaa ? EditionFinish.prism : EditionFinish.print;

int? editionTier(int? level) {
  if (level == null || level < 1 || level > editionTierCeilings.last) {
    return null;
  }
  return editionTierCeilings.indexWhere((ceiling) => level <= ceiling) + 1;
}

EditionRecipe resolveEdition(EditionFacts facts,
    [EditionOptions options = defaultEditionOptions]) {
  final precision = facts.precision?.award;
  final lamp = facts.lamp;
  final frame = lamp == ClearLamp.mfc || precision == PrecisionAward.mfc
      ? EditionFrame.starlight
      : lamp == ClearLamp.pfc ||
              precision == PrecisionAward.pfc ||
              precision == PrecisionAward.sdp
          ? EditionFrame.gold
          : lamp == ClearLamp.fc ||
                  lamp == ClearLamp.gfc ||
                  lamp == ClearLamp.life4
              ? EditionFrame.silver
              : EditionFrame.stock;
  final tier = editionTier(facts.level);
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
    cut: tier == null ? EditionCut.neutral : EditionCut.values[tier],
    border: editionBorders[options.borderId] ?? EditionBorder.gilded,
    tier: tier,
    difficultyShape: difficulty == null
        ? 0
        : kInGameDifficultyNames.values.toList().indexOf(difficulty) + 1,
    flareIndex: flare,
    ex: facts.flare == 'EX',
    secret: frame == EditionFrame.gold && precision == PrecisionAward.sdp,
    failed: lamp == ClearLamp.failed || facts.grade == Grade.e,
    negative: facts.levelTop,
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
    levelStamp: options.difficultyStamp && tier != null ? facts.level : null,
    // Ten cuts use single-digit display indices .0–.9; the optical tier
    // itself remains 1–10 in the recipe/catalog.
    tierSuffix: options.tierSuffix && options.difficultyStamp && tier != null
        ? tier - 1
        : null,
  );
}
