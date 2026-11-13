/// Name: SongJson
/// Description: JSON parsing for song & chart information
/// Reference: https://app.quicktype.io/
library;

import 'dart:convert';

SongInfo parseJson(String str) => SongInfo.fromJson(json.decode(str));
String welcomeToJson(SongInfo data) => json.encode(data.toJson());

class SongInfo {
  bool ssc;
  String version;
  String name;

  /// Konami's own song ID, which synced e-amusement scores are matched on;
  /// empty for a song not linked to one.
  String konamiId;
  String title;
  String titletranslit;
  String artist;
  String artisttranslit;
  double songLength;
  bool perChart;
  Difficulty singles;
  Difficulty doubles;
  Map<String, Radar> radarSingles;
  Map<String, Radar> radarDoubles;
  Difficulty singlesNotecounts;
  Difficulty doublesNotecounts;
  List<Chart> charts;
  Sync? sync;
  Sync? arcadeSync;
  ScoringTiers? scoringTiers;

  /// The song's bar lengths, when it isn't plain 4/4 from beat 0 (empty then).
  List<TimeSignature> timeSignatures;

  /// Charts not playable by default, by difficulty key (beginner..challenge).
  Map<String, ChartUnlock> unlocksSingles;
  Map<String, ChartUnlock> unlocksDoubles;

  SongInfo({
    required this.ssc,
    required this.version,
    required this.name,
    this.konamiId = '',
    required this.title,
    required this.titletranslit,
    required this.artist,
    required this.artisttranslit,
    required this.songLength,
    required this.perChart,
    required this.singles,
    required this.doubles,
    required this.radarSingles,
    required this.radarDoubles,
    required this.singlesNotecounts,
    required this.doublesNotecounts,
    required this.charts,
    this.sync,
    this.arcadeSync,
    this.scoringTiers,
    this.timeSignatures = const [],
    this.unlocksSingles = const {},
    this.unlocksDoubles = const {},
  });

  /// What still locks the chart at [chosenDifficulty] (indexed as in
  /// [radarFor]) on [day], today by default; null once it's playable by
  /// default.
  ChartUnlock? unlockAt(Modes mode, int chosenDifficulty, [DateTime? day]) {
    final available =
        (mode == Modes.singles ? singles : doubles).availableTypes;
    if (available.isEmpty) return null;
    final key = available[chosenDifficulty.clamp(0, available.length - 1)];
    final unlock =
        (mode == Modes.singles ? unlocksSingles : unlocksDoubles)[key];
    return unlock != null && unlock.lockedOn(day ?? DateTime.now())
        ? unlock
        : null;
  }

  /// The first of [mode]'s charts still locked on [day], if any.
  ChartUnlock? anyUnlock(Modes mode, [DateTime? day]) {
    final count =
        (mode == Modes.singles ? singles : doubles).availableTypes.length;
    for (var i = 0; i < count; i++) {
      if (unlockAt(mode, i, day) case final unlock?) return unlock;
    }
    return null;
  }

  /// Simfile sync data for [chart]: per_chart songs carry it on the chart
  /// entry, otherwise the song-level block applies to every chart.
  Sync? syncFor(Chart chart) => chart.sync ?? sync;

  /// Sync to display for [chart]: the cabinet fingerprint ([arcadeSync],
  /// always song-wide) when the arcade data covers this song, else the
  /// simfile fingerprint as a fallback.
  Sync? displaySyncFor(Chart chart) => arcadeSync ?? syncFor(chart);

  /// Timing for [difficultyKey] (beginner..challenge). per_chart songs list
  /// one entry per difficulty name, SP and DP alike, from the lowest name
  /// either style charts.
  Chart chartFor(String difficultyKey) {
    if (!perChart) return charts.first;
    const keys = ['beginner', 'easy', 'medium', 'hard', 'challenge'];
    final first = keys.indexWhere((k) =>
        singles.availableTypes.contains(k) ||
        doubles.availableTypes.contains(k));
    final i = keys.indexOf(difficultyKey) - first;
    return charts[i.clamp(0, charts.length - 1)];
  }

  /// Timing for the chart at [chosenDifficulty], indexed as in [radarFor].
  Chart chartAt(Modes mode, int chosenDifficulty) {
    final available =
        (mode == Modes.singles ? singles : doubles).availableTypes;
    if (available.isEmpty) return charts.first;
    return chartFor(available[chosenDifficulty.clamp(0, available.length - 1)]);
  }

