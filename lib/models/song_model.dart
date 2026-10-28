/// Name: SongState -- ChangeNotifier
/// Description: Model for state relating to the selected song, plus the
/// master song list ([Songs]) loaded from the bundled songs assets.
library;

import 'dart:convert';
import 'dart:math';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/cloud_sync.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SongState extends ChangeNotifier {
  SongState() {
    CloudSync.pulled.addListener(_reloadSettings);
  }

  // Play style and sort, as another device may have just synced them.
  void _reloadSettings() {
    _mode = Settings.getInt(Settings.playModeKey) == Modes.doubles.index
        ? Modes.doubles
        : Modes.singles;
    final sort = Settings.getInt(Settings.songlistSortKey);
    _sortType = sort == 0 ? SortType.version : SortType.values[sort - 1];
    _sortDescending = Settings.getInt(Settings.songlistSortDescKey) == 1;
    notifyListeners();
  }

  SongInfo? _songInfo;
  SongInfo? get songInfo => _songInfo;

  // Persisted play style, chosen on the settings page.
  Modes _mode = Settings.getInt(Settings.playModeKey) == Modes.doubles.index
      ? Modes.doubles
      : Modes.singles;
  Modes get modes => _mode;

  // Stored as index+1 so an unset 0 falls back to the cabinet's release order.
  SortType _sortType = Settings.getInt(Settings.songlistSortKey) == 0
      ? SortType.version
      : SortType.values[Settings.getInt(Settings.songlistSortKey) - 1];
  SortType get sortType => _sortType;

  bool _sortDescending = Settings.getInt(Settings.songlistSortDescKey) == 1;
  bool get sortDescending => _sortDescending;

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
    Settings.setInt(Settings.songlistSortKey, newSortType.index + 1);
    notifyListeners();
  }

  void setSortDescending(bool descending) {
    _sortDescending = descending;
    Settings.setInt(Settings.songlistSortDescKey, descending ? 1 : 0);
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

/// Master song list, loaded once at startup from the songlist.
class Songs {
  static List<String> assets = [];
  static List<SongInfo> list = [];

  // Load song list JSONs from the asset bundle into the static list.
  // `cache: false` throughout: rootBundle otherwise pins every decoded JSON
  // string in its cache for the app's lifetime, doubling what the parsed
  // SongInfo list already holds.
  static Future<void> load() async {
    // Built aside and swapped in whole, so a reload (an applied update) never
    // shows a half-filled list.
    final loaded = <SongInfo>[];
    // Prefer the merged songlist (scripts/generate_songlist.sh): one read
    // instead of ~1100 sequential ones. A downloaded one replaces the bundled
    // one whole (ContentStore), so new songs arrive without a store release.
    String? response;
    try {
      response = await ContentStore.loadString("assets/songlist.json");
    } catch (_) {}
    if (response != null) {
      // ~2.7 MB of JSON: parsed off the UI isolate so launch and an applied
      // update don't drop frames.
      list = await compute(_parseSonglist, response);
      _searchKeys; // built now so the first keystroke doesn't pay for it
      return;
    }

    AssetManifest asset = await AssetManifest.loadFromAssetBundle(rootBundle);
    assets = asset.listAssets();
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
        loaded.add(songInfo);
      } catch (e) {
        // ignore: avoid_print
        print("Error parsing JSON for ${songDataPaths[i]}: $e");
        continue;
      }
    }
    list = loaded;
    _searchKeys;
  }

  // Each song's normalized title, translit title and name (deduped, empties
  // dropped), parallel to [list]. Rebuilt whenever [list] is swapped, so a
  // keystroke never re-runs the normalizing regex over the whole catalogue.
  static List<SongInfo>? _keyedList;
  static List<List<String>> _keys = const [];

  static List<List<String>> get _searchKeys {
    if (!identical(_keyedList, list)) {
      _keyedList = list;
      _keys = [
        for (final song in list)
          {
            _normalize(song.title),
            _normalize(song.titletranslit),
            _normalize(song.name),
          }.where((k) => k.isNotEmpty).toList(growable: false),
      ];
    }
    return _keys;
  }

  // Lowercase and strip everything but letters/digits (any script) so OCR
  // punctuation/spacing noise doesn't count against the edit distance.
  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  // Similarity of [query] (already normalized) to a song's [keys]: the best
  // score across them. An exact substring hit (e.g. typing a prefix of a long
  // title) always wins, so short partial queries aren't drowned out by
  // whole-string edit distance; otherwise falls back to normalized Levenshtein
  // so typos still rank sensibly. Keys that can't reach [floor] (or beat the
  // best so far) are skipped, cut off by length gap or mid-way through the
  // distance; a song with no key reaching [floor] may score anywhere below it.
  static double _similarity(String query, List<String> keys, double floor) {
    double best = 0;
    for (final key in keys) {
      double similarity;
      if (key.contains(query)) {
        // Floor of 0.5 so a short substring match (e.g. a prefix of a long
        // title) still ranks as a strong hit, not a weak one.
        similarity = 0.5 + 0.5 * (query.length / key.length);
      } else {
        final maxLen = max(query.length, key.length);
        final maxDist = ((1 - max(best, floor)) * maxLen + 1e-9).floor();
        if ((query.length - key.length).abs() > maxDist) continue;
        final distance = query.length <= 64
            ? _myersWithin(query.length, key, maxDist)
            : _levenshteinWithin(query, key, maxDist);
        if (distance > maxDist) continue;
        similarity = 1 - distance / maxLen;
      }
      if (similarity > best) best = similarity;
    }
    return best;
  }

  static Int32List _prevRow = Int32List(128), _currRow = Int32List(128);

  // Levenshtein distance of [a] to [b], or anything above [maxDist] once no
  // alignment can come back under it. Rows are reused across calls.
  static int _levenshteinWithin(String a, String b, int maxDist) {
    final n = b.length;
    if (_prevRow.length <= n) {
      _prevRow = Int32List(n + 1);
      _currRow = Int32List(n + 1);
    }
    var prev = _prevRow, curr = _currRow;
    for (var j = 0; j <= n; j++) {
      prev[j] = j;
    }
    for (var i = 0; i < a.length; i++) {
      final ca = a.codeUnitAt(i);
      var rowMin = curr[0] = i + 1;
      for (var j = 0; j < n; j++) {
        var v = prev[j] + (ca == b.codeUnitAt(j) ? 0 : 1);
        if (curr[j] + 1 < v) v = curr[j] + 1;
        if (prev[j + 1] + 1 < v) v = prev[j + 1] + 1;
        curr[j + 1] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > maxDist) return maxDist + 1;
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }

  // Per query character, the bitmask of positions it holds in the query, for
  // [_myersWithin]. ASCII in a table, the rest (kana, kanji) in a map.
  static final Int64List _peqAscii = Int64List(128);
  static final Map<int, int> _peqOther = {};

  static void _setPeq(String query) {
    _peqAscii.fillRange(0, 128, 0);
    _peqOther.clear();
    for (var i = 0; i < query.length; i++) {
      final c = query.codeUnitAt(i);
      if (c < 128) {
        _peqAscii[c] |= 1 << i;
      } else {
        _peqOther[c] = (_peqOther[c] ?? 0) | 1 << i;
      }
    }
  }

  // The same distance as [_levenshteinWithin] for a query of [m] <= 64 code
  // units (its masks set by [_setPeq]), a whole DP column per word op
  // (Myers/Hyyrö bit-parallel).
  static int _myersWithin(int m, String key, int maxDist) {
    final high = 1 << (m - 1);
    final n = key.length;
    var pv = -1, mv = 0, score = m;
    for (var j = 0; j < n; j++) {
      final c = key.codeUnitAt(j);
      final eq = c < 128 ? _peqAscii[c] : (_peqOther[c] ?? 0);
      final xv = eq | mv;
      final xh = (((eq & pv) + pv) ^ pv) | eq;
      var ph = mv | ~(xh | pv);
      var mh = pv & xh;
      if (ph & high != 0) {
        score++;
      } else if (mh & high != 0) {
        score--;
      }
      ph = (ph << 1) | 1;
      mh <<= 1;
      pv = mh | ~(xv | ph);
      mv = ph & xv;
      // Each remaining key character can lower the distance by at most one.
      if (score - (n - 1 - j) > maxDist) return maxDist + 1;
    }
    return score;
  }

  // Finds the song whose title (or translit title) is closest to [ocrTitle]
  // by normalized Levenshtein distance. Returns null when the list is empty
  // or the query normalizes to nothing.
  static SongMatch? matchTitle(String ocrTitle) =>
      matchTitles(ocrTitle, limit: 1).firstOrNull;

  // The [limit] closest songs to [ocrTitle] scoring at least [minSimilarity],
  // best first. Empty when the list is empty or the query normalizes to
  // nothing.
  static List<SongMatch> matchTitles(String ocrTitle,
      {int limit = 10, double minSimilarity = 0}) {
    final query = _normalize(ocrTitle);
    if (query.isEmpty || list.isEmpty) return const [];
    final keys = _searchKeys;
    if (query.length <= 64) _setPeq(query);
    final matches = <SongMatch>[];
    for (var i = 0; i < list.length; i++) {
      final similarity = _similarity(query, keys[i], minSimilarity);
      if (similarity >= minSimilarity) {
        matches.add(SongMatch(list[i], similarity));
      }
    }
    matches.sort((a, b) => b.similarity.compareTo(a.similarity));
    return matches.take(limit).toList();
  }
}

List<SongInfo> _parseSonglist(String response) {
  final loaded = <SongInfo>[];
  for (final entry in json.decode(response) as List<dynamic>) {
    try {
      loaded.add(SongInfo.fromJson(entry));
    } catch (e) {
      // ignore: avoid_print
      print("Error parsing songlist entry: $e");
    }
  }
  return loaded;
}
