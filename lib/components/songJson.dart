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
    List<Chart> chart;

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
        chart: List<Chart>.from(json["chart"].map((x) => Chart.fromJson(x))),
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
        "chart": List<dynamic>.from(chart.map((x) => x.toJson())),
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
    Double single;
    Double levelsDouble;

    Levels({
        required this.single,
        required this.levelsDouble,
    });

    factory Levels.fromJson(Map<String, dynamic> json) => Levels(
        single: Double.fromJson(json["single"]),
        levelsDouble: Double.fromJson(json["double"]),
    );

    Map<String, dynamic> toJson() => {
        "single": single.toJson(),
        "double": levelsDouble.toJson(),
    };
}

class Double {
    int easy;
    int medium;
    int hard;
    int? beginner;

    Double({
        required this.easy,
        required this.medium,
        required this.hard,
        this.beginner,
    });

    factory Double.fromJson(Map<String, dynamic> json) => Double(
        easy: json["easy"],
        medium: json["medium"],
        hard: json["hard"],
        beginner: json["beginner"],
    );

    Map<String, dynamic> toJson() => {
        "easy": easy,
        "medium": medium,
        "hard": hard,
        "beginner": beginner,
    };
}
