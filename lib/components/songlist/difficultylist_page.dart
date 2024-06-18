/// Name: DifficultyListPage
/// Parent: Main
/// Description: Rendering out difficulty folders and preparing
/// song list and favourites list to pass to children widgets.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/favlist_page.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/components/songlist/songlist_page.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:provider/provider.dart';

class ListDifficulty {
  ListDifficulty({
    required this.value,
    this.isExpanded = false,
    required this.songItemList,
  });
  int value;
  bool isExpanded;
  List<SongItem> songItemList = [];
}

class SongItem {
  SongItem({
    required this.songInfo,
    required this.isFav,
  });

  SongInfo songInfo;
  bool isFav;
}

class DifficultyListPage extends StatefulWidget {
  const DifficultyListPage({super.key});
  @override
  State<DifficultyListPage> createState() => _DifficultyListPageState();
}

class _DifficultyListPageState extends State<DifficultyListPage> {
  Future<List<ListDifficulty>>? _songItemsPromise;
  final List<SongListItem> _searchResultWidgets = [];
  int favCount = 0;

  // Search result handler
  void getMatch(String value) {
    value = value.toLowerCase().trim();
    if (value == "") {
      setState(() {
        _searchResultWidgets.clear();
      });
      return;
    }
    _searchResultWidgets.clear();
    var songListItems = Songs.list
        .where((SongInfo song) =>
            song.title.toLowerCase().contains(value) ||
            song.titletranslit.toLowerCase().contains(value))
        .map((e) => SongListItem(
              songInfo: e,
              isFav: false,
              isSearch: true,
              regenFavsCallback: regenFavCount,
            ));
    setState(() {
      _searchResultWidgets.addAll(songListItems);
    });

    return;
  }

  // Populate difficulty folders
  List<ListDifficulty> difficultyList = List<ListDifficulty>.generate(
    constants.maxDifficulty,
    (index) {
      return (ListDifficulty(value: 1 + index, songItemList: []));
    },
  );

  void regenFavCount() async {
    List<Favorite> favList = await DatabaseProvider.getAllFavorites();
    setState(() {
      favCount = favList.length;
    });
  }

  Future<List<ListDifficulty>> generateSongItems(Modes mode) async {
    List<ListDifficulty> newDiffList = difficultyList;
    List<Favorite> favList = await DatabaseProvider.getAllFavorites();
    setState(() {
      favCount = favList.length;
    });

    // Clear list and regenerate if already exists
    if (newDiffList.first.songItemList.isNotEmpty) {
      for (var difficulty in newDiffList) {
        difficulty.songItemList.clear();
      }
    }

    // Generate song list.
    for (int i = 0; i < Songs.list.length; i++) {
      SongInfo song = Songs.list[i];
      Difficulty songDifficulty =
          mode == Modes.singles ? song.singles : song.doubles;

      for (var difficulty in newDiffList) {
        if (songDifficulty
            .toJson()
            .containsValue(difficulty.value.toDouble())) {
          difficulty.songItemList.add(SongItem(
              songInfo: song,
              isFav: favList.any((Favorite fav) {
                final isFav = fav.songTitle == song.titletranslit;
                return isFav;
              })));
        }
      }
    }

    return difficultyList;
  }