  /// Calculated scoring difficulty for the same available-chart index as the
  /// picker. A rating must belong to this chart's current official folder.
  ScoringTier? scoringTierFor(Modes mode, int chosenDifficulty) {
    final levels = mode == Modes.singles ? singles : doubles;
    final available = levels.availableTypes;
    if (available.isEmpty) return null;
    final key = available[chosenDifficulty.clamp(0, available.length - 1)];
    final entry = (mode == Modes.singles
        ? scoringTiers?.singles
        : scoringTiers?.doubles)?[key];
    return entry?.tier.floor() == levels.toJson()[key] ? entry : null;
  }

  /// Radar for the chart at [chosenDifficulty], which indexes the non-null
  /// difficulties of [mode] in beginner..challenge order (as rendered by
  /// SongDifficultyPicker). Out-of-range indexes clamp to match the picker's
  /// highlight when switching modes drops a difficulty.
  Radar? radarFor(Modes mode, int chosenDifficulty) {
    final radars = mode == Modes.singles ? radarSingles : radarDoubles;
    final available =
        (mode == Modes.singles ? singles : doubles).availableTypes;
    if (available.isEmpty) return null;
    return radars[available[chosenDifficulty.clamp(0, available.length - 1)]];
  }

  factory SongInfo.fromJson(Map<String, dynamic> json) {
    final levels = json["levels"] as Map<String, dynamic>?;
    final radar = json["radar"] as Map<String, dynamic>?;
    final notecounts = json["notecounts"] as Map<String, dynamic>?;

    Map<String, Radar> parseRadars(dynamic radars) =>
        (radars as Map<String, dynamic>? ?? {}).map(
          (diff, values) => MapEntry(diff, Radar.fromJson(values)),
        );

    return SongInfo(
      ssc: json["ssc"] ?? false,
      version: json["version"] ?? "",
      name: json["name"] ?? "",
      konamiId: json["konami_id"] ?? "",
      title: json["title"] ?? "",
      titletranslit: json["titletranslit"] ?? "",
      artist: json["artist"] ?? "",
      artisttranslit: json["artisttranslit"] ?? "",
      songLength: (json["song_length"] ?? 0).toDouble(),
      perChart: json["per_chart"] ?? false,

      // NEW: supports both formats
      singles: Difficulty.fromJson(
        json["sp"] ?? levels?["single"] ?? {},
      ),
      doubles: Difficulty.fromJson(
        json["dp"] ?? levels?["double"] ?? {},
      ),

      radarSingles: parseRadars(radar?["sp"]),
      radarDoubles: parseRadars(radar?["dp"]),

      // Per-difficulty step counts (a jump counts as one step)
      singlesNotecounts: Difficulty.fromJson(notecounts?["sp"] ?? {}),
      doublesNotecounts: Difficulty.fromJson(notecounts?["dp"] ?? {}),

      // NEW: supports both "charts" and "chart"
      charts: List<Chart>.from(
        (json["charts"] ?? json["chart"] ?? []).map((x) => Chart.fromJson(x)),
      ),

      scoringTiers: ScoringTiers.tryParse(json["scoring_tiers"]),
      sync: json["sync"] == null ? null : Sync.fromJson(json["sync"]),
      arcadeSync: json["arcade_sync"] == null
          ? null
          : Sync.fromJson(json["arcade_sync"]),
      timeSignatures: List<TimeSignature>.from(
        (json["time_signatures"] ?? []).map((x) => TimeSignature.fromJson(x)),
      ),
      unlocksSingles: ChartUnlock.parseAll(json["unlocks"]?["sp"]),
      unlocksDoubles: ChartUnlock.parseAll(json["unlocks"]?["dp"]),
    );
  }

