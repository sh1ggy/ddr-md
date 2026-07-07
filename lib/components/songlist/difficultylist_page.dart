/// Name: DifficultyListPage
/// Parent: Main
/// Description: Rendering out difficulty folders and preparing
/// song list and favourites list to pass to children widgets.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/favlist_page.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/components/songlist/songlist_page.dart';
import 'package:ddr_md/components/songlist/sort_menu_button.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:provider/provider.dart';

class SongFolder {
  SongFolder({
    required this.name,
    required this.songItemList,
  });
  String name;
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
  Future<List<SongFolder>>? _songItemsPromise;
  final List<SongInfo> _searchResults = [];
  int favCount = 0;

  // Search result handler; widgets are built lazily in suggestionsBuilder.
  void getMatch(String value) {
    value = value.toLowerCase().trim();
    setState(() {
      _searchResults.clear();
      if (value == "") return;
      _searchResults.addAll(Songs.list.where((SongInfo song) =>
          song.title.toLowerCase().contains(value) ||
          song.titletranslit.toLowerCase().contains(value)));
    });
  }

  void regenFavCount() async {
    List<Favorite> favList = await DatabaseProvider.getAllFavorites();
    setState(() {
      favCount = favList.length;
    });
  }

  // First letter of the (romaji) title, so Japanese titles bucket in with
  // their romaji equivalent; anything not A-Z goes under '#'.
  String titleBucket(SongInfo song) {
    String title = (song.titletranslit.isNotEmpty ? song.titletranslit : song.title)
        .trim();
    if (title.isEmpty) return '#';
    String first = title[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
  }

  Future<List<SongFolder>> generateFolders(Modes mode, SortType sortType) async {
    List<Favorite> favList = await DatabaseProvider.getAllFavorites();
    setState(() {
      favCount = favList.length;
    });

    // Bucket every song into folders keyed by the chosen sort: one folder
    // per level (a song repeats for each distinct level it has in the
    // chosen mode), per first title letter, or per game version.
    Map<String, SongFolder> folders = {};
    if (sortType == SortType.level) {
      for (int i = 1; i <= constants.maxDifficulty; i++) {
        folders['Level $i'] = SongFolder(name: 'Level $i', songItemList: []);
      }
    }
    for (SongInfo song in Songs.list) {
      bool isFav =
          favList.any((Favorite fav) => fav.songTitle == song.titletranslit);

      List<String> names = [];
      switch (sortType) {
        case SortType.level:
          Difficulty songDifficulty =
              mode == Modes.singles ? song.singles : song.doubles;
          for (int? level in {
            songDifficulty.beginner,
            songDifficulty.easy,
            songDifficulty.medium,
            songDifficulty.hard,
            songDifficulty.challenge,
          }) {
            if (level == null || level < 1 || level > constants.maxDifficulty) {
              continue;
            }
            names.add('Level $level');
          }
          break;
        case SortType.title:
          names.add(titleBucket(song));
          break;
        case SortType.version:
          names.add(song.version);
          break;
      }
      for (String name in names) {
        folders
            .putIfAbsent(name, () => SongFolder(name: name, songItemList: []))
            .songItemList
            .add(SongItem(songInfo: song, isFav: isFav));
      }
    }

    List<SongFolder> folderList = folders.values.toList();
    switch (sortType) {
      case SortType.level:
        break; // Already inserted in level order.
      case SortType.title:
        // Alphabetical folders, with the '#' catch-all last.
        folderList.sort((a, b) => a.name == '#'
            ? 1
            : b.name == '#'
                ? -1
                : a.name.compareTo(b.name));
        break;
      case SortType.version:
        folderList.sort(
            (a, b) => versionIndex(a.name).compareTo(versionIndex(b.name)));
        break;
    }
    // Alphabetical contents for title/version folders; level folders keep
    // the master list's order.
    if (sortType != SortType.level) {
      for (SongFolder folder in folderList) {
        folder.songItemList.sort(
            (a, b) => compareSongInfo(a.songInfo, b.songInfo, SortType.title));
      }
    }
    return folderList;
  }

  void regenFolders(Modes mode, SortType sortType) {
    setState(() {
      _songItemsPromise = generateFolders(mode, sortType);
    });
  }

  @override
  void initState() {
    super.initState();
    SongState songState = Provider.of<SongState>(context, listen: false);
    _songItemsPromise = Future<List<SongFolder>>(
        () => generateFolders(songState.modes, songState.sortType));
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
                SortMenuButton(
                    onSorted: () =>
                        regenFolders(songState.modes, songState.sortType)),
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
                          regenFolders(Modes.singles, songState.sortType);
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
                          regenFolders(Modes.doubles, songState.sortType);
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
                          text: '$favCount song${favCount == 1 ? '' : 's'}',
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
                  regenFolders(songState.modes, songState.sortType);
                },
              ),
            );
            difficultyFolders
                .addAll(snapshot.data!.map<ListTile>((SongFolder folder) {
              return ListTile(
                title: RichText(
                  text: TextSpan(
                    text: '${folder.name}: ',
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge!.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 22),
                    children: <TextSpan>[
                      TextSpan(
                          text:
                              '${folder.songItemList.length} song${folder.songItemList.length == 1 ? '' : 's'}',
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
                                folder: folder,
                              )));
                  regenFolders(songState.modes, songState.sortType);
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
            if (_searchResults.isEmpty || controller.text == "") {
              return List.empty();
            }
            return _searchResults.map((song) => SongListItem(
                  songInfo: song,
                  isFav: false,
                  isSearch: true,
                  regenFavsCallback: regenFavCount,
                ));
          }),
    );
  }
}
