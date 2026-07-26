/// Name: SongItem
/// Parent: DifficultyListPage, ArcadeGridView
/// Description: One row of the generated songlist — the song plus the bits of
/// per-user state the list needs alongside it. Lives apart from the page so
/// both the list and the arcade grid can consume it without importing each
/// other.
library;

import 'package:ddr_md/components/song_json.dart';

class SongItem {
  SongItem({
    required this.songInfo,
    required this.isFav,
    this.defaultDifficultyIndex,
  });

  SongInfo songInfo;
  bool isFav;
  // chosenDifficulty index to open the song at, when a single level filter
  // is active and matches one of this song's difficulty types.
  int? defaultDifficultyIndex;
}
