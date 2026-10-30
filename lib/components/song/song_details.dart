/// Name: SongDetails
/// Parent: SongPage
/// Description: Widgets that display base song information.
library;

import 'dart:ui' show ImageFilter;

import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_binder_page.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_viewer.dart';
import 'package:ddr_md/components/song/song_difficulty_picker.dart';
import 'package:ddr_md/components/song/song_radar.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart' show canonicalVersion;
import 'package:ddr_md/helpers.dart'
    show kInGameDifficultyColors, kInGameDifficultyNames, versionColor;
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/score_overview.dart' show flareGroup;
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Widget _zoomArtwork(SongInfo song, {double radius = 22}) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SongArtwork(
        songName: song.name,
        title: song.title,
        fullResolution: true,
        fade: Duration.zero));

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
    final scroll = Scrollable.maybeOf(context)?.position;
    return Stack(
      // The artwork extends into the space revealed by a pull past the top.
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedBuilder(
              animation: scroll ?? const AlwaysStoppedAnimation(0.0),
              // Stretch only the paint: relaying out the scroll content while
              // overscrolled would make its viewport reset the scroll offset.
              builder: (context, child) => Transform.scale(
                alignment: Alignment.bottomCenter,
                scaleY: 1 +
                    (scroll != null && scroll.hasPixels && scroll.pixels < 0
                            ? -scroll.pixels
                            : 0) /
                        constraints.maxHeight,
                child: child,
              ),
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: ClipRect(
                    child: Stack(fit: StackFit.expand, children: [
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                        child: SongArtwork(
                            songName: songInfo.name, title: songInfo.title),
                      ),
                      DecoratedBox(
                          decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            pop.ink.withValues(alpha: 0.66),
                            pop.ink.withValues(alpha: 0.82),
                            pop.ink
                          ],
                          stops: const [0, 0.65, 1],
                        ),
                      )),
                      DecoratedBox(decoration: pop.stripes()),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          // The page's header buttons float over this, so it starts under them.
          padding: EdgeInsets.fromLTRB(
              20, MediaQuery.paddingOf(context).top + 4, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                      builder: (jacket) => GestureDetector(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.35),
                                      blurRadius: 30,
                                      offset: const Offset(0, 12)),
                                ],
                              ),
                              child: SizedBox.square(
                                  dimension: 96, child: _zoomArtwork(songInfo)),
                            ),
                            // Zooming image onTap
                            onTap: () async {
                              // The jacket and the card use the same decoded image. Avoid
                              // swapping a thumbnail for a fading full-size image in
                              // the middle of the opening, including a tap before load.
                              // Freeze identity before image/database awaits.
                              final mode = songState.modes;
                              final index = songState.chosenDifficulty;
                              final levels = mode == Modes.singles
                                  ? songInfo.singles
                                  : songInfo.doubles;
                              final key = _chosenDifficultyKey(levels, index);
                              final level = levels.toJson()[key] as int?;
                              final options = editionPreferences();
                              final (_, loaded) = await (
                                precacheImage(
                                    ContentStore.image(
                                        'assets/jackets/${songInfo.name}.png'),
                                    context,
                                    onError: (_, __) {}),
                                // Without bests the jacket still opens, plain.
                                editionDevelopmentEnabled && options.effects
                                    ? ChartBests.ensure(mode).then((_) => true,
                                        onError: (_) => false)
                                    : Future.value(false),
                              ).wait;
                              if (!context.mounted) return;
                              // The card's finish comes from the chart picked below.
                              final best = loaded && key != null
                                  ? ChartBests.forChart(songInfo.name, mode,
                                      kInGameDifficultyNames[key]!)
                                  : null;
                              final facts = EditionFacts(
                                chart: (
                                  song: songInfo.name,
                                  mode: mode.name,
                                  difficulty: key ?? ''
                                ),
                                level: level,
                                version: flareGroup(songInfo.version),
                                grade: best?.grade,
                                flare: best?.flare,
                                lamp: best?.lamp,
                                precision: loaded && key != null
                                    ? ChartBests.precisionAt(songInfo.name,
                                        mode, kInGameDifficultyNames[key]!)
                                    : null,
                                score: best?.score,
                                levelTop: loaded &&
                                    key != null &&
                                    ChartBests.levelTop(songInfo.name, mode,
                                        kInGameDifficultyNames[key]!),
                              );
                              await showEditionViewer(context,
                                  facts: facts,
                                  options: (
                                    borderId: options.borderId,
                                    effects: editionDevelopmentEnabled &&
                                        options.effects,
                                    motion: options.motion,
                                    // The score card carries the chart's badges;
                                    // the card is its finish alone.
                                    modeStamp: false,
                                    gradeStamp: false,
                                    difficultyStamp: false,
                                    tierSuffix: false
                                  ),
                                  from: switch (jacket.findRenderObject()) {
                                    final RenderBox box when box.hasSize =>
                                      box.localToGlobal(Offset.zero) & box.size,
                                    _ => null
                                  },
                                  artwork: _zoomArtwork(songInfo),
                                  // To this chart's pocket.
                                  onBinder: key == null
                                      ? null
                                      : () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) => EditionBinderPage(
                                                  level: level,
                                                  song: songInfo.name,
                                                  difficulty:
                                                      kInGameDifficultyNames[
                                                          key]))));
                            },
                          )),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Opacity(
                          opacity: hideTitle ? 0 : 1,
                          child: Text(songInfo.title,
                              key: titleKey,
                              style: FloorPop.display(20,
                                  color: scheme.onSurface)),
                        ),
                        if (songInfo.titletranslit.isNotEmpty &&
                            songInfo.titletranslit != songInfo.title)
                          Text(songInfo.titletranslit, style: muted),
                        if (songInfo.artist.isNotEmpty)
                          Text(songInfo.artist, style: muted),
                      ],
                    ),
                  ),
                  if (songInfo.radarFor(
                          songState.modes, songState.chosenDifficulty)
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
                _Badge(
                    value: songInfo.version,
                    detail:
                        flareGroup(canonicalVersion(songInfo.version))?.label,
                    color: versionColor(songInfo.version)),
                _Badge(
                    value: formattedTime(
                        timeInSecond: songInfo.songLength.toInt())),
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
        ),
      ],
    );
  }
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
