/// Name: SortMenuButton
/// Parent: DifficultyListPage, FavoriteListPage
/// Description: Button that cycles the shared song sort, sitting beside the
/// songlist's count. The label advances the key (release order / title /
/// level / BPM, plus score / flare / lamp on the songlist while bests show);
/// the arrow beside it flips ascending/descending.
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
  SortType.score,
  SortType.flare,
  SortType.lamp,
];

/// The key after [sortType] in the cycle, skipping the bests sorts unless
/// [bests].
SortType nextSortType(SortType sortType, {bool bests = false}) {
  final cycle = [
    for (final s in _kSortCycle)
      if (bests || !s.isBest) s
  ];
  return cycle[(cycle.indexOf(sortType) + 1) % cycle.length];
}

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
    case SortType.score:
      return 'Score';
    case SortType.flare:
      return 'Flare';
    case SortType.lamp:
      return 'Lamp';
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
    // The favourites list has no bests, so it sorts a bests sort as the
    // default.
    final SortType sortType =
        songState.sortType.isBest ? SortType.version : songState.sortType;
    final String label = sortLabel(sortType);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextButton(
          onPressed: () {
            songState.setSortType(nextSortType(sortType));
            onSorted?.call();
          },
          child: Text(label),
        ),
        IconButton(
          tooltip: descending ? 'Descending' : 'Ascending',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            songState.setSortDescending(!descending);
            onSorted?.call();
          },
          icon: Icon(
            descending ? Icons.arrow_downward : Icons.arrow_upward,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
