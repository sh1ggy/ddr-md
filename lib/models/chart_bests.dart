/// Name: ChartBests
/// Parent: DifficultyListPage
/// Description: The player's best score, grade, clear lamp and flare on every chart
/// of one mode, from synced records and saved scores, so song list rows can
/// show them without a query each. Each is bested separately, as the cabinet
/// keeps them. Only synced records carry a lamp.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart'
    show kFlareRanks, kInGameDifficultyNames, resolveOcrFlare;
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart' show ClearLamp;
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';

typedef ChartBest = ({
  int? score,
  Grade? grade,
  ClearLamp? lamp,
  String? flare
});

class ChartBests {
  /// Whether the song list shows bests at all; off, chart rows are plain rows.
  static bool get shown => Settings.getInt(Settings.songlistHideStatsKey) == 0;

  static Modes? _mode;
  // Song name → in-game difficulty → best.
  static Map<String, Map<String, ChartBest>> _bests = {};

  /// The best on the chart at [index] into [mode]'s availableTypes; null when
  /// it hasn't been played or another mode is loaded.
  static ChartBest? at(SongInfo song, Modes mode, int index) {
    final types =
        (mode == Modes.singles ? song.singles : song.doubles).availableTypes;
    if (mode != _mode || types.isEmpty) return null;
    return _bests[song.name]
        ?[kInGameDifficultyNames[types[index.clamp(0, types.length - 1)]]];
  }

  /// [load]s unless [mode] is already loaded, so refiltering the list skips
  /// the database.
  static Future<void> ensure(Modes mode) async {
    if (mode != _mode) await load(mode);
  }

  static Future<void> load(Modes mode) async {
    final (records, scores) = await (
      DatabaseProvider.getScoreRecordsByMode(mode),
      DatabaseProvider.getAllScores(),
    ).wait;
    // Scores key on the transliterated title, records on the song name.
    final names = {for (final s in Songs.list) s.titletranslit: s.name};
    final bests = <String, Map<String, ChartBest>>{};
    void add(String? song, String difficulty, int? score, Grade? grade,
        ClearLamp? lamp, String? flare) {
      if (song == null) return;
      final charts = bests.putIfAbsent(song, () => {});
      final old = charts[difficulty];
      final oldScore = old?.score,
          oldGrade = old?.grade,
          oldLamp = old?.lamp,
          oldFlare = old?.flare;
      charts[difficulty] = (
        score: oldScore == null || (score != null && score > oldScore)
            ? score ?? oldScore
            : oldScore,
        // Grades run best first; lamps and flare ranks worst first.
        grade:
            oldGrade == null || (grade != null && grade.index < oldGrade.index)
                ? grade ?? oldGrade
                : oldGrade,
        lamp: oldLamp == null || (lamp != null && lamp.index > oldLamp.index)
            ? lamp ?? oldLamp
            : oldLamp,
        flare: oldFlare == null ||
                (flare != null &&
                    kFlareRanks.indexOf(flare) > kFlareRanks.indexOf(oldFlare))
            ? flare ?? oldFlare
            : oldFlare,
      );
    }

    for (final r in records) {
      add(
          r.song,
          r.difficulty,
          r.score,
          Grade.values.where((g) => g.label == r.rank).firstOrNull,
          r.clearLamp,
          r.flareRank.isEmpty ? null : r.flareRank);
    }
    for (final s in scores) {
      if (s.mode != mode) continue;
      add(
          names[s.songTitle],
          s.difficulty,
          s.score,
          s.score == null ? null : gradeForScore(s.score!),
          null,
          resolveOcrFlare(s.flare));
    }
    _mode = mode;
    _bests = bests;
  }
}