  Map<String, dynamic> toJson() => {
        if (scoringTiers != null) "scoring_tiers": scoringTiers!.toJson(),
        "ssc": ssc,
        "version": version,
        "name": name,
        if (konamiId.isNotEmpty) "konami_id": konamiId,
        "title": title,
        "titletranslit": titletranslit,
        "artist": artist,
        "artisttranslit": artisttranslit,
        "song_length": songLength,
        "per_chart": perChart,
        "sp": singles.toJson(),
        "dp": doubles.toJson(),
        "radar": {
          "sp": radarSingles.map((diff, r) => MapEntry(diff, r.toJson())),
          "dp": radarDoubles.map((diff, r) => MapEntry(diff, r.toJson())),
        },
        "notecounts": {
          "sp": singlesNotecounts.toJson(),
          "dp": doublesNotecounts.toJson(),
        },
        "chart": List<dynamic>.from(charts.map((x) => x.toJson())),
        if (sync != null) "sync": sync!.toJson(),
        if (arcadeSync != null) "arcade_sync": arcadeSync!.toJson(),
        if (timeSignatures.isNotEmpty)
          "time_signatures":
              List<dynamic>.from(timeSignatures.map((x) => x.toJson())),
        if (unlocksSingles.isNotEmpty || unlocksDoubles.isNotEmpty)
          "unlocks": {
            "sp": unlocksSingles.map((k, u) => MapEntry(k, u.toJson())),
            "dp": unlocksDoubles.map((k, u) => MapEntry(k, u.toJson())),
          },
      };
}

/// Where a chart is unlocked when it isn't playable by default.
enum UnlockSource { galaxyBrave, grandPrix }

/// How a chart is unlocked, and the day it becomes playable by default when
/// that's announced. GRAND PRIX charts are released this way about a year on,
/// so a chart past [until] reads as default without new content.
class ChartUnlock {
  const ChartUnlock({required this.source, this.pack = '', this.until});

  final UnlockSource source;

  /// The GRAND PRIX pack that carries the chart; empty for GALAXY BRAVE.
  final String pack;
  final DateTime? until;

  bool lockedOn(DateTime day) => until == null || day.isBefore(until!);

  static const _sources = {
    'galaxy_brave': UnlockSource.galaxyBrave,
    'grand_prix': UnlockSource.grandPrix,
  };

  /// One style's map; an entry with a source this app doesn't know is
  /// skipped, so content can add sources older apps ignore.
  static Map<String, ChartUnlock> parseAll(dynamic json) => {
        for (final MapEntry(:key, :value)
            in (json as Map<String, dynamic>? ?? {}).entries)
          if (_sources[value["via"]] case final source?)
            key: ChartUnlock(
              source: source,
              pack: value["pack"] ?? "",
              until: DateTime.tryParse(value["until"] ?? ""),
            ),
      };

  Map<String, dynamic> toJson() => {
        "via": _sources.entries.firstWhere((e) => e.value == source).key,
        if (pack.isNotEmpty) "pack": pack,
        if (until != null)
          "until": until!.toIso8601String().substring(0, 10),
      };
}

/// From [beat] on, bars are [beats] quarter notes long, until the next entry.
/// The first entry also covers any beats before it.
class TimeSignature {
  final double beat;
  final int beats;

  const TimeSignature({required this.beat, required this.beats});

  factory TimeSignature.fromJson(Map<String, dynamic> json) => TimeSignature(
        beat: (json["beat"] as num).toDouble(),
        beats: json["beats"] as int,
      );

  Map<String, dynamic> toJson() => {"beat": beat, "beats": beats};
}

class Chart {
  int dominantBpm;
  int trueMin;
  int trueMax;
  String bpmRange;
  List<Bpm> bpms;
  List<Stop> stops;
  Sync? sync;

  Chart({
    required this.dominantBpm,
    required this.trueMin,
    required this.trueMax,
    required this.bpmRange,
    required this.bpms,
    required this.stops,
    this.sync,
  });

  factory Chart.fromJson(Map<String, dynamic> json) => Chart(
        dominantBpm: json["dominant_bpm"] ?? 0,
        trueMin: json["true_min"] ?? 0,
        trueMax: json["true_max"] ?? 0,
        bpmRange: json["bpm_range"] ?? "",
        bpms: List<Bpm>.from(
          (json["bpms"] ?? []).map((x) => Bpm.fromJson(x)),
        ),
        stops: List<Stop>.from(
          (json["stops"] ?? []).map((x) => Stop.fromJson(x)),
        ),
        sync: json["sync"] == null ? null : Sync.fromJson(json["sync"]),
      );

  Map<String, dynamic> toJson() => {
        "dominant_bpm": dominantBpm,
        "true_min": trueMin,
        "true_max": trueMax,
        "bpm_range": bpmRange,
        "bpms": List<dynamic>.from(bpms.map((x) => x.toJson())),
        "stops": List<dynamic>.from(stops.map((x) => x.toJson())),
        if (sync != null) "sync": sync!.toJson(),
      };
}

