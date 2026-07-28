/// Name: ArcadeGridTile
/// Parent: ArcadeGridView
/// Description: One jacket in the arcade grid, captioned with its title, BPM
/// and charted levels. A tap opens the song outright — there is no
/// hover/confirm step — so the tile carries no selection state of its own.
library;

import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:flutter/material.dart';

// Gap each tile leaves around its jacket, so neighbouring artwork doesn't abut.
const double kArcadeTileGap = 4;

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
            _jacket(context),
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _infoStrip(),
          ),
          if (item.isFav)
            const Positioned(
              top: 2,
              left: 2,
              child: Icon(Icons.star, color: Colors.yellow, size: 14),
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
    // a row and push the strip up over the artwork.
    return ClipRect(
      child: Row(mainAxisSize: MainAxisSize.min, children: numbers),
    );
  }

  Widget _levelText(MapEntry<String, int?> chart, {required bool dimmed}) {
    final Color color = difficultyColor(chart.key);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        '${chart.value}',
        style: TextStyle(
          color: dimmed ? color.withValues(alpha: 0.45) : color,
          fontSize: dimmed ? 10 : 11,
          height: 1.2,
          fontWeight: dimmed ? FontWeight.w400 : FontWeight.w700,
          // The numbers sit on artwork, so they carry their own shadow rather
          // than relying on the scrim alone.
          shadows: const <Shadow>[Shadow(color: Colors.black, blurRadius: 2)],
        ),
      ),
    );
  }

  // Title and levels banded across the jacket's foot. Overlaid rather than
  // given its own row so the jacket keeps the whole cell, with a gradient scrim
  // to stay legible over light artwork.
  Widget _infoStrip() {
    final SongInfo song = item.songInfo;
    // The translit is the readable form for Japanese titles; for everything
    // else it repeats the title, so it is only worth a second line when it
    // actually differs.
    final String primary =
        song.titletranslit.isNotEmpty ? song.titletranslit : song.title;
    final String? secondary =
        song.title != primary && song.title.isNotEmpty ? song.title : null;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Colors.black87, Colors.black],
          stops: <double>[0, 0.45, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(3, 6, 3, 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              primary,
              maxLines: secondary == null ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                // Fixed light tones, not scheme colours: the strip is a dark
                // scrim over artwork in both light and dark mode.
                color: Colors.white,
                fontSize: 12,
                height: 1.15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (secondary != null)
              Text(
                secondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  height: 1.15,
                ),
              ),
            _difficultyRow(),
          ],
        ),
      ),
    );
  }
}
