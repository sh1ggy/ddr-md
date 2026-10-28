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

  /// The song's bar lengths, when it isn't plain 4/4 from beat 0 (empty then).
  List<TimeSignature> timeSignatures;

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
    this.timeSignatures = const [],
  });

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

      sync: json["sync"] == null ? null : Sync.fromJson(json["sync"]),
      arcadeSync: json["arcade_sync"] == null
          ? null
          : Sync.fromJson(json["arcade_sync"]),
      timeSignatures: List<TimeSignature>.from(
        (json["time_signatures"] ?? []).map((x) => TimeSignature.fromJson(x)),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
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
// its default.
enum SortType {
  level,
  title,
  version,
  bpm,
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
