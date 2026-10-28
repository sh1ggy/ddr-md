/// Name: JacketImage
/// Parent: SongListItem, ArcadeGridTile, SongDetails
/// Description: A song's jacket with deterministic generated art while its
/// image loads or when no artwork is available.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/generated_jacket.dart';
import 'package:ddr_md/models/content_store.dart';
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
    final fallback = GeneratedJacket(songName: songName, title: title);
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
        image: true,
        label: title ?? songName,
        child: ExcludeSemantics(
            child: Stack(fit: StackFit.expand, children: [
          fallback,
          Image(
            image: ContentStore.image(
                'assets/${fullResolution ? 'jackets' : 'jackets-160'}/$songName.png'),
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
