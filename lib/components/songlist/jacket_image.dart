/// Name: JacketImage
/// Parent: SongListItem, ArcadeGridTile, SongDetails
/// Description: A song's jacket. Behind it, a plain music-note tile for songs
/// in the list, or deterministic generated art for songs it doesn't know.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/generated_jacket.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';

class JacketImage extends StatelessWidget {
  const JacketImage(this.song,
      {super.key,
      this.iconSize = 30,
      this.fade = const Duration(milliseconds: 150)});

  final SongInfo song;
  // Kept for list callers that also size their surrounding icons.
  final double iconSize;
  final Duration fade;

  @override
  Widget build(BuildContext context) =>
      SongArtwork(songName: song.name, title: song.title, fade: fade);
}

/// Fills a bounded slot. The same fallback is used for thumbnails, zoomed art,
/// and the song header's atmospheric backdrop.
class SongArtwork extends StatelessWidget {
  const SongArtwork(
      {super.key,
      required this.songName,
      this.title,
      this.fullResolution = false,
      this.fade = const Duration(milliseconds: 150)});

  final String songName;
  final String? title;
  final bool fullResolution;
  final Duration fade;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Songs.contains(songName)
        ? ColoredBox(
            color: scheme.surfaceContainerLow,
            child: FractionallySizedBox(
                widthFactor: 0.4,
                heightFactor: 0.4,
                child: FittedBox(
                    child: Icon(Icons.music_note,
                        color: scheme.onSurfaceVariant))))
        : GeneratedJacket(songName: songName, title: title);
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
        image: true,
        label: title ?? songName,
        child: ExcludeSemantics(
            child: Stack(fit: StackFit.expand, children: [
          fallback,
          Image(
            image: ContentStore.image(
                'assets/${fullResolution ? 'jackets-webp' : 'jackets-160-webp'}/$songName.webp'),
            fit: BoxFit.cover,
            filterQuality:
                fullResolution ? FilterQuality.medium : FilterQuality.low,
            frameBuilder: (context, child, frame, synchronous) => synchronous
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: still ? Duration.zero : fade,
                    curve: Curves.easeOut,
                    child: child),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ])));
  }
}
