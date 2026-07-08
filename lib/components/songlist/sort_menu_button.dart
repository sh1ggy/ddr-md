/// Name: SortMenuButton
/// Parent: DifficultyListPage, FavoriteListPage
/// Description: App bar popup menu that sets the shared song sort, i.e. how
/// songs are bucketed into folders (level / title letter / version).
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SortMenuButton extends StatelessWidget {
  const SortMenuButton({super.key, this.onSorted});

  // Called after the sort changes, once the new value is set in SongState.
  final void Function()? onSorted;

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    return PopupMenuButton(
      tooltip: "Sort",
      icon: const Icon(Icons.sort),
      itemBuilder: (BuildContext context) => <PopupMenuEntry>[
        sortMenuItem(context, songState, SortType.level,
            Icons.format_list_numbered_rounded, 'Level'),
        sortMenuItem(
            context, songState, SortType.title, Icons.sort_by_alpha, 'Title'),
        sortMenuItem(context, songState, SortType.version,
            Icons.sports_esports_rounded, 'Version'),
      ],
    );
  }

  PopupMenuItem sortMenuItem(BuildContext context, SongState songState,
      SortType sortType, IconData icon, String label) {
    return menuListTileItem(
      title: label,
      leading: icon,
      checked: songState.sortType == sortType,
      onTap: () {
        songState.setSortType(sortType);
        onSorted?.call();
        showToast(context, "Sorted by ${label.toLowerCase()}");
        Navigator.pop(context);
      },
    );
  }
}
