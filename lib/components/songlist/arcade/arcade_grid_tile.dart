/// Name: ArcadeGridTile
/// Parent: ArcadeGridView
/// Description: One jacket in the arcade grid, its title and charted levels
/// banded above the artwork and BPM/sync captioned below it, so nothing covers
/// the jacket. A tap opens the song outright — there is no hover/confirm step —
/// so the tile carries no selection state of its own.
library;

import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/components/songlist/flare_card.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/components/song/scores/art_badge.dart';
import 'package:ddr_md/components/song/scores/score_card.dart'
    show clearLampIcon;
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show formatScore;
import 'package:ddr_md/theme.dart' show FloorPop;
import 'package:flutter/material.dart';

// Gap each tile leaves around its jacket, so neighbouring artwork doesn't abut.
const double kArcadeTileGap = 3;

// Height of the title/levels band above each jacket and the BPM/sync caption
// below it. Fixed so every tile in a row lines up; the grid adds both to the
// square jacket to size the cell.
const double kArcadeTitleHeight = 33;
const double kArcadeCaptionHeight = 19;

class ArcadeGridTile extends StatelessWidget {
  const ArcadeGridTile({
    super.key,
    required this.item,
    required this.mode,
    required this.onTap,
  });

  final SongItem item;
  // Which chart set the difficulty numbers come from.
  final Modes mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // A tile standing for one chart is a card in its flare colours, with the
    // player's bests pinned to the jacket's corners.
    final best = item.isChartScoped
        ? ChartBests.at(item.songInfo, mode, item.difficultyIndex!)
        : null;
    final flare = best?.flare;
    final plain = BoxDecoration(color: scheme.surfaceContainerHigh);
    // InkWell rather than a bare GestureDetector: with the tap now committing
    // straight to the song page, the ripple is the only feedback that the
    // press registered.
    return Padding(
      padding: const EdgeInsets.all(kArcadeTileGap),
      child: BestsReveal(
        shown: item.isChartScoped && ChartBests.shown,
        builder: (context, t) => Stack(fit: StackFit.expand, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                revealBack(
                  plain: plain,
                  flare: flare == null
                      ? const BoxDecoration()
                      : flareCardBack(context, flare, radius: 8),
                  t: t,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _titleBand(context),
                      Expanded(child: _jacket(context, best, t)),
                      _caption(context),
                    ],
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    splashColor: scheme.primary.withValues(alpha: 0.24),
                    highlightColor: scheme.primary.withValues(alpha: 0.10),
                  ),
                ),
              ],
            ),
          ),
          if (flare != null && t > 0)
            IgnorePointer(
              child: Opacity(
                opacity: t,
                child: CustomPaint(painter: FlareFrame(flare, radius: 8)),
              ),
            ),
        ]),
      ),
    );
  }

  // BPM and sync below the artwork, on the tile's own surface rather than
  // overlaid on the jacket.
  Widget _caption(BuildContext context) {
    return SizedBox(
      height: kArcadeCaptionHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(3, 2, 3, 3),
        child: _statStrip(context),
      ),
    );
  }

  // Title and levels in their own band above the jacket, so nothing is ever
  // laid over the artwork.
  Widget _titleBand(BuildContext context) {
    final SongInfo song = item.songInfo;
    return SizedBox(
      height: kArcadeTitleHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(3, 3, 3, 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              song.titletranslit.isNotEmpty ? song.titletranslit : song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            _difficultyRow(),
          ],
        ),
      ),
    );
  }

  Widget _jacket(BuildContext context, ChartBest? best, double t) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          JacketImage(item.songInfo),
          if (item.isFav)
            const Positioned(
              top: 2,
              left: 2,
              // Sits straight on the artwork, so it carries its own shadow.
              child: Icon(
                Icons.star,
                color: Colors.yellow,
                size: 14,
                shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 3)],
              ),
            ),
          if (best != null && t > 0) Opacity(opacity: t, child: _bests(best)),
        ],
      ),
    );
  }

  // Flare, grade and lamp in a row across the top, score in a tab at the
  // bottom, both centred. Badges the chart hasn't earned are left off rather
  // than drawn empty.
  Widget _bests(ChartBest best) {
    Widget badge(String art, double aspect) =>
        ArtBadge(art, aspect: aspect, ink: 9, height: 15);
    final lamp = clearLampIcon(best.lamp);
    final score = best.score;
    const figures = [FontFeature.tabularFigures()];
    return Stack(children: <Widget>[
      if (best.flare != null || best.grade != null || lamp != null)
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          // Shrinks rather than overflows on a narrow tile.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xB0000000),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: <Widget>[
                    if (best.flare case final String flare)
                      badge(flareRankIcon(flare), kFlareAspect),
                    if (best.grade case final Grade grade)
                      badge(gradeIcon(grade), kGradeAspect),
                    if (lamp != null) badge(lamp, kLampAspect),
                  ],
                ),
              ),
            ),
          ),
        ),
      if (score != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Center(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xB0000000),
                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Builder(builder: (context) {
                  final text = formatScore(score);
                  final split = text.lastIndexOf(',');
                  return Text.rich(TextSpan(children: [
                    TextSpan(
                        text: text.substring(0, split),
                        style: FloorPop.readout(12, color: Colors.white)
                            .copyWith(fontFeatures: figures)),
                    TextSpan(
                        text: text.substring(split),
                        style: FloorPop.readout(9, color: Colors.white70)
                            .copyWith(fontFeatures: figures)),
                  ]));
                }),
              ),
            ),
          ),
        ),
    ]);
  }

  // The song's charted levels for the current mode, in the canonical
  // beginner..challenge order and colour-coded off the same palette the list
  // view and the song page use. Missing charts are skipped rather than padded,
  // so a song with three charts shows three numbers. When the tile stands for
  // one chart, that number leads at full weight and the rest recede.
  Widget _difficultyRow() {
    final Difficulty difficulty =
        mode == Modes.singles ? item.songInfo.singles : item.songInfo.doubles;
    // Clipped rather than wrapped: on a narrow tile a wrap would silently add
    // a row and overflow the band's fixed height.
    return ClipRect(
      child: LevelRow(
          levels: difficulty,
          height: kSongListLevelHeight,
          // Fixed columns don't fit all five on a narrow tile.
          packed: true,
          highlightIndex: item.isChartScoped ? item.difficultyIndex : null),
    );
  }

  Chart get _chart => item.isChartScoped
      ? item.songInfo.chartAt(mode, item.difficultyIndex!)
      : item.songInfo.charts.first;

  // Recommended in-game offset adjustment: the bias with its sign flipped.
  (String, Color)? _syncAdjust(bool isDark) {
    final Sync? sync = item.songInfo.displaySyncFor(_chart);
    if (sync == null) return null;
    final double adjustBy = -sync.biasMs;
    final Color color = sync.biasMs < 0
        ? kSlowColor(isDark)
        : sync.biasMs > 0
            ? kFastColor(isDark)
            : Colors.grey;
    return ('${adjustBy >= 0 ? '+' : ''}${adjustBy.toStringAsFixed(0)}', color);
  }

  Widget _statStrip(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Expanded(
          child: _statText(
              _chart.bpmRange, Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        if (_syncAdjust(isDark) case (final String label, final Color color))
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _statText(label, color),
          ),
      ],
    );
  }

  Widget _statText(String text, Color color) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      );
}
