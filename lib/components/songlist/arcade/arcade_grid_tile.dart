/// Name: ArcadeGridTile
/// Parent: ArcadeGridView
/// Description: One jacket in the arcade grid, its title and charted levels
/// banded above the artwork and BPM/sync captioned below it, so nothing covers
/// the jacket. A tap opens the song outright — there is no hover/confirm step —
/// so the tile carries no selection state of its own.
library;

import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart';
import 'package:flutter/material.dart';

// Gap each tile leaves around its jacket, so neighbouring artwork doesn't abut.
const double kArcadeTileGap = 4;

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
    // InkWell rather than a bare GestureDetector: with the tap now committing
    // straight to the song page, the ripple is the only feedback that the
    // press registered.
    return Padding(
      padding: const EdgeInsets.all(kArcadeTileGap),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(
              color: scheme.surfaceContainerHigh,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _titleBand(context),
                  Expanded(child: _jacket(context)),
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
    );
  }

  // BPM and sync below the artwork, on the tile's own surface rather than
  // overlaid on the jacket.
  Widget _caption(BuildContext context) {
    return SizedBox(
      height: kArcadeCaptionHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 3),
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
        padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
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

  Widget _jacket(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image(
            image: AssetImage('assets/jackets-160/${item.songInfo.name}.png'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Icon(
                Icons.music_note,
                size: 30,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
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
        ],
      ),
    );
  }

  // The song's charted levels for the current mode, in the canonical
  // beginner..challenge order and colour-coded off the same palette the list
  // view and the song page use. Missing charts are skipped rather than padded,
  // so a song with three charts shows three numbers. When the tile stands for
  // one chart, that number leads at full weight and the rest recede.
  Widget _difficultyRow() {
    final Difficulty difficulty =
        mode == Modes.singles ? item.songInfo.singles : item.songInfo.doubles;
    final Map<String, int?> levels = <String, int?>{
      'beginner': difficulty.beginner,
      'easy': difficulty.easy,
      'medium': difficulty.medium,
      'hard': difficulty.hard,
      'challenge': difficulty.challenge,
    };

    // Charted entries only, so the position matches availableTypes' index.
    final List<MapEntry<String, int?>> charted =
        levels.entries.where((e) => e.value != null).toList();

    final List<Widget> numbers = <Widget>[
      for (int i = 0; i < charted.length; i++)
        _levelText(
          charted[i],
          dimmed: item.isChartScoped && i != item.difficultyIndex,
        ),
    ];
    if (numbers.isEmpty) return const SizedBox.shrink();

    // Clipped rather than wrapped: on a narrow tile a wrap would silently add
    // a row and overflow the band's fixed height.
    return ClipRect(
      child: Row(mainAxisSize: MainAxisSize.min, children: numbers),
    );
  }

  int get _chartIndex {
    final int i = item.isChartScoped ? (item.difficultyIndex ?? 0) : 0;
    return i < item.songInfo.charts.length ? i : 0;
  }

  // Recommended in-game offset adjustment: the bias with its sign flipped.
  (String, Color)? _syncAdjust(bool isDark) {
    final Sync? sync =
        item.songInfo.displaySyncFor(item.songInfo.charts[_chartIndex]);
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
          child: _statText(item.songInfo.charts[_chartIndex].bpmRange,
              Theme.of(context).colorScheme.onSurfaceVariant),
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

  Widget _levelText(MapEntry<String, int?> chart, {required bool dimmed}) {
    final Color color = difficultyColor(chart.key);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        '${chart.value}',
        style: TextStyle(
          // Dimmed numbers still have to read, so they recede by weight and
          // size rather than by fading most of the way out.
          color: dimmed ? color.withValues(alpha: 0.7) : color,
          fontSize: dimmed ? 10 : 11,
          height: 1.2,
          fontWeight: dimmed ? FontWeight.w500 : FontWeight.w700,
        ),
      ),
    );
  }
}
