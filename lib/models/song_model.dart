/// Name: SongState -- ChangeNotifier
/// Description: Model for state relating to the selected song, plus the
/// master song list ([Songs]) loaded from the bundled songs assets.
library;

import 'dart:convert';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SongState extends ChangeNotifier {
  SongInfo? _songInfo;
  SongInfo? get songInfo => _songInfo;

  // Persisted play style, chosen on the settings page.
  Modes _mode = Settings.getInt(Settings.playModeKey) == Modes.doubles.index
      ? Modes.doubles
      : Modes.singles;
  Modes get modes => _mode;

  SortType _sortType = SortType.level;
  SortType get sortType => _sortType;

  int _chosenDifficulty = 0;
  int get chosenDifficulty => _chosenDifficulty;

  List<Note>? _notesPromise;
  List<Note>? get notesPromise => _notesPromise;

  void setSongInfo(SongInfo selectedSongInfo) {
    _songInfo = selectedSongInfo;
    notifyListeners();
  }

  void setMode(Modes newMode) {
    _mode = newMode;
    Settings.setInt(Settings.playModeKey, newMode.index);
    notifyListeners();
  }

  void setSortType(SortType newSortType) {
    _sortType = newSortType;
    notifyListeners();
  }

  void setNotePromise(List<Note>? newNotesPromise) {
    _notesPromise = newNotesPromise;
    notifyListeners();
  }

  void setChosenDifficulty(int difficulty) {
    _chosenDifficulty = difficulty;
    notifyListeners();
  }
}

// A fuzzy title match against the master song list: the closest song and its
// similarity (1.0 = exact, 0.0 = nothing in common).
class SongMatch {
  final SongInfo song;
  final double similarity;
  const SongMatch(this.song, this.similarity);
}

/// Master song list, loaded once at startup from assets/songs/*.json.
class Songs {
  static List<String> assets = [];
  static List<SongInfo> list = [];

  // Load song list JSONs from the asset bundle into the static list.
  // `cache: false` throughout: rootBundle otherwise pins every decoded JSON
  // string in its cache for the app's lifetime, doubling what the parsed
  // SongInfo list already holds.
  static Future<void> load() async {
    AssetManifest asset = await AssetManifest.loadFromAssetBundle(rootBundle);
    assets = asset.listAssets();

    // Prefer the merged songlist (scripts/generate_songlist.sh): one asset
    // read instead of ~1100 sequential ones. Bundled by lite builds, or by
    // any build made after generating it.
    if (assets.contains("assets/songlist.json")) {
      var response =
          await rootBundle.loadString("assets/songlist.json", cache: false);
      for (final entry in json.decode(response) as List<dynamic>) {
        try {
          list.add(SongInfo.fromJson(entry));
        } catch (e) {
          // ignore: avoid_print
          print("Error parsing songlist entry: $e");
        }
      }
      return;
    }

    List<String> songDataPaths = assets
      .where((string) => string.startsWith("assets/songs/"))
        .where((string) => string.endsWith(".json"))
        .map((e) => e.substring(0, e.length - 5))
        .toList();

    for (int i = 0; i < songDataPaths.length; i++) {
      var response =
          await rootBundle.loadString('${songDataPaths[i]}.json', cache: false);
      SongInfo songInfo;
      try {
        songInfo = parseJson(response);
        list.add(songInfo);
      } catch (e) {
        // ignore: avoid_print
        print("Error parsing JSON for ${songDataPaths[i]}: $e");
        continue;
      }
    }
  }

  // Lowercase and strip everything but letters/digits (any script) so OCR
  // punctuation/spacing noise doesn't count against the edit distance.
  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  // Similarity of [query] (already normalized) to a song: the best score
  // across its title, translit title, and name. An exact substring hit (e.g.
  // typing a prefix of a long title) always wins, so short partial queries
  // aren't drowned out by whole-string edit distance; otherwise falls back to
  // normalized Levenshtein so typos still rank sensibly.
  static double _similarity(String query, SongInfo song) {
    double best = 0;
    for (final candidate in [song.title, song.titletranslit, song.name]) {
      final normalized = _normalize(candidate);
      if (normalized.isEmpty) continue;
      double similarity;
      if (normalized.contains(query)) {
        // Floor of 0.5 so a short substring match (e.g. a prefix of a long
        // title) still ranks as a strong hit, not a weak one.
        similarity = 0.5 + 0.5 * (query.length / normalized.length);
      } else {
        final maxLen = query.length > normalized.length
            ? query.length
            : normalized.length;
        similarity = 1 - levenshtein(query, normalized) / maxLen;
      }
      if (similarity > best) best = similarity;
    }
    return best;
  }

  // Finds the song whose title (or translit title) is closest to [ocrTitle]
  // by normalized Levenshtein distance. Returns null when the list is empty
  // or the query normalizes to nothing.
  static SongMatch? matchTitle(String ocrTitle) =>
      matchTitles(ocrTitle, limit: 1).firstOrNull;

  // The [limit] closest songs to [ocrTitle], best first. Empty when the list
  // is empty or the query normalizes to nothing.
  static List<SongMatch> matchTitles(String ocrTitle, {int limit = 10}) {
    final query = _normalize(ocrTitle);
    if (query.isEmpty || list.isEmpty) return const [];
    final matches = [
      for (final song in list) SongMatch(song, _similarity(query, song)),
    ]..sort((a, b) => b.similarity.compareTo(a.similarity));
    return matches.take(limit).toList();
  }
}