/// Audio-vs-chart sync fingerprint produced by the DDR-BPM-prep sync stages
/// (same shape for the simfile "sync" and the cabinet "arcade_sync" blocks).
/// [curve] is the beat-attack convolution response normalized to 0..100,
/// sampled from [curveStartMs] in [curveStepMs] steps; its peak sits at
/// [biasMs]. Positive bias: the audio attack lands after the charted beat.
class Sync {
  double biasMs;

  /// Neutral at the displayed tenth-of-a-millisecond precision, matching the
  /// chart preview's on-the-beat reading.
  bool get isOnSync => biasMs.abs() < 0.05;
  double confidence;
  double curveStartMs;
  double curveStepMs;
  List<int> curve;

  Sync({
    required this.biasMs,
    required this.confidence,
    required this.curveStartMs,
    required this.curveStepMs,
    required this.curve,
  });

  factory Sync.fromJson(Map<String, dynamic> json) => Sync(
        biasMs: (json["bias_ms"] ?? 0).toDouble(),
        curveStartMs: (json["curve_start_ms"] ?? 0).toDouble(),
        curveStepMs: (json["curve_step_ms"] ?? 1).toDouble(),
        confidence: (json["confidence"] ?? 0).toDouble(),
        curve: List<int>.from(json["curve"] ?? []),
      );

  Map<String, dynamic> toJson() => {
        "bias_ms": biasMs,
        "confidence": confidence,
        "curve_start_ms": curveStartMs,
        "curve_step_ms": curveStepMs,
        "curve": curve,
      };
}

class Radar {
  double stream;
  double voltage;
  double air;
  double freeze;
  double chaos;

  Radar({
    required this.stream,
    required this.voltage,
    required this.air,
    required this.freeze,
    required this.chaos,
  });

  factory Radar.fromJson(Map<String, dynamic> json) => Radar(
        stream: (json["stream"] ?? 0).toDouble(),
        voltage: (json["voltage"] ?? 0).toDouble(),
        air: (json["air"] ?? 0).toDouble(),
        freeze: (json["freeze"] ?? 0).toDouble(),
        chaos: (json["chaos"] ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        "stream": stream,
        "voltage": voltage,
        "air": air,
        "freeze": freeze,
        "chaos": chaos,
      };
}

class Bpm {
  double st;
  double ed;
  int val;

  Bpm({
    required this.st,
    required this.ed,
    required this.val,
  });

  factory Bpm.fromJson(Map<String, dynamic> json) => Bpm(
        st: json["st"]?.toDouble(),
        ed: json["ed"]?.toDouble(),
        val: json["val"],
      );

  Map<String, dynamic> toJson() => {
        "st": st,
        "ed": ed,
        "val": val,
      };
}

class Stop {
  double st;
  double dur;
  List<Beat> beats;

  Stop({
    required this.st,
    required this.dur,
    required this.beats,
  });

  factory Stop.fromJson(Map<String, dynamic> json) {
    final beatsRaw = json["beats"];

    List<Beat> parsedBeats;

    if (beatsRaw == null) {
      parsedBeats = [];
    } else if (beatsRaw is num) {
      // OLD FORMAT
      parsedBeats = [
        Beat(bpm: 0, val: beatsRaw.toDouble()),
      ];
    } else if (beatsRaw is List) {
      // NEW FORMAT
      parsedBeats = List<Beat>.from(
        beatsRaw.map((x) => Beat.fromJson(x)),
      );
    } else {
      parsedBeats = [];
    }

    return Stop(
      st: (json["st"] ?? 0).toDouble(),
      dur: (json["dur"] ?? 0).toDouble(),
      beats: parsedBeats,
    );
  }

  Map<String, dynamic> toJson() => {
        "st": st,
        "dur": dur,
        "beats": List<dynamic>.from(beats.map((x) => x.toJson())),
      };
}

class Beat {
  int bpm;
  double val;

  Beat({
    required this.bpm,
    required this.val,
  });

  factory Beat.fromJson(Map<String, dynamic> json) => Beat(
        bpm: json["bpm"],
        val: json["val"]?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        "bpm": bpm,
        "val": val,
      };
}

enum Modes {
  singles,
  doubles,
}

// The cabinet's sort keys. `version` is the release order the cabinet treats as
// its default. The last three sort on the player's bests, only while the
// songlist shows them.
enum SortType {
  level,
  title,
  version,
  bpm,
  score,
  flare,
  lamp;

