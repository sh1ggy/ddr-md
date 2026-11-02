/// Name: EditionModel
/// Parent: JacketEdition
/// Description: Immutable input facts and comparable resolved materials.
library;

import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/version_group.dart';

enum EditionFinish { print, satin, metallic, holo, texturedHolo, prism }

enum EditionFrame { stock, bronze, silver, gold, platinum, rainbow }

enum EditionMotif { neutral, classic, white, gold }

enum EditionCut {
  neutral,
  broad,
  split,
  cross,
  diamond,
  fan,
  lattice,
  shard,
  star,
  brilliant,
  fine
}

enum EditionBorder { gilded, engraved, bevel }

/// A card's layers, back to front, each earned separately: the art (and
/// what's done to it: negative, EX's polychrome), the grade's finish over
/// it, the lamp's frame round it and the flare's aura beyond.
enum EditionLayer { art, finish, frame, aura }

const editionAllLayers = {...EditionLayer.values};

typedef EditionChartKey = ({String song, String mode, String difficulty});
typedef EditionOptions = ({
  String borderId,
  bool effects,
  bool motion,
  bool modeStamp,
  bool gradeStamp,
  bool difficultyStamp,
  bool tierSuffix
});
const defaultEditionOptions = (
  borderId: 'gilded',
  effects: true,
  motion: true,
  modeStamp: true,
  gradeStamp: true,
  difficultyStamp: true,
  tierSuffix: true
);

class EditionFacts {
  const EditionFacts(
      {required this.chart,
      this.level,
      this.tier,
      this.version,
      this.grade,
      this.flare,
      this.lamp,
      this.precision,
      this.score,
      this.hardestTop = false});
  final EditionChartKey chart;
  final int? level;
  // How hard the chart is within its level, easy 0 to hard 9, as 17.0–17.9.
  // From community ratings, which aren't loaded yet.
  final int? tier;
  final FlareGroup? version;
  final Grade? grade;
  final String? flare;
  final ClearLamp? lamp;
  final PrecisionEvidence? precision;
  final int? score;
  // The player's highest score at the hardest level they play.
  final bool hardestTop;
}

/// Value equality comes from records. No picture, image, database or ticker
/// is stored here; the resolver runs only when facts/options change.
typedef EditionRecipe = ({
  EditionFinish finish,
  EditionFrame frame,
  EditionMotif motif,
  EditionCut cut,
  EditionBorder border,
  int? tier,
  int difficultyShape,
  int flareIndex,
  bool ex,
  bool failed,
  bool negative,
  double strength,
  bool effects,
  bool motion,
  Grade? gradeStamp,
  int? scoreStamp,
  String? flareStamp,
  String? modeStamp,
  String? difficultyStamp,
  int? levelStamp,
  int? tierSuffix,
});

extension EditionRecipeDetails on EditionRecipe {
  bool get animated =>
      effects &&
      motion &&
      (finish != EditionFinish.print ||
          flareIndex >= 0 ||
          frame != EditionFrame.stock);
  Map<String, Object?> toJson() => {
        'finish': finish.name,
        'frame': frame.name,
        'motif': motif.name,
        'cut': cut.name,
        'border': border.name,
        'tier': tier,
        'difficultyShape': difficultyShape,
        'flareIndex': flareIndex,
        'ex': ex,
        'failed': failed,
        'negative': negative,
        'strength': strength,
        'effects': effects,
        'motion': motion,
        'gradeStamp': gradeStamp?.label,
        'scoreStamp': scoreStamp,
        'flareStamp': flareStamp,
        'modeStamp': modeStamp,
        'difficultyStamp': difficultyStamp,
        'levelStamp': levelStamp,
        'tierSuffix': tierSuffix,
      };
}
