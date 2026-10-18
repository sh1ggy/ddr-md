/// Name: score_overview.dart
/// Description: The player's synced bests summed up for the profile's score
/// overview: clear lamps per level, DDR WORLD flare skill and plays per day.
library;

import 'dart:math';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyNames;
import 'package:ddr_md/models/db_models.dart';

/// The chart's level, or null when [song] has no such chart.
int? chartLevel(SongInfo song, Modes mode, String difficulty) {
  final levels = (mode == Modes.singles ? song.singles : song.doubles).toJson();
  for (final e in kInGameDifficultyNames.entries) {
    if (e.value == difficulty) return levels[e.key] as int?;
  }
  return null;
}

/// One level of the clear table: how many charts it has, and the player's
/// synced bests on them.
typedef LevelCharts = ({int charts, List<ScoreRecord> played});

/// [mode]'s charts by level, over every chart in [songs]. Records whose song
/// matched nothing are left out, having no level.
Map<int, LevelCharts> chartsByLevel(
    List<ScoreRecord> records, List<SongInfo> songs, Modes mode) {
  final byName = {for (final s in songs) s.name: s};
  final charts = <int, int>{};
  for (final s in songs) {
    final levels = mode == Modes.singles ? s.singles : s.doubles;
    for (final level in levels.toJson().values) {
      if (level is int) charts[level] = (charts[level] ?? 0) + 1;
    }
  }
  final played = <int, List<ScoreRecord>>{};
  for (final r in records) {
    final song = byName[r.song];
    if (r.mode != mode || song == null) continue;
    final level = chartLevel(song, mode, r.difficulty);
    if (level != null) played.putIfAbsent(level, () => []).add(r);
  }
  return {
    for (final level in charts.keys.toList()..sort())
      level: (charts: charts[level]!, played: played[level] ?? const []),
  };
}

/// Mean and population standard deviation of [values], or null when empty.
({double mean, double sd})? meanAndSd(List<int> values) {
  if (values.isEmpty) return null;
  final mean = values.fold(0, (a, b) => a + b) / values.length;
  final variance =
      values.fold(0.0, (a, v) => a + (v - mean) * (v - mean)) / values.length;
  return (mean: mean, sd: sqrt(variance));
}

/// DDR WORLD's flare skill groups, by the version a song first appeared in.
enum FlareGroup { classic, white, gold }

FlareGroup? flareGroup(String version) => switch (version) {
      '1st' ||
      '2nd' ||
      '3rd' ||
      '4th' ||
      '5th' ||
      'MAX' ||
      'MAX2' ||
      'EXTREME' ||
      'SuperNOVA' ||
      'SuperNOVA2' ||
      'X' ||
      'X2' ||
      'X3' =>
        FlareGroup.classic,
      '2013' || '2014' || 'A' || 'A20' => FlareGroup.white,
      'A20 PLUS' || 'A3' || 'WORLD' => FlareGroup.gold,
      _ => null,
    };

/// How many charts of each group count towards the total.
const kFlareChartsPerGroup = 30;

/// A style's flare skill: each group's best [kFlareChartsPerGroup] charts,
/// best first, and their sum.
class FlareSkill {
  FlareSkill(this.groups);

  final Map<FlareGroup, List<ScoreRecord>> groups;

  int groupTotal(FlareGroup g) =>
      groups[g]!.fold(0, (sum, r) => sum + (r.flareSkill ?? 0));

  int get total => FlareGroup.values.fold(0, (sum, g) => sum + groupTotal(g));
}

FlareSkill flareSkill(
    List<ScoreRecord> records, List<SongInfo> songs, Modes mode) {
  final versions = {for (final s in songs) s.name: s.version};
  final groups = {for (final g in FlareGroup.values) g: <ScoreRecord>[]};
  for (final r in records) {
    final group = flareGroup(versions[r.song] ?? '');
    if (r.mode != mode || group == null || (r.flareSkill ?? 0) <= 0) continue;
    groups[group]!.add(r);
  }
  for (final list in groups.values) {
    list.sort((a, b) => b.flareSkill!.compareTo(a.flareSkill!));
    if (list.length > kFlareChartsPerGroup) {
      list.removeRange(kFlareChartsPerGroup, list.length);
    }
  }
  return FlareSkill(groups);
}

/// The flare skill class a total reaches, with the total the next one
/// starts at (null at WORLD, the top).
({String name, int? next}) flareClass(int total) {
  const steps = [
    (0, 'NONE'), (500, 'NONE+'), (1000, 'NONE++'), (1500, 'NONE+++'), //
    (2000, 'MERCURY'), (3000, 'MERCURY+'), (4000, 'MERCURY++'),
    (5000, 'MERCURY+++'), (6000, 'VENUS'), (7000, 'VENUS+'),
    (8000, 'VENUS++'), (9000, 'VENUS+++'), (10000, 'EARTH'),
    (11500, 'EARTH+'), (13000, 'EARTH++'), (14500, 'EARTH+++'),
    (16000, 'MARS'), (18000, 'MARS+'), (20000, 'MARS++'), (22000, 'MARS+++'),
    (24000, 'JUPITER'), (26500, 'JUPITER+'), (29000, 'JUPITER++'),
    (31500, 'JUPITER+++'), (34000, 'SATURN'), (36750, 'SATURN+'),
    (39500, 'SATURN++'), (42250, 'SATURN+++'), (45000, 'URANUS'),
    (48750, 'URANUS+'), (52500, 'URANUS++'), (56250, 'URANUS+++'),
    (60000, 'NEPTUNE'), (63750, 'NEPTUNE+'), (67500, 'NEPTUNE++'),
    (71250, 'NEPTUNE+++'), (75000, 'SUN'), (78750, 'SUN+'), (82500, 'SUN++'),
    (86250, 'SUN+++'), (90000, 'WORLD'),
  ];
  for (var i = steps.length - 1; i >= 0; i--) {
    if (total >= steps[i].$1) {
      return (
        name: steps[i].$2,
        next: i + 1 < steps.length ? steps[i + 1].$1 : null
      );
    }
  }
  return (name: 'NONE', next: 500);
}

/// Plays per local calendar day, keyed by midnight: every kept recent play,
/// plus each chart's last play from [records] that isn't one of them, which
/// reaches back past the recent plays history.
Map<DateTime, int> playsPerDay(
    Iterable<RecentPlay> plays, Iterable<ScoreRecord> records) {
  final seen = {for (final p in plays) (p.recordId, p.playedAt)};
  final days = <DateTime, int>{};
  void add(DateTime t) {
    t = t.toLocal();
    final day = DateTime(t.year, t.month, t.day);
    days[day] = (days[day] ?? 0) + 1;
  }

  plays.map((p) => p.playedAt).forEach(add);
  for (final r in records) {
    if (r.playedAt != null && !seen.contains((r.id, r.playedAt))) {
      add(r.playedAt!);
    }
  }
  return days;
}
