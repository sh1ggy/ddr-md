/// Name: SortMenuButton
/// Parent: DifficultyListPage, FavoriteListPage
/// Description: Button that cycles the shared song sort, sitting beside the
/// songlist's count. A tap advances the key (release order / title / level /
/// BPM); a long press flips between ascending and descending.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Cycle order, starting on the cabinet's default.
const List<SortType> _kSortCycle = <SortType>[
  SortType.version,
  SortType.title,
  SortType.level,
  SortType.bpm,
];

String sortLabel(SortType sortType) {
  switch (sortType) {
    case SortType.version:
      return 'Default';
    case SortType.title:
      return 'Title';
    case SortType.level:
      return 'Level';
    case SortType.bpm:
      return 'BPM';
  }
}

class SortMenuButton extends StatelessWidget {
  const SortMenuButton({super.key, this.onSorted});

  // Called after the sort changes, once the new value is set in SongState.
  final void Function()? onSorted;

  @override
  Widget build(BuildContext context) {
    final SongState songState = context.watch<SongState>();
    final bool descending = songState.sortDescending;
    final String label = sortLabel(songState.sortType);

    return Tooltip(
      message: 'Sort: $label — long press to reverse',
      child: TextButton.icon(
        onPressed: () {
          final int next = (_kSortCycle.indexOf(songState.sortType) + 1) %
              _kSortCycle.length;
          songState.setSortType(_kSortCycle[next]);
          onSorted?.call();
        },
        onLongPress: () {
          songState.setSortDescending(!descending);
          onSorted?.call();
        },
        icon: Icon(
          descending ? Icons.arrow_downward : Icons.arrow_upward,
          size: 16,
        ),
        label: Text(label),
      ),
    );
  }
}
