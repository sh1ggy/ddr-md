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
  String title;
  String titletranslit;
  double songLength;
  bool perChart;
  Difficulty singles;
  Difficulty doubles;
  Map<String, Radar> radarSingles;
  Map<String, Radar> radarDoubles;
  Difficulty singlesNotecounts;
  Difficulty doublesNotecounts;
  List<Chart> charts;

  SongInfo({
    required this.ssc,
    required this.version,
    required this.name,
    required this.title,
    required this.titletranslit,
    required this.songLength,
    required this.perChart,
    required this.singles,
    required this.doubles,
    required this.radarSingles,
    required this.radarDoubles,
    required this.singlesNotecounts,
    required this.doublesNotecounts,
    required this.charts,
  });

  /// Radar for the chart at [chosenDifficulty], which indexes the non-null
  /// difficulties of [mode] in beginner..challenge order (as rendered by
  /// SongDifficultyPicker). Out-of-range indexes clamp to match the picker's
  /// highlight when switching modes drops a difficulty.
  Radar? radarFor(Modes mode, int chosenDifficulty) {
    final radars = mode == Modes.singles ? radarSingles : radarDoubles;
    final levels = (mode == Modes.singles ? singles : doubles).toJson();
    final available = levels.entries
        .where((e) => e.value != null)
        .map((e) => e.key)
        .toList();
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
      title: json["title"] ?? "",
      titletranslit: json["titletranslit"] ?? "",
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
    );
  }

  Map<String, dynamic> toJson() => {
        "ssc": ssc,
        "version": version,
        "name": name,
        "title": title,
        "titletranslit": titletranslit,
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
      };
}

class Chart {
  int dominantBpm;
  int trueMin;
  int trueMax;
  String bpmRange;
  List<Bpm> bpms;
  List<Stop> stops;

  Chart({
    required this.dominantBpm,
    required this.trueMin,
    required this.trueMax,
    required this.bpmRange,
    required this.bpms,
    required this.stops,
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
      );

  Map<String, dynamic> toJson() => {
        "dominant_bpm": dominantBpm,
        "true_min": trueMin,
        "true_max": trueMax,
        "bpm_range": bpmRange,
        "bpms": List<dynamic>.from(bpms.map((x) => x.toJson())),
        "stops": List<dynamic>.from(stops.map((x) => x.toJson())),
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

enum SortType {
  level,
  title,
  version,
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
}