  bool get isBest => this == score || this == flare || this == lamp;

  /// Rows stand for one chart each, not a song.
  bool get isChartScoped => this == level || isBest;
}

class Difficulty {
  int? beginner;
  int? easy;
  int? medium;
  int? hard;
  int? challenge;

  Difficulty({
    this.beginner,
    this.easy,
    this.medium,
    this.hard,
    this.challenge,
  });

  factory Difficulty.fromJson(Map<String, dynamic> json) => Difficulty(
        beginner: json["beginner"],
        easy: json["easy"],
        medium: json["medium"],
        hard: json["hard"],
        challenge: json["challenge"],
      );

  Map<String, dynamic> toJson() => {
        "beginner": beginner,
        "easy": easy,
        "medium": medium,
        "hard": hard,
        "challenge": challenge,
      };

  /// Difficulty type keys (beginner..challenge) that have a level, in the
  /// canonical order used by chosenDifficulty's index (SongDifficultyPicker,
  /// radarFor).
  List<String> get availableTypes =>
      toJson().entries.where((e) => e.value != null).map((e) => e.key).toList();

  /// Every charted difficulty as its [availableTypes] index paired with its
  /// level, in canonical beginner..challenge order.
  List<({int index, int level})> get chartsByIndex {
    final levels = toJson();
    final types = availableTypes;
    return <({int index, int level})>[
      for (int i = 0; i < types.length; i++)
        (index: i, level: levels[types[i]] as int),
    ];
  }
}

/// A tier's hundredths as its shortest exact decimal digits: 90 → "9",
/// 85 → "85", 5 → "05", 0 → "0".
String decimalDigits(int hundredths) => hundredths % 10 == 0
    ? '${hundredths ~/ 10}'
    : hundredths.toString().padLeft(2, '0');

/// Optional chart-content predictions, independent of player achievements.
class ScoringTiers {
  const ScoringTiers(
      {required this.model,
      required this.engine,
      required this.singles,
      required this.doubles});
  final String model;
  final String engine;
  final Map<String, ScoringTier> singles;
  final Map<String, ScoringTier> doubles;

  static ScoringTiers? tryParse(dynamic value) {
    if (value is! Map ||
        value['schema'] != 1 ||
        value['model'] is! String ||
        (value['model'] as String).isEmpty) {
      return null;
    }
    Map<String, ScoringTier> entries(dynamic raw) => {
          if (raw is Map)
            for (final e in raw.entries)
              if (e.key is String)
                if (ScoringTier.tryParse(e.value) case final tier?)
                  e.key as String: tier,
        };
    return ScoringTiers(
        model: value['model'],
        engine: value['engine'] is String ? value['engine'] : '',
        singles: entries(value['sp']),
        doubles: entries(value['dp']));
  }

  Map<String, dynamic> toJson() => {
        'schema': 1,
        'model': model,
        if (engine.isNotEmpty) 'engine': engine,
        'sp': singles.map((k, v) => MapEntry(k, v.toJson())),
        if (doubles.isNotEmpty)
          'dp': doubles.map((k, v) => MapEntry(k, v.toJson())),
      };
}

class ScoringTier {
  const ScoringTier(
      {required this.tier, required this.position, required this.inputHash});
  final double tier;
  final double position;
  final String inputHash;
  // Hundredths past the level, e.g. 90 for 14.90.
  int get hundredths => (tier * 100).round() % 100;
  // Shortest exact decimal, e.g. 14.9, 14.85.
  String get label => '${tier.floor()}.${decimalDigits(hundredths)}';

  static ScoringTier? tryParse(dynamic value) {
    if (value is! Map ||
        value['tier'] is! num ||
        value['position'] is! num ||
        value['input_hash'] is! String) {
      return null;
    }
    final tier = (value['tier'] as num).toDouble();
    final position = (value['position'] as num).toDouble();
    if (!tier.isFinite || !position.isFinite || tier < 1 || tier >= 20) {
      return null;
    }
    final step = tier.floor() == 19 ? 10 : 5;
    final hundredths = (tier * 100).round();
    if ((tier * 100 - hundredths).abs() > .00001 || hundredths % step != 0) {
      return null;
    }
    return ScoringTier(
        tier: tier, position: position, inputHash: value['input_hash']);
  }

  Map<String, dynamic> toJson() =>
      {'tier': tier, 'position': position, 'input_hash': inputHash};
}
