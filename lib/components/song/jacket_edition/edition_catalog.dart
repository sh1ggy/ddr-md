/// Name: EditionCatalog
/// Parent: EditionRules, EditionPainter
/// Description: Typed material recipes and bounded geometry tuning.
library;

import 'package:flutter/painting.dart';
import 'edition_model.dart';

/// Inclusive upper levels of the ten optical tiers. Invalid levels are neutral.
const editionTierCeilings = [2, 4, 6, 8, 10, 12, 14, 16, 18, 20];
const editionBorders = {
  'gilded': EditionBorder.gilded,
  'engraved': EditionBorder.engraved,
  'bevel': EditionBorder.bevel
};
const editionFramePalettes = {
  EditionFrame.stock: [Color(0xFF181A24), Color(0xFF676473), Color(0xFF242632)],
  EditionFrame.silver: [
    Color(0xFF454D5A),
    Color(0xFFEAF1FA),
    Color(0xFF8F9DAF)
  ],
  EditionFrame.gold: [Color(0xFF694014), Color(0xFFFFE3A0), Color(0xFFC48822)],
  EditionFrame.starlight: [
    Color(0xFF6E6F9E),
    Color(0xFFFFFFFF),
    Color(0xFFB8DDF6)
  ],
};
const editionFrameWidths = {
  EditionFrame.stock: .014,
  EditionFrame.silver: .023,
  EditionFrame.gold: .040,
  EditionFrame.starlight: .045
};
const editionSpectrum = [
  Color(0x33FF78AB),
  Color(0x33FFD57B),
  Color(0x3383EDBA),
  Color(0x3383CFFF),
  Color(0x33BB9FFF)
];
const editionFinishAlpha = [0.0, .06, .10, .12, .14, .16];
const editionGlintCount = 6;
const editionMaxMotifLines = 52;
// CPU display lists only: no application-owned effect textures. The active viewer
// owns two small pictures and releases them on recipe/size change/disposal.
// Engine raster caches still need device allocation measurements. There is
// deliberately no cross-chart cache or offscreen image allocation.
const editionMaxSide = 640.0;

/// Ten deliberate cuts: broad sheen through a dense faceted prism. The
/// renderer shares primitives; adding a cut changes data here, not branches.
const editionCuts = {
  EditionCut.neutral: (lines: 8, angle: 0.0, cross: false),
  EditionCut.broad: (lines: 8, angle: .10, cross: false),
  EditionCut.split: (lines: 12, angle: .25, cross: false),
  EditionCut.cross: (lines: 14, angle: .45, cross: true),
  EditionCut.diamond: (lines: 18, angle: .78, cross: true),
  EditionCut.fan: (lines: 22, angle: .18, cross: false),
  EditionCut.lattice: (lines: 26, angle: .0, cross: true),
  EditionCut.shard: (lines: 32, angle: .65, cross: false),
  EditionCut.star: (lines: 36, angle: 1.05, cross: true),
  EditionCut.brilliant: (lines: 42, angle: .40, cross: true),
  EditionCut.fine: (lines: 48, angle: .78, cross: true),
};
