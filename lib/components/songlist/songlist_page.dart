/// Name: SongListPage
/// Parent: DifficultyListPage
/// Description: Rendering out the song list page based on the
/// larger [difficulty] attribute from
library;

import 'package:ddr_md/components/songlist/difflist_page.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter/material.dart';

class SongListPage extends StatefulWidget {
  const SongListPage({super.key, required this.difficulty});

  final ListDifficulty difficulty;

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  late List<SongItem> songItems = [];
  void regenFavs() async {
    List<Favorite> favList = await DatabaseProvider.getAllFavorites();
    // Generate song list.
    for (SongItem songItem in songItems) {
      setState(() {
        songItem.isFav = favList.any((Favorite fav) =>
            fav.songTitle == songItem.songInfo.titletranslit);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    songItems = widget.difficulty.songList;
    regenFavs();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        child: Scaffold(
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
          itemCount: widget.difficulty.songList.length,
          prototypeItem: SongListItem(
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
}
