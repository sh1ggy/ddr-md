/// Name: SongDetails
/// Parent: SongPage
/// Description: Widgets that display base song information.
library;

import 'package:ddr_md/components/song/song_difficulty_picker.dart';
import 'package:ddr_md/components/song/song_chart.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Builds the BPM range shown after the dominant BPM, e.g. " (75~) 100~200 (~400)".
/// True min/max only appear when they fall outside the displayed range.
String _bpmRangeSuffix(Chart chart) {
  if (chart.trueMax == chart.trueMin) return '';
  final buffer = StringBuffer();
  if (!chart.bpmRange.contains('${chart.trueMin}')) {
    buffer.write(' (${chart.trueMin}~)');
  }
  buffer.write(' ${chart.bpmRange}');
  if (!chart.bpmRange.contains('${chart.trueMax}')) {
    buffer.write(' (~${chart.trueMax})');
  }
  return buffer.toString();
}

const _difficultyColors = <String, Color>{
  "beginner": Colors.cyan,
  "easy": Colors.orange,
  "medium": Colors.red,
  "hard": Colors.green,
  "challenge": Colors.purple,
};

/// The difficulty key ("beginner".."challenge") the picker's chosen index
/// refers to: the picker only shows the mode's non-null levels, so the index
/// counts across those.
String? _chosenDifficultyKey(Difficulty difficulty, int chosenIndex) {
  final keys = difficulty
      .toJson()
      .entries
      .where((entry) => entry.value != null)
      .map((entry) => entry.key)
      .toList();
  if (keys.isEmpty) return null;
  return keys[chosenIndex.clamp(0, keys.length - 1)];
}

// Method for formatting time from a given time (s)
formattedTime({required int timeInSecond}) {
  int sec = timeInSecond % 60;
  int min = (timeInSecond / 60).floor();
  String minute = min.toString().length <= 1 ? "$min" : "$min";
  String second = sec.toString().length <= 1 ? "0$sec" : "$sec";
  return "$minute:$second";
}

class SongDetails extends StatelessWidget {
  const SongDetails({
    super.key,
    required this.songInfo,
    required this.chart,
  });

  final SongInfo songInfo;
  final Chart? chart;

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    final chart = this.chart;

    final difficulty =
        songState.modes == Modes.singles ? songInfo.singles : songInfo.doubles;
    final notecounts = songState.modes == Modes.singles
        ? songInfo.singlesNotecounts
        : songInfo.doublesNotecounts;
    final chosenKey =
        _chosenDifficultyKey(difficulty, songState.chosenDifficulty);
    final chosenNotecount =
        chosenKey == null ? null : notecounts.toJson()[chosenKey];

    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Column(
            children: [
              GestureDetector(
                child: Hero(
                  tag: "imgZoom",
                  child: _ResolvedJacketImage(
                    songName: songInfo.name,
                    assetPrefix: 'assets/jackets-160/',
                    height: 100,
                    fallbackSize: 100,
                  ),
                ),
                // Zooming image onTap
                onTap: () {
                  Navigator.of(context).push(PageRouteBuilder(
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      opaque: true,
                      barrierDismissible: true,
                      pageBuilder: (BuildContext context, _, __) {
                        return GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Hero(
                            tag: "imgZoom",
                            transitionOnUserGestures: true,
                            child: _ResolvedJacketImage(
                              songName: songInfo.name,
                              assetPrefix: 'assets/jackets/',
                              height: MediaQuery.of(context).size.height * .7,
                              fallbackSize: 100,
                            ),
                          ),
                        );
                      }));
                },
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (chart != null)
                            RichText(
                              text: TextSpan(
                                style: TextStyle(
                                    fontSize: 15.5,
                                    color: DefaultTextStyle.of(context)
                                        .style
                                        .color),
                                children: <TextSpan>[
                                  TextSpan(
                                    text: "${chart.dominantBpm} BPM",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(text: _bpmRangeSuffix(chart)),
                                ],
                              ),
                            ),
                          Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  formattedTime(
                                          timeInSecond:
                                              songInfo.songLength.toInt()) +
                                      " min",
                                  style: const TextStyle(
                                      fontSize: 16.0,
                                      fontWeight: FontWeight.bold),
                                ),
                                if (chosenNotecount != null) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.music_note,
                                      size: 14, color: Colors.grey),
                                  Text(
                                    "$chosenNotecount",
                                    style: TextStyle(
                                        fontSize: 16.0,
                                        color: _difficultyColors[chosenKey],
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ]),
                          Text(
                            songInfo.version,
                            style: const TextStyle(
                                fontSize: 15.5,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                    if (songInfo.radarFor(
                            songState.modes, songState.chosenDifficulty)
                        case final radar?)
                      SongRadarChart(radar: radar),
                  ],
                ),
                // Every song has per-difficulty radar data, so the
                // difficulty is always selectable.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SongDifficultyPicker(difficulty: difficulty),
                ),
              ],
            ),
          ),
        ]);
  }
}

/// A song's jacket, `<prefix><song name>.png`, or a note icon when it has none.
class _ResolvedJacketImage extends StatelessWidget {
  const _ResolvedJacketImage({
    required this.songName,
    required this.assetPrefix,
    required this.height,
    required this.fallbackSize,
  });

  final String songName;
  final String assetPrefix;
  final double height;
  final double fallbackSize;

  @override
  Widget build(BuildContext context) => Image(
        image: ContentStore.image('$assetPrefix$songName.png'),
        height: height,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.music_note, size: fallbackSize),
      );
}
