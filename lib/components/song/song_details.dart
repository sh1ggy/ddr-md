/// Name: SongDetails
/// Parent: SongPage
/// Description: Widgets that display base song information.
library;

import 'package:ddr_md/components/song/song_difficulty_picker.dart';
import 'package:ddr_md/components/song/song_radar.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart'
    show kInGameDifficultyColors, kInGameDifficultyNames;
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    this.titleKey,
    this.hideTitle = false,
  });

  final SongInfo songInfo;
  final Chart? chart;
  final Key? titleKey;
  // The page draws its own moving copy of the title over this one.
  final bool hideTitle;

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
      // The page's header buttons float over this, so it starts under them.
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.paddingOf(context).top + 4, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                        height: 96,
                        fallbackSize: 100,
                      ),
                    ),
                  ),
                ),
                // Zooming image onTap
                onTap: () {
                  // The jacket flies up to full size over a darkening page,
                  // a beat long (instant under reduced motion).
                  final still = MediaQuery.of(context).disableAnimations;
                  Navigator.of(context).push(PageRouteBuilder(
                      transitionDuration: still ? Duration.zero : FloorPop.beat,
                      reverseTransitionDuration:
                          still ? Duration.zero : FloorPop.eighth,
                      opaque: false,
                      barrierColor: Colors.black87,
                      barrierDismissible: true,
                      transitionsBuilder: (_, animation, __, child) =>
                          FadeTransition(opacity: animation, child: child),
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
                    Opacity(
                      opacity: hideTitle ? 0 : 1,
                      child: Text(songInfo.title,
                          key: titleKey,
                          style: FloorPop.display(20, color: scheme.onSurface)),
                    ),
                    if (songInfo.titletranslit.isNotEmpty &&
                        songInfo.titletranslit != songInfo.title)
                      Text(songInfo.titletranslit, style: muted),
                    if (songInfo.artist.isNotEmpty)
                      Text(songInfo.artist, style: muted),
                  ],
                ),
              ),
              if (songInfo.radarFor(songState.modes, songState.chosenDifficulty)
                  case final radar?)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: SongRadarChart(
                      radar: radar, color: _difficultyColors[chosenKey]),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // The song at a glance, one row of pills under its title.
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (chart != null)
              _Badge(
                value: '${chart.dominantBpm}',
                detail: chart.trueMin == chart.trueMax
                    ? 'BPM'
                    : '${chart.trueMin}~${chart.trueMax}',
              ),
            _Badge(value: songInfo.version),
            _Badge(
                value:
                    formattedTime(timeInSecond: songInfo.songLength.toInt())),
            if (chosenNotecount != null)
              _Badge(
                  value: '$chosenNotecount',
                  detail: 'steps',
                  color: _difficultyColors[chosenKey]),
          ]),
          const SizedBox(height: 14),
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

/// One fact about the song as a small pill: its value, with an optional
/// quieter word or range beside it.
class _Badge extends StatelessWidget {
  const _Badge({required this.value, this.detail, this.color});

  final String value;
  final String? detail;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: pop.riser, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value,
              style: FloorPop.readout(14,
                  color: color ?? Theme.of(context).colorScheme.onSurface)),
          if (detail != null) ...[
            const SizedBox(width: 4),
            Text(detail!,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: pop.haze)),
          ],
        ],
      ),
    );
  }
}
