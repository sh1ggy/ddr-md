/// Name: SongListPage
/// Parent: DifficultyListPage
/// Description: Rendering out the song list page based on the
/// larger [folder] attribute from
library;

import 'package:ddr_md/components/songlist/difficultylist_page.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter/material.dart';

class SongListPage extends StatefulWidget {
  const SongListPage(
      {super.key, required this.folder, this.enableVersionFilter = true});

  final SongFolder folder;
  final bool enableVersionFilter;

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  String? _versionFilter;

  // Distinct versions present in this folder, in release order.
  List<String> folderVersions() {
    List<String> versions = widget.folder.songItemList
        .map((SongItem songItem) => songItem.songInfo.version)
        .toSet()
        .toList();
    versions.sort((a, b) => versionIndex(a).compareTo(versionIndex(b)));
    return versions;
  }

  void regenFavs() async {
    List<Favorite> favList = await DatabaseProvider.getAllFavorites();
    // Initialise temp value
    List<SongItem> newSongItems = widget.folder.songItemList;
    for (SongItem songItem in newSongItems) {
      songItem.isFav = favList.any(
          (Favorite fav) => fav.songTitle == songItem.songInfo.titletranslit);
    }
    // Updating parent state passed from props
    setState(() {
      widget.folder.songItemList = newSongItems;
    });
  }

  @override
  void initState() {
    super.initState();
    regenFavs();
  }

  @override
  Widget build(BuildContext context) {
    List<SongItem> songItems = widget.enableVersionFilter
      ? widget.folder.songItemList
        .where((SongItem songItem) =>
          _versionFilter == null ||
          songItem.songInfo.version == _versionFilter)
        .toList()
      : widget.folder.songItemList;
    return SafeArea(
        child: Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.black,
        shadowColor: Colors.black,
        elevation: 2,
        centerTitle: true,
        title: Text(
          widget.folder.name,
          style: const TextStyle(
              fontSize: 20,
              color: Colors.blueGrey,
              fontWeight: FontWeight.w600),
        ),
        actions: widget.enableVersionFilter
            ? <Widget>[
                PopupMenuButton(
                  tooltip: "Filter by version",
                  icon: Icon(_versionFilter == null
                      ? Icons.filter_alt_outlined
                      : Icons.filter_alt),
                  itemBuilder: (BuildContext context) => <PopupMenuEntry>[
                    versionFilterItem(null),
                    for (String version in folderVersions())
                      versionFilterItem(version),
                  ],
                ),
              ]
            : null,
        iconTheme: const IconThemeData(color: Colors.blueGrey),
      ),
      body: ListView.builder(
          scrollDirection: Axis.vertical,
          itemCount: songItems.length,
          prototypeItem: songItems.isEmpty
              ? null
              : SongListItem(
                  songInfo: songItems.first.songInfo,
                  isFav: songItems.first.isFav,
                  isSearch: false,
                  regenFavsCallback: regenFavs,
                ),
          itemBuilder: (context, index) {
            return SongListItem(
              songInfo: songItems[index].songInfo,
              isFav: songItems[index].isFav,
              isSearch: false,
              regenFavsCallback: regenFavs,
            );
          }),
    ));
  }

  PopupMenuItem versionFilterItem(String? version) {
    return menuListTileItem(
      title: version ?? 'All versions',
      checked: _versionFilter == version,
      onTap: () {
        setState(() => _versionFilter = version);
        Navigator.pop(context);
      },
    );
  }
}
