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
    this.difficultyIndex,
    this.level,
  });

  SongInfo songInfo;
  bool isFav;
  // The chart this row stands for, null when the row is the whole song. Only
  // an active level filter scopes a row to one chart (see generateSongItems).
  int? difficultyIndex;
  int? level;

  bool get isChartScoped => difficultyIndex != null;
}
