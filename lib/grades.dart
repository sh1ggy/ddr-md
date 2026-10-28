/// Name: grades.dart
/// Description: DDR World scoring — money score, grade, EX score and
/// full-combo tier from judgement counts, plus their assets/icons art.
library;

import 'dart:ui' show Color;

import 'package:ddr_md/helpers.dart' show kFlareRanks, resolveOcrFlare;
import 'package:ddr_md/models/db_models.dart' show ClearLamp;
import 'package:flutter/painting.dart' show HSLColor;

/// Grades in descending order with their inclusive score floors.
/// E is a fail (gauge depleted) and is never reached by score alone.
enum Grade {
  aaa('AAA', 990000),
  aaPlus('AA+', 950000),
  aa('AA', 900000),
  aaMinus('AA-', 890000),
  aPlus('A+', 850000),
  a('A', 800000),
  aMinus('A-', 790000),
  bPlus('B+', 750000),
  b('B', 700000),
  bMinus('B-', 690000),
  cPlus('C+', 650000),
  c('C', 600000),
  cMinus('C-', 590000),
  dPlus('D+', 550000),
  d('D', 0),
  e('E', 0);

  final String label;
  final int minScore;
  const Grade(this.label, this.minScore);
}

/// Full-combo tiers, best first. None of them require a particular grade.
enum FullComboTier {
  mfc('MFC'), // all Marvelous
  pfc('PFC'), // Marvelous/Perfect only
  gfc('GFC'), // nothing below Great
  fc('FC'), // nothing below Good
  none('');

  final String label;
  const FullComboTier(this.label);
}

Grade gradeForScore(int score, {bool failed = false}) {
  if (failed) return Grade.e;
  return Grade.values.firstWhere((g) => g != Grade.e && score >= g.minScore);
}

/// DDR A (2016+) money score. The step score SC = 1,000,000 / N where N is
/// every judgement: steps (a jump counts once), freeze pairs (once per pair,
/// as [ok]/[ng]) and shock arrows. Marvelous and OK earn SC, Perfect SC-10,
/// Great 3/5*SC-10, Good 1/5*SC-10, Miss and NG nothing. In-game the
/// fractional part of SC is spread across notes so the total stays a multiple
/// of 10; summing aggregate counts in doubles and flooring the total to a
/// multiple of 10 reproduces that, including the exact 1,000,000 cap.
int calcScore({
  required int marvelous,
  required int perfect,
  required int great,
  required int good,
  required int miss,
  int ok = 0,
  int ng = 0,
}) {
  final n = marvelous + perfect + great + good + miss + ok + ng;
  if (n == 0) return 0;
  final sc = 1000000 / n;
  final raw = (marvelous + ok) * sc +
      perfect * (sc - 10) +
      great * (sc * 3 / 5 - 10) +
      good * (sc / 5 - 10);
  return ((raw / 10).floor() * 10).clamp(0, 1000000);
}

/// EX score, for display/accuracy only — grades never use it.
int calcExScore({
  required int marvelous,
  required int perfect,
  required int great,
  int ok = 0,
}) =>
    (marvelous + ok) * 3 + perfect * 2 + great;

FullComboTier fullComboTier({
  required int marvelous,
  required int perfect,
  required int great,
  required int good,
  required int miss,
  int ng = 0,
}) {
  if (miss > 0 || ng > 0) return FullComboTier.none;
  if (perfect == 0 && great == 0 && good == 0) return FullComboTier.mfc;
  if (great == 0 && good == 0) return FullComboTier.pfc;
  if (good == 0) return FullComboTier.gfc;
  return FullComboTier.fc;
}

// The generic CLEAR lamp, for clears that earned no full-combo tier.
const clearIcon = 'assets/icons/cl_li4clear.png';
const life4Icon = 'assets/icons/cl_life4.png';

/// Grade art (_p = plus, _m = minus).
String gradeIcon(Grade grade) => 'assets/icons/rank_'
    '${grade.label.toLowerCase().replaceAll('+', '_p').replaceAll('-', '_m')}.png';

String? fullComboIcon(FullComboTier tier) {
  switch (tier) {
    case FullComboTier.mfc:
      return 'assets/icons/cl_marv.png';
    case FullComboTier.pfc:
      return 'assets/icons/cl_perf.png';
    case FullComboTier.gfc:
      return 'assets/icons/cl_great.png';
    case FullComboTier.fc:
      return 'assets/icons/cl_good.png';
    case FullComboTier.none:
      return null;
  }
}

