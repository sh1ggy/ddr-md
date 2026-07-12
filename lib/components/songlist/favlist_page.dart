/// Name: FavoriteListPage
/// Parent: DiffListPage
/// Description: Rendering out all favourite songs
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/components/songlist/sort_menu_button.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FavoriteListPage extends StatefulWidget {
  const FavoriteListPage({
    super.key,
  });

  @override
  State<FavoriteListPage> createState() => _FavoriteListPageState();
}

class _FavoriteListPageState extends State<FavoriteListPage> {
  List<Favorite>? favorites;
  Future<List<SongInfo>>? songInfoLoadingPromise;

  // Getting favourite items & returning future for list of SongInfo
  Future<List<SongInfo>> getFavSongInfoList() async {
    Modes mode = Provider.of<SongState>(context, listen: false).modes;
    List<Favorite>? favorites = await DatabaseProvider.getAllFavorites(mode);

    List<SongInfo> tempFavoriteSongList = [];
    for (Favorite fav in favorites) {
      // Skip favourites that no longer resolve against the loaded song list
      // instead of crashing the page on firstWhere.
      SongInfo? songInfo = Songs.list
          .where((SongInfo songInfo) => fav.songTitle == songInfo.titletranslit)
          .firstOrNull;
      if (songInfo != null) tempFavoriteSongList.add(songInfo);
    }
    return tempFavoriteSongList;
  }

  // Setting songInfo list promise.
  void genSongInfoList() async {
    setState(() {
      songInfoLoadingPromise = getFavSongInfoList();
    });
  }

  @override
  void initState() {
    super.initState();
    genSongInfoList(); // initialise favourite items
  }

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    return SafeArea(
        child: Scaffold(
            appBar: AppBar(
              surfaceTintColor: Colors.black,
              shadowColor: Colors.black,
              elevation: 2,
              centerTitle: true,
              title: const Text(
                "Favourites",
                style: TextStyle(
                    fontSize: 20,
                    color: Colors.blueGrey,
                    fontWeight: FontWeight.w600),
              ),
              actions: const <Widget>[SortMenuButton()],
              iconTheme: const IconThemeData(color: Colors.blueGrey),
            ),
            body: SingleChildScrollView(
              child: FutureBuilder(
                future: songInfoLoadingPromise,
                builder: (context, snapshot) {
                  List<Widget> children;
                  if (snapshot.hasData) {
                    if (snapshot.data!.isEmpty) {
                      return SizedBox(
                          height: MediaQuery.of(context).size.height / 1.5,
                          child: const Center(child: Text('No favourites...')));
                    }
                    List<SongInfo> favSongs = List.of(snapshot.data!);
                    if (songState.sortType != SortType.level) {
                      favSongs.sort(
                          (a, b) => compareSongInfo(a, b, songState.sortType));
                    }
                    children =
                        favSongs.map<SongListItem>((SongInfo songInfo) {
                      return SongListItem(
                        songInfo: songInfo,
                        isFav: true,
                        isSearch: false,
                        regenFavsCallback: genSongInfoList,
                      );
                    }).toList();
                  } else {
                    children = [
                      SizedBox(
                          height: MediaQuery.of(context).size.height / 1.5,
                          child: const Center(child: Text('Loading...'))),
                    ];
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: children,
                  );
                },
              ),
            )));
  }
}
