/// Name: JacketImage
/// Parent: SongListItem, ArcadeGridTile
/// Description: A song's jacket that fills its slot with a placeholder and
/// fades the artwork in once decoded, so rows keep their shape while jackets
/// stream in on a fast scroll.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:flutter/material.dart';

class JacketImage extends StatelessWidget {
  const JacketImage(this.song,
      {super.key,
      this.iconSize = 30,
      this.fade = const Duration(milliseconds: 150)});

  final SongInfo song;
  final double iconSize;
  final Duration fade;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Image(
        image: ContentStore.image('assets/jackets-160/${song.name}.png'),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        // Already-cached jackets draw straight away; only a fresh decode fades.
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            wasSynchronouslyLoaded
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: fade,
                    curve: Curves.easeOut,
                    child: child,
                  ),
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.music_note,
          size: iconSize,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