// Each letter in its art's colour, + a shade lighter and - a shade darker.
Color gradeColor(Grade g) {
  final base = switch (g.label[0]) {
    'A' when g.label.startsWith('AAA') => const Color(0xFFE8C930),
    'A' when g.label.startsWith('AA') => const Color(0xFFB0BEC5),
    'A' => const Color(0xFFD63A4F),
    'B' => const Color(0xFFF2701F),
    'C' => const Color(0xFFF5B400),
    'D' => const Color(0xFF2F6FE0),
    _ => const Color(0xFF616161),
  };
  final hsl = HSLColor.fromColor(base);
  final shift = g.label.endsWith('+')
      ? 0.12
      : g.label.endsWith('-')
          ? -0.12
          : 0.0;
  return hsl.withLightness((hsl.lightness + shift).clamp(0.0, 1.0)).toColor();
}

/// Each clear lamp's colour, after its lamp art.
const kLampColors = {
  ClearLamp.mfc: Color(0xFFB3E5FC),
  ClearLamp.pfc: Color(0xFFFFC107),
  ClearLamp.gfc: Color(0xFF66BB6A),
  ClearLamp.fc: Color(0xFF42A5F5),
  ClearLamp.life4: Color(0xFFE8344E),
  ClearLamp.clear: Color(0xFFFF9800),
  ClearLamp.failed: Color(0xFF757575),
};

/// A flare rank's colour wherever one stands for it: its card's frame
/// ([kFlareCardColors]), or for EX the first of its rainbow.
Color flareColor(String rank) => rank == 'EX'
    ? kFlareExColors.first
    : kFlareCardColors[kFlareRanks.indexOf(rank)].frame;

const kFlareExColors = [
  Color(0xFFFF5A5A),
  Color(0xFFFFB84D),
  Color(0xFFFFF15A),
  Color(0xFF5AFF8C),
  Color(0xFF5AC8FF),
  Color(0xFFB45AFF),
];

/// The frame and back of the flare-tinted card the cabinet's song select
/// gives a chart, I to IX. EX's frame is a rainbow of [kFlareExColors].
const kFlareCardColors = [
  (frame: Color(0xFF0065BD), back: Color(0xFF232E4C)),
  (frame: Color(0xFF10AADE), back: Color(0xFF233846)),
  (frame: Color(0xFF18B210), back: Color(0xFF124223)),
  (frame: Color(0xFFF6B200), back: Color(0xFF493610)),
  (frame: Color(0xFFA40400), back: Color(0xFF361010)),
  (frame: Color(0xFF41188B), back: Color(0xFF181039)),
  (frame: Color(0xFFBDBABD), back: Color(0xFF413A36)),
  (frame: Color(0xFFEEEEEE), back: Color(0xFF7D7D7D)),
  (frame: Color(0xFFFFDE20), back: Color(0xFF3E2A0D)),
];

/// Icon asset for a canonical flare rank from [kFlareRanks].
String flareRankIcon(String rank) => rank == 'EX'
    ? 'assets/icons/flare_ex.png'
    : 'assets/icons/flare_${kFlareRanks.indexOf(rank) + 1}.png';

const _kFlarePlanets = [
  'NONE', 'MERCURY', 'VENUS', 'EARTH', 'MARS', 'JUPITER', 'SATURN', //
  'URANUS', 'NEPTUNE', 'SUN', 'WORLD',
];

/// Each flare skill planet's main colour, NONE to WORLD, toned to read as
/// text on light and dark cards.
const kFlareClassColors = [
  Color(0xFF8C8C8C),
  Color(0xFF0C9CE4),
  Color(0xFFF0A00C),
  Color(0xFF10B478),
  Color(0xFFF03C14),
  Color(0xFFC8965A),
  Color(0xFFB4306C),
  Color(0xFF30C0C8),
  Color(0xFF4058C0),
  Color(0xFFFC5A0C),
  Color(0xFF9C48E0),
];

int _flarePlanet(String name) =>
    _kFlarePlanets.indexOf(name.replaceAll('+', ''));

/// Icon asset for a flare skill class name from `flareClass` ("EARTH++" →
/// the EARTH planet).
String flareClassIcon(String name) =>
    'assets/icons/flare_skill_${(_flarePlanet(name) + 1).toString().padLeft(2, '0')}.png';

/// Text colour for a flare skill class name, its planet's main colour.
Color flareClassColor(String name) => kFlareClassColors[_flarePlanet(name)];

/// Icon for the flare rank as detected by OCR ([Score.flare]). Accepts the
/// raw reading: an optional FLARE prefix, then a roman numeral I-IX, a digit,
/// "EX", or "NONE" (see [resolveOcrFlare], which normalises 1/l misreads of I
/// so "FLARE 1X" still correlates to flare_9). No flare or an unreadable
/// reading gets no icon.
String? flareIcon(String flare) {
  final rank = resolveOcrFlare(flare);
  if (rank != null) return flareRankIcon(rank);
  return null;
}