  @override
  void initState() {
    super.initState();
    SongState songState = Provider.of<SongState>(context, listen: false);
    _songItemsPromise =
        Future<List<ListDifficulty>>(() => generateSongItems(songState.modes));
  }

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              elevation: 2,
              title: const Text(
                'Songlist',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.blueGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: <Widget>[
                // TODO: Uncomment when sorting exists.
                // PopupMenuButton(
                //   initialValue: 0,
                //   tooltip: "Sort",
                //   icon: const Icon(Icons.sort),
                //   itemBuilder: (BuildContext context) => <PopupMenuEntry>[
                //     const PopupMenuItem(
                //       child: ListTile(
                //         leading: Icon(Icons.sort_by_alpha),
                //         title: Text('Alphabetical'),
                //       ),
                //     ),
                //     const PopupMenuItem(
                //       child: ListTile(
                //         leading: Icon(Icons.sports_esports_rounded),
                //         title: Text('Version'),
                //       ),
                //     ),
                //     const PopupMenuItem(
                //       child: ListTile(
                //         leading: Icon(Icons.not_interested_rounded),
                //         title: Text('None'),
                //       ),
                //     ),
                //   ],
                // ),
                PopupMenuButton(
                  initialValue: 0,
                  tooltip: "Chart Type",
                  icon: const Icon(Icons.swap_vert),
                  itemBuilder: (BuildContext context) => <PopupMenuEntry>[
                    PopupMenuItem(
                      padding: const EdgeInsets.all(0),
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 8, right: 8),
                        hoverColor: Colors.transparent,
                        onTap: () {
                          songState.setMode(Modes.singles);
                          generateSongItems(Modes.singles);
                          showToast(context, "Set mode to singles");
                          Navigator.pop(context);
                          return;
                        },
                        leading: const Icon(Icons.looks_one_rounded),
                        title: const Text('Singles'),
                      ),
                    ),
                    PopupMenuItem(
                      padding: const EdgeInsets.all(0),
                      child: ListTile(
                        hoverColor: Colors.transparent,
                        contentPadding:
                            const EdgeInsets.only(left: 8, right: 8),
                        onTap: () {
                          songState.setMode(Modes.doubles);
                          generateSongItems(Modes.doubles);
                          showToast(context, "Set mode to doubles");
                          Navigator.pop(context);
                          return;
                        },
                        leading: const Icon(Icons.looks_two_rounded),
                        title: const Text('Doubles'),
                      ),
                    ),
                  ],
                ),
              ],
              iconTheme: const IconThemeData(color: Colors.blueGrey),
            ),
            body: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return <Widget>[
                  songSearchBar(),
                ];
              },
              body: CustomScrollView(
                  slivers: <Widget>[songList(songState, context)]),
            ),
          ),
        );
      }),
    );
  }

  SliverList songList(SongState songState, BuildContext context) {
    return SliverList(
        delegate: SliverChildListDelegate([
      FutureBuilder(
        future: _songItemsPromise,
        builder: (context, snapshot) {
          List<Widget> difficultyFolders = [];
          if (snapshot.hasData) {
            difficultyFolders.add(
              ListTile(
                title: RichText(
                  text: TextSpan(
                    text: 'Favourites: ',
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge!.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 22),
                    children: <TextSpan>[
                      TextSpan(
                          text: '$favCount song${favCount == 1 ? 's' : ''}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 19,
                              color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const FavoriteListPage()));
                  generateSongItems(songState.modes);
                },
              ),
            );
            difficultyFolders.addAll(
                snapshot.data!.map<ListTile>((ListDifficulty difficulty) {
              return ListTile(
                title: RichText(
                  text: TextSpan(
                    text: 'Level ${difficulty.value}: ',
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge!.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 22),
                    children: <TextSpan>[
                      TextSpan(
                          text: '${difficulty.songItemList.length} songs',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 19,
                              color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => SongListPage(
                                difficulty: difficulty,
                              )));
                  generateSongItems(songState.modes);
                },
              );
            }).toList());
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: difficultyFolders,
          );
        },
      ),
    ]));
  }

  SliverAppBar songSearchBar() {
    return SliverAppBar(
      floating: true,
      pinned: true,
      backgroundColor: Colors.transparent,
      flexibleSpace: SearchAnchor(
          isFullScreen: true,
          viewOnSubmitted: (value) {
            FocusScope.of(context).unfocus();
          },
          viewOnChanged: (value) => getMatch(value),
          viewHintText: "Search song...",
          builder: (BuildContext context, SearchController controller) {
            return SearchBar(
              controller: controller,
              onTap: () {
                controller.openView();
              },
              onChanged: (value) {
                controller.openView();
                getMatch(value);
              },
              hintText: "Search song...",
              constraints: const BoxConstraints(
                  minWidth: 360.0, maxWidth: 800.0, minHeight: 56.0),
              shape: WidgetStateProperty.all(const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              )),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(vertical: 5.0, horizontal: 20.0),
              ),
              leading: const Icon(Icons.search),
            );
          },
          suggestionsBuilder:
              (BuildContext context, SearchController controller) {
            if (_searchResultWidgets.isEmpty || controller.text == "") {
              return List.empty();
            }
            return _searchResultWidgets;
          }),
    );
  }
}
