// To parse this JSON data, do
//
//     final welcome = welcomeFromJson(jsonString);

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
  Levels levels;
  Chart chart;

  SongInfo({
    required this.ssc,
    required this.version,
    required this.name,
    required this.title,
    required this.titletranslit,
    required this.songLength,
    required this.perChart,
    required this.levels,
    required this.chart,
  });

  factory SongInfo.fromJson(Map<String, dynamic> json) => SongInfo(
        ssc: json["ssc"],
        version: json["version"],
        name: json["name"],
        title: json["title"],
        titletranslit: json["titletranslit"],
        songLength: json["song_length"]?.toDouble(),
        perChart: json["per_chart"],
        levels: Levels.fromJson(json["levels"]),
        chart: Chart.fromJson(json["chart"]),
      );

  Map<String, dynamic> toJson() => {
        "ssc": ssc,
        "version": version,
        "name": name,
        "title": title,
        "titletranslit": titletranslit,
        "song_length": songLength,
        "per_chart": perChart,
        "levels": levels.toJson(),
        "chart": chart.toJson(),
      };
}

class Chart {
  int dominantBpm;
  int trueMin;
  int trueMax;
  String bpmRange;
  List<Bpm> bpms;
  List<dynamic> stops;

  Chart({
    required this.dominantBpm,
    required this.trueMin,
    required this.trueMax,
    required this.bpmRange,
    required this.bpms,
    required this.stops,
  });

  factory Chart.fromJson(Map<String, dynamic> json) => Chart(
        dominantBpm: json["dominant_bpm"],
        trueMin: json["true_min"],
        trueMax: json["true_max"],
        bpmRange: json["bpm_range"],
        bpms: List<Bpm>.from(json["bpms"].map((x) => Bpm.fromJson(x))),
        stops: List<dynamic>.from(json["stops"].map((x) => x)),
      );

  Map<String, dynamic> toJson() => {
        "dominant_bpm": dominantBpm,
        "true_min": trueMin,
        "true_max": trueMax,
        "bpm_range": bpmRange,
        "bpms": List<dynamic>.from(bpms.map((x) => x.toJson())),
        "stops": List<dynamic>.from(stops.map((x) => x)),
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
        st: json["st"],
        ed: json["ed"]?.toDouble(),
        val: json["val"],
      );

  Map<String, dynamic> toJson() => {
        "st": st,
        "ed": ed,
        "val": val,
      };
}

class Levels {
  Difficulty single;
  Difficulty double;

  Levels({
    required this.single,
    required this.double,
  });

  factory Levels.fromJson(Map<String, dynamic> json) => Levels(
        single: Difficulty.fromJson(json["single"]),
        double: Difficulty.fromJson(json["double"]),
      );

  Map<String, dynamic> toJson() => {
        "single": single.toJson(),
        "double": double.toJson(),
      };
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
        challenge: json["challenge"]
      );

  Map<String, dynamic> toJson() => {
        "beginner": beginner,
        "easy": easy,
        "medium": medium,
        "hard": hard,
        "challenge": challenge,
      };
}
