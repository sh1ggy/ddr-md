/// Name: EditionCatalog
/// Parent: EditionRules, EditionPainter
/// Description: Typed material recipes and bounded geometry tuning.
library;

import 'package:flutter/painting.dart';
import 'edition_model.dart';

const editionBorders = {
  'gilded': EditionBorder.gilded,
  'engraved': EditionBorder.engraved,
  'bevel': EditionBorder.bevel
};
const editionFramePalettes = {
  EditionFrame.stock: [Color(0xFF181A24), Color(0xFF676473), Color(0xFF242632)],
  EditionFrame.bronze: [
    Color(0xFF4A2814),
    Color(0xFFF2C394),
    Color(0xFF9C5A2C)
  ],
  EditionFrame.silver: [
    Color(0xFF454D5A),
    Color(0xFFEAF1FA),
    Color(0xFF8F9DAF)
  ],
  EditionFrame.gold: [Color(0xFF694014), Color(0xFFFFE3A0), Color(0xFFC48822)],
  // Pearly white gold: PFC's gold, paler, with a pearl's pink-cream light.
  EditionFrame.platinum: [
    Color(0xFF7E5A22),
    Color(0xFFFFF5DE),
    Color(0xFFDDB86A)
  ],
  EditionFrame.rainbow: [
    Color(0xFF6E6F9E),
    Color(0xFFFFFFFF),
    Color(0xFFB8DDF6)
  ],
};
const editionFrameWidths = {
  EditionFrame.stock: .014,
  EditionFrame.bronze: .023,
  EditionFrame.silver: .030,
  EditionFrame.gold: .040,
  EditionFrame.platinum: .043,
  EditionFrame.rainbow: .045
};
const editionSpectrum = [
  Color(0x33FF78AB),
  Color(0x33FFD57B),
  Color(0x3383EDBA),
  Color(0x3383CFFF),
  Color(0x33BB9FFF)
];
// SDP's pearl: the platinum frame's inlay and its sheen over the art.
const editionPearl = [
  Color(0x1FFFD6DE),
  Color(0x1FFFEBB8),
  Color(0x1FFFDFA0),
  Color(0x1FF4E4F0),
  Color(0x1FFFDCC4)
];
const editionFinishAlpha = [0.0, .06, .10, .12, .14, .16];
const editionGlintCount = 6;
// MFC's frame, round the card.
// The badges' rainbow (kFlareExColors), round the card.
const editionRainbowFrame = [
  Color(0xFFFF5A5A),
  Color(0xFFFFB84D),
  Color(0xFFFFF15A),
  Color(0xFF5AFF8C),
  Color(0xFF5AC8FF),
  Color(0xFFB45AFF),
  Color(0xFFFF5A5A),
];
// AAA's foil, the AAA badge's gold at a lighter touch over art.
const editionGoldFoil = [
  Color(0x408A6512),
  Color(0x40FFE98A),
  Color(0x40C99A1E),
  Color(0x40FFF6CF),
  Color(0x40A8780F),
  Color(0x408A6512),
];
// Flare aura: particles per rank within a band, EX's, the small card's, and
// each halo ring's width, of the card's side.
const editionSparksPerRank = 3;
const editionMaxSparks = 16;
const editionCompactSparks = 4;
const editionHaloWidth = .008;
// Flare EX's polychrome over the art, mirrored so its bands never seam.
const editionPolychrome = [
  Color(0xFFFF4D6D),
  Color(0xFFFFB347),
  Color(0xFFF9F871),
  Color(0xFF4DFFA0),
  Color(0xFF4DC3FF),
  Color(0xFFB04DFF),
];
const editionPolychromeAlpha = .55;
// Negative: the art inverted, leaning blue-violet.
const editionNegative = ColorFilter.matrix([
  -.9, 0, 0, 0, 225, //
  0, -.85, 0, 0, 210,
  0, 0, -1, 0, 255,
  0, 0, 0, 1, 0,
]);
const editionMaxMotifLines = 52;
// CPU display lists only: no application-owned effect textures. The active viewer
// owns two small pictures and releases them on recipe/size change/disposal.
// Engine raster caches still need device allocation measurements. There is
// deliberately no cross-chart cache or offscreen image allocation.
const editionMaxSide = 640.0;

/// The tier's gems along the frame's foot, one lit per step: each gem's
/// width and their spacing, of the card's side.
const editionGemSize = .036;
const editionGemGap = .048;
const editionGem = [Color(0xFFF4FDFF), Color(0xFF8FD8FF), Color(0xFF2E6FA8)];

/// Ten deliberate cuts, one per tier: broad sheen through a dense faceted
/// prism; neutral without one. The
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

/// Each difficulty's corners, of the card's side: rounded by [size], or cut
/// off at 45° [size] along each edge. Unknown, then beginner to challenge.
/// [alternate] cuts only the top left and bottom right, rounding the others
/// slightly.
const editionCorners = [
  (round: true, size: .065, alternate: false),
  (round: true, size: .10, alternate: false),
  (round: true, size: .05, alternate: false),
  (round: false, size: .07, alternate: true),
  (round: false, size: .05, alternate: false),
  (round: false, size: .09, alternate: false),
];

// Logical pixels around each icon's silhouette, rather than a label panel.
const editionStampRim = 1.8;
// The band across the art's foot, of the card's side.
const editionFooterHeight = .09;
const editionCompactMotifLines = 8;
const editionCompactGlints = 4;
const editionCompactFinishStrength = .55;
const editionTiltRadians = .14;
