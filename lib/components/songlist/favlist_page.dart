/// Name: FavoriteListPage
/// Parent: DiffListPage
/// Description: Rendering out all favourite songs
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';

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

  // Generate the list of favourite items and set the promise accordingly.
  void generateFavItems() async {
    List<Favorite>? favorites = await DatabaseProvider.getAllFavorites();

    List<SongInfo> tempFavoriteSongList = [];
    for (Favorite fav in favorites) {
      tempFavoriteSongList.add(Songs.list.firstWhere(
          (SongInfo songInfo) => fav.songTitle == songInfo.titletranslit));
    }
    setState(() {
      songInfoLoadingPromise = Future(() => tempFavoriteSongList);
    });
  }

  @override
  void initState() {
    super.initState();
    generateFavItems(); // initialise favourite items
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
              title: const Text(
                "Favourites",
                style: TextStyle(
                    fontSize: 20,
                    color: Colors.blueGrey,
                    fontWeight: FontWeight.w600),
              ),
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
                    children =
                        snapshot.data!.map<SongListItem>((SongInfo songInfo) {
                      return SongListItem(
                        songInfo: songInfo,
                        isFav: true,
                        isSearch: false,
                        regenFavsCallback: generateFavItems,
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
