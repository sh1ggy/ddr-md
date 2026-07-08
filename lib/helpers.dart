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
      int byVersion = versionIndex(a.version).compareTo(versionIndex(b.version));
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
