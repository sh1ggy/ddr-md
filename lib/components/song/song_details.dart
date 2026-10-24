/// Name: SongDetails
/// Parent: SongPage
/// Description: Widgets that display base song information.
library;

import 'package:ddr_md/components/song/song_difficulty_picker.dart';
import 'package:ddr_md/components/song/song_chart.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart'
    show kInGameDifficultyColors, kInGameDifficultyNames;
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
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

final _difficultyColors = <String, Color>{
  for (final MapEntry(:key, :value) in kInGameDifficultyNames.entries)
    key: kInGameDifficultyColors[value]!,
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
String formattedTime({required int timeInSecond}) {
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

    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 14, height: 1.3, color: pop.haze);
    return Container(
      decoration: pop.stripes(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                child: Hero(
                  tag: "imgZoom",
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 30,
                            offset: const Offset(0, 12)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: _ResolvedJacketImage(
                        songName: songInfo.name,
                        assetPrefix: 'assets/jackets-160/',
                        height: 112,
                        fallbackSize: 100,
                      ),
                    ),
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (chart != null)
                                Text.rich(TextSpan(
                                  style: FloorPop.readout(18,
                                      color: scheme.onSurface),
                                  children: [
                                    TextSpan(text: '${chart.dominantBpm}'),
                                    TextSpan(
                                        text: _bpmRangeSuffix(chart),
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: pop.haze,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                )),
                              const SizedBox(height: 4),
                              // Where and how long, then the chosen chart's
                              // steps in its difficulty's colour.
                              Text.rich(TextSpan(
                                style: muted.copyWith(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                                children: [
                                  TextSpan(
                                      text: '${songInfo.version} · '
                                          '${formattedTime(timeInSecond: songInfo.songLength.toInt())}'),
                                  if (chosenNotecount != null) ...[
                                    const TextSpan(text: ' · '),
                                    TextSpan(
                                        text: '$chosenNotecount steps',
                                        style: TextStyle(
                                            color:
                                                _difficultyColors[chosenKey])),
                                  ],
                                ],
                              )),
                            ],
                          ),
                        ),
                        if (songInfo.radarFor(
                                songState.modes, songState.chosenDifficulty)
                            case final radar?)
                          SongRadarChart(
                              radar: radar,
                              color: _difficultyColors[chosenKey]),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(songInfo.title,
                        style: FloorPop.display(22, color: scheme.onSurface)),
                    if (songInfo.titletranslit.isNotEmpty &&
                        songInfo.titletranslit != songInfo.title)
                      Text(songInfo.titletranslit, style: muted),
                    if (songInfo.artist.isNotEmpty)
                      Text(songInfo.artist, style: muted),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Every song has per-difficulty radar data, so the difficulty is
          // always selectable.
          SongDifficultyPicker(difficulty: difficulty),
        ],
      ),
    );
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
