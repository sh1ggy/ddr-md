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
    show kInGameDifficultyNames, resolveOcrFlare;
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/chart_achievements.dart';
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

  static final _cache = <Modes,
      ({
    int revision,
    Map<String, Map<String, ChartBest>> bests,
    Map<String, Map<String, PrecisionEvidence>> precision,
    Set<(String, String)> levelTops
  })>{};
  static final _loads = <Modes, Future<void>>{};

  static PrecisionEvidence? precisionAt(
          String song, Modes mode, String difficulty) =>
      _cache[mode]?.precision[song]?[difficulty];

  /// Whether this chart holds the player's highest score of its level, out
  /// of at least [levelTopMinCharts] scored charts there. Ties all hold it.
  static bool levelTop(String song, Modes mode, String difficulty) =>
      _cache[mode]?.levelTops.contains((song, difficulty)) ?? false;

  static const levelTopMinCharts = 3;

  static ChartBest? forChart(String song, Modes mode, String difficulty) =>
      _cache[mode]?.bests[song]?[difficulty];

  /// Every chart's best in [mode] as loaded, by song then difficulty. A load
  /// makes a new map, so this one stays as it was.
  static Map<String, Map<String, ChartBest>> bestsOf(Modes mode) =>
      _cache[mode]?.bests ?? const {};

  /// The best on the chart at [index] into [mode]'s availableTypes; null when
  /// it hasn't been played or another mode is loaded.
  static ChartBest? at(SongInfo song, Modes mode, int index) {
    final types =
        (mode == Modes.singles ? song.singles : song.doubles).availableTypes;
    if (types.isEmpty) return null;
    return _cache[mode]?.bests[song.name]
        ?[kInGameDifficultyNames[types[index.clamp(0, types.length - 1)]]];
  }

  /// [load]s unless [mode] is already loaded, so refiltering the list skips
  /// the database.
  static Future<void> ensure(Modes mode) async {
    while (
        _cache[mode]?.revision != DatabaseProvider.achievementsRevision.value) {
      await load(mode);
    }
  }

  static Future<void> load(Modes mode) async {
    do {
      await (_loads[mode] ??= _load(mode).whenComplete(() {
        _loads.remove(mode);
      }));
    } while (
        _cache[mode]?.revision != DatabaseProvider.achievementsRevision.value);
  }

  static Future<void> _load(Modes mode) async {
    final revision = DatabaseProvider.achievementsRevision.value;
    final (records, scores) = await (
      DatabaseProvider.getScoreRecordsByMode(mode),
      DatabaseProvider.getAllScores(),
    ).wait;
    // Scores key on the transliterated title, records on the song name.
    final names = {
      for (final s in Songs.list)
        (s.titletranslit.isEmpty ? s.title : s.titletranslit): s.name
    };
    final bests = <String, Map<String, ChartBest>>{};
    void add(String? song, String difficulty, int? score, Grade? grade,
        ClearLamp? lamp, String? flare) {
      if (song == null) return;
      final charts = bests.putIfAbsent(song, () => {});
      charts[difficulty] = mergeBest(charts[difficulty],
          (score: score, grade: grade, lamp: lamp, flare: flare));
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
    // Use a local map so concurrent loads never mix evidence between modes.
    final precision = <String, Map<String, PrecisionEvidence>>{};
    for (final s in scores) {
      final name = names[s.songTitle];
      if (s.mode != mode || name == null) continue;
      final evidence = precisionForPlay(s);
      if (evidence == null) continue;
      final charts = precision.putIfAbsent(name, () => {});
      final old = charts[s.difficulty];
      if (old == null ||
          evidence.award.index > old.award.index ||
          (evidence.award == old.award &&
              evidence.sourceRowId.compareTo(old.sourceRowId) < 0)) {
        charts[s.difficulty] = evidence;
      }
    }
    final levels =
        <int, ({int score, int charts, List<(String, String)> tops})>{};
    for (final song in Songs.list) {
      final charts = bests[song.name];
      if (charts == null) continue;
      final json =
          (mode == Modes.singles ? song.singles : song.doubles).toJson();
      for (final MapEntry(:key, :value) in kInGameDifficultyNames.entries) {
        final level = json[key], score = charts[value]?.score;
        if (level is! int || score == null) continue;
        final old = levels[level];
        levels[level] = old == null || score > old.score
            ? (
                score: score,
                charts: (old?.charts ?? 0) + 1,
                tops: [(song.name, value)]
              )
            : (
                score: old.score,
                charts: old.charts + 1,
                tops: score == old.score
                    ? [...old.tops, (song.name, value)]
                    : old.tops
              );
      }
    }
    _cache[mode] = (
      revision: revision,
      bests: bests,
      precision: precision,
      levelTops: {
        for (final l in levels.values)
          if (l.charts >= levelTopMinCharts) ...l.tops
      }
    );
  }
}
