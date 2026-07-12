/// Name: grades.dart
/// Description: DDR World scoring — money score, grade, EX score and
/// full-combo tier from judgement counts, plus their assets/icons art.
library;

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
  return Grade.values
      .firstWhere((g) => g != Grade.e && score >= g.minScore);
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

/// Grade art (_p = plus, _m = minus). Grades without art in assets/icons
/// (A-, the B/C/D tiers below B+) return null; callers should fall back to
/// Grade.label.
String? gradeIcon(Grade grade) {
  switch (grade) {
    case Grade.aaa:
      return 'assets/icons/rank_aaa.png';
    case Grade.aaPlus:
      return 'assets/icons/rank_aa_p.png';
    case Grade.aa:
      return 'assets/icons/rank_aa.png';
    case Grade.aaMinus:
      return 'assets/icons/rank_aa_m.png';
    case Grade.aPlus:
      return 'assets/icons/rank_a_p.png';
    case Grade.a:
      return 'assets/icons/rank_a.png';
    case Grade.bPlus:
      return 'assets/icons/rank_b_p.png';
    case Grade.e:
      return 'assets/icons/rank_e.png';
    default:
      return null;
  }
}

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

/// Icon for the flare rank as detected by OCR ([Score.flare]). Accepts the
/// raw reading: an optional FLARE prefix, then a roman numeral I-IX, a digit,
/// "EX", or "NONE". 1/l misreads of I are normalised before matching, so
/// "FLARE 1X" still correlates to flare_9.
String? flareIcon(String flare) {
  const romans = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX'];
  var f = flare.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (f.startsWith('FLARE')) f = f.substring(5);
  if (f.isEmpty || f == 'NONE' || f == '0') return 'assets/icons/icon_0.png';
  if (f == 'EX') return 'assets/icons/flare_ex.png';
  final level =
      int.tryParse(f) ?? romans.indexOf(f.replaceAll(RegExp(r'[1L]'), 'I')) + 1;
  if (level >= 1 && level <= 9) return 'assets/icons/flare_$level.png';
  return null;
}
