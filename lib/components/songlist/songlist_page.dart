/// Name: SongListPage
/// Parent: DifficultyListPage
/// Description: Rendering out the song list page based on the
/// larger [difficulty] attribute from
library;

import 'package:ddr_md/components/songlist/difficultylist_page.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/navigation_model.dart';
import 'package:ddr_md/navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SongListPage extends StatefulWidget {
  const SongListPage({super.key, required this.difficulty});

  final ListDifficulty difficulty;

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  void regenFavs() async {
    List<Favorite> favList = await DatabaseProvider.getAllFavorites();
    // Initialise temp value
    List<SongItem> newSongItems = widget.difficulty.songItemList;
    for (SongItem songItem in newSongItems) {
      songItem.isFav = favList.any(
          (Favorite fav) => fav.songTitle == songItem.songInfo.titletranslit);
    }
    // Updating parent state passed from props
    setState(() {
      widget.difficulty.songItemList = newSongItems;
    });
  }

  @override
  void initState() {
    super.initState();
    regenFavs();
  }

  @override
  Widget build(BuildContext context) {
    var navigationState = context.watch<NavigationState>();
    return SafeArea(
        child: Scaffold(
      bottomNavigationBar: LayoutNavigationBar(
        navigationState: navigationState,
      ),
      appBar: AppBar(
        surfaceTintColor: Colors.black,
        shadowColor: Colors.black,
        elevation: 2,
        centerTitle: true,
        title: Text(
          "Level ${widget.difficulty.value}",
          style: const TextStyle(
              fontSize: 20,
              color: Colors.blueGrey,
              fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.blueGrey),
      ),
      body: ListView.builder(
          scrollDirection: Axis.vertical,
          itemCount: widget.difficulty.songItemList.length,
          prototypeItem: SongListItem(
            songInfo: widget.difficulty.songItemList.first.songInfo,
            isFav: widget.difficulty.songItemList.first.isFav,
            isSearch: false,
            regenFavsCallback: regenFavs,
          ),
          itemBuilder: (context, index) {
            return SongListItem(
              songInfo: widget.difficulty.songItemList[index].songInfo,
              isFav: widget.difficulty.songItemList[index].isFav,
              isSearch: false,
              regenFavsCallback: regenFavs,
            );
          }),
    ));
  }
}
