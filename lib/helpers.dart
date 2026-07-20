/// Name: helpers.dart
/// Description: A file to store helper functions
library;

import 'dart:math';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:flutter/material.dart';

int findNearestReadSpeed(int songBpm, List array, int readSpeed) {
  var nearest = 0;
  array.asMap().entries.forEach((entry) {
    var i = entry.key;
    if (array[i] * songBpm <= readSpeed + constants.buffer) {
      nearest = i;
    }
  });
  return nearest;
}

// Checkable popup-menu row shared by the songlist sort and version-filter
// menus: a ListTile with an optional leading icon and a trailing check when
// selected. onTap must handle closing the menu (Navigator.pop).
PopupMenuItem menuListTileItem({
  required String title,
  IconData? leading,
  required bool checked,
  required VoidCallback onTap,
}) {
  return PopupMenuItem(
    padding: const EdgeInsets.all(0),
    child: ListTile(
      contentPadding: const EdgeInsets.only(left: 8, right: 8),
      hoverColor: Colors.transparent,
      onTap: onTap,
      leading: leading != null ? Icon(leading) : null,
      title: Text(title),
      trailing: checked ? const Icon(Icons.check) : null,
    ),
  );
}

// Parses a numeric OCR field reading into its integer value, dropping
// formatting noise like thousands separators or stray whitespace
// ("999,940" -> 999940). Returns null when there are no digits to read.
int? parseOcrNumber(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

// Levenshtein edit distance between two strings (two-row iterative form).
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = min(min(curr[j] + 1, prev[j + 1] + 1), prev[j] + cost);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

// In-game difficulty names keyed by the StepMania-style field names used in
// [Difficulty].
const Map<String, String> kInGameDifficultyNames = {
  'beginner': 'BEGINNER',
  'easy': 'BASIC',
  'medium': 'DIFFICULT',
  'hard': 'EXPERT',
  'challenge': 'CHALLENGE',
};

// DDR UI colors for the in-game difficulty names (same palette as
// SongDifficultyPicker uses for the level toggle).
const Map<String, Color> kInGameDifficultyColors = {
  'BEGINNER': Colors.cyan,
  'BASIC': Colors.orange,
  'DIFFICULT': Colors.red,
  'EXPERT': Colors.green,
  'CHALLENGE': Colors.purple,
};

// The charts that exist in [levels], as (in-game name, level) pairs in
// beginner..challenge order.
List<(String, int)> difficultyOptions(Difficulty levels) => [
      for (final e in levels.toJson().entries)
        if (e.value != null) (kInGameDifficultyNames[e.key]!, e.value as int),
    ];

// Resolves a noisy OCR difficulty reading (e.g. "ert 16", "XPERT", "16")
// to the in-game name of a chart that actually exists in [levels], or null
// when nothing matches confidently (caller keeps the raw reading).
//
// [totalNotes] is the played step count summed from the judgment fields
// (marvelous + perfect + great + good + miss); each chart's step count in
// [notecounts] should equal it, so a chart within [noteTolerance] of it is
// evidence too — used to break level ties and as the last-resort fallback
// when the reading itself is unusable.
//
// Evidence, strongest first:
// 1. A near-exact name match wins outright — OCR misreads the small level
//    digits more often than a whole word.
// 2. Otherwise a level number matching exactly one chart identifies it.
// 3. A level shared by several charts is tie-broken by name similarity,
//    then by the note count.
// 4. With no usable level, the name alone must clear a similarity threshold.
// 5. Failing all that, a note count matching exactly one chart identifies it.
String? resolveOcrDifficulty(
  String raw,
  Difficulty levels, {
  Difficulty? notecounts,
  int? totalNotes,
  int noteTolerance = 5,
}) {
  final letters = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  final level = int.tryParse(RegExp(r'\d+').firstMatch(raw)?.group(0) ?? '');

  final candidates = difficultyOptions(levels);
  if (candidates.isEmpty) return null;

  // Chart step counts by in-game name (difficultyOptions pairs each name
  // with its value, which for [notecounts] is the step count).
  final countFor = <String, int>{
    if (notecounts != null)
      for (final o in difficultyOptions(notecounts)) o.$1: o.$2,
  };
  List<(String, int)> nearNoteCount(Iterable<(String, int)> from) => [
        for (final c in from)
          if (totalNotes != null &&
              countFor[c.$1] != null &&
              (countFor[c.$1]! - totalNotes).abs() <= noteTolerance)
            c
      ];

  double nameSim(String name) {
    if (letters.isEmpty) return 0;
    final target = name.toLowerCase();
    final maxLen = max(letters.length, target.length);
    var sim = 1 - levenshtein(letters, target) / maxLen;
    // OCR often crops leading/trailing characters, so containment ("ert" in
    // "expert") is stronger evidence than raw edit distance suggests.
    if (letters.length >= 3 && target.contains(letters)) {
      sim = max(sim, letters.length / target.length);
    }
    return sim;
  }

  (String, int)? best;
  var bestSim = 0.0;
  for (final c in candidates) {
    final sim = nameSim(c.$1);
    if (sim > bestSim) {
      bestSim = sim;
      best = c;
    }
  }

  if (bestSim >= 0.8) return best!.$1;

  final atLevel = [
    for (final c in candidates)
      if (c.$2 == level) c
  ];
  if (atLevel.length == 1) return atLevel.single.$1;
  if (atLevel.length > 1) {
    // Several charts share this level; the name breaks the tie, then the
    // note count.
    (String, int)? tie;
    var tieSim = 0.0;
    for (final c in atLevel) {
      final sim = nameSim(c.$1);
      if (sim > tieSim) {
        tieSim = sim;
        tie = c;
      }
    }
    if (tie != null) return tie.$1;
    final byNotes = nearNoteCount(atLevel);
    return byNotes.length == 1 ? byNotes.single.$1 : null;
  }

  if (bestSim >= 0.5) return best!.$1;

  // Last resort: the played step count singles out one chart.
  final byNotes = nearNoteCount(candidates);
  return byNotes.length == 1 ? byNotes.single.$1 : null;
}

// Canonical flare ranks in ascending order, as shown on the DDR World
// results screen: FLARE I..IX, then FLARE EX.
const List<String> kFlareRanks = [
  'I',
  'II',
  'III',
  'IV',
  'V',
  'VI',
  'VII',
  'VIII',
  'IX',
  'EX',
];

// Resolves a noisy OCR flare reading ("FLARE 1X", "vii", "4", "ex") to its
// canonical rank in [kFlareRanks], or null when it's blank, NONE, or
// unreadable.
//
// Closed-vocabulary correction: the reading is scored against each rank's
// on-screen forms (the rank alone and its full "FLARE <rank>" label) with an
// edit distance that counts glyphs OCR confuses in this font as equal
// (1/l→I, U/Y→V, K→X). The unique nearest rank within one edit wins —
// misreads inside the label ("FIARE IX") cost nothing extra because the
// label is a candidate form, not a prefix to strip. A tie (e.g. "X", one
// edit from both IX and EX) stays unresolved rather than guessing.
String? resolveOcrFlare(String raw) {
  final f = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (f.isEmpty || f == 'NONE' || f == '0') return null;
  // A purely numeric reading is a typed level, not a misread numeral —
  // resolve it exactly or not at all.
  final level = int.tryParse(f);
  if (level != null) {
    return level >= 1 && level <= 9 ? kFlareRanks[level - 1] : null;
  }
  String glyphClasses(String s) => s
      .replaceAll(RegExp(r'[1L]'), 'I')
      .replaceAll(RegExp(r'[UY]'), 'V')
      .replaceAll('K', 'X');
  final reading = glyphClasses(f);
  String? best;
  var bestDist = 2;
  var ambiguous = false;
  for (final rank in kFlareRanks) {
    final d = min(
      levenshtein(reading, glyphClasses(rank)),
      levenshtein(reading, glyphClasses('FLARE$rank')),
    );
    if (d < bestDist) {
      bestDist = d;
      best = rank;
      ambiguous = false;
    } else if (d == bestDist) {
      ambiguous = true;
    }
  }
  return ambiguous ? null : best;
}

// Position of a version in the DDR release order; unknown versions sort last.
int versionIndex(String version) {
  final index = constants.versionOrder.indexOf(version);
  return index == -1 ? constants.versionOrder.length : index;
}

// Sort on the translit title so Japanese titles order alphabetically too.
String _titleKey(SongInfo song) =>
    (song.titletranslit.isNotEmpty ? song.titletranslit : song.title)
        .toLowerCase();

// Comparator for song lists under the given sort. Callers should skip
// sorting entirely for SortType.level: List.sort isn't stable, so a
// zero-comparator would still shuffle the original order.
int compareSongInfo(SongInfo a, SongInfo b, SortType sortType) {
  switch (sortType) {
    case SortType.level:
      return 0;
    case SortType.title:
      return _titleKey(a).compareTo(_titleKey(b));
    case SortType.version:
      int byVersion =
          versionIndex(a.version).compareTo(versionIndex(b.version));
      return byVersion != 0 ? byVersion : _titleKey(a).compareTo(_titleKey(b));
  }
}

// Helper function to show snackbar toast
void showToast(BuildContext context, String message) {
  final scaffold = ScaffoldMessenger.of(context);
  scaffold.showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(
          label: 'DISMISS', onPressed: scaffold.hideCurrentSnackBar),
    ),
  );
}

// Helper function to format date
String formatDate(DateTime date) {
  return "${date.year}-${date.month}-${date.day} (${date.hour}:${date.minute.toString().length == 1 ? "0${date.minute}" : date.minute})";
}

// Date-only rendering (no time) for play dates the user sets at day
// granularity. Zero-pads month and day: 2026-07-08.
String formatPlayDate(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return "${date.year}-$m-$d";
}

// Helper function to format a score with thousands separators
String formatScore(int score) {
  return score
      .toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}

// Accent color for a DDR judgment key. Returns null for unrecognised keys so
// callers fall back to the theme's default text color (safe in dark mode).
Color? judgmentColor(String key, {BuildContext? context}) {
  final isDark = context != null
      ? Theme.of(context).brightness == Brightness.dark
      : WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;

  switch (key.toLowerCase()) {
    case 'marvelous':
      // A near-white cyan in dark mode, and a deep cyan in light mode.
      return isDark ? const Color(0xFFB6FFF7) : const Color(0xFF006F67);
    case 'perfect':
      return Colors.yellow[700]!;
    case 'great':
      return Colors.green;
    case 'good':
      return Colors.blueAccent;
    case 'bad':
      return Colors.purpleAccent;
    default:
      return null;
  }
}
