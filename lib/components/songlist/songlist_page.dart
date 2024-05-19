/// Name: SettingsPage
/// Parent: Main
/// Description: Settings page for use with shared_preferences
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;

class SonglistPage extends StatefulWidget {
  const SonglistPage({super.key});
  @override
  State<SonglistPage> createState() => _SonglistPageState();
}

class Difficulty {
  Difficulty({
    required this.value,
    this.isExpanded = false,
    required this.songList,
  });
  int value;
  bool isExpanded;
  List<SongInfo> songList = [];
}

class _SonglistPageState extends State<SonglistPage> {
  Future<List<Difficulty>>? _songItemsPromise;
  final List<SongListItem> _searchResultWidgets = [];

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
              isSearch: true,
            ));
    setState(() {
      _searchResultWidgets.addAll(songListItems);
    });

    return;
  }

  // Generate difficulty list to 19.
  List<Difficulty> difficulties = List<Difficulty>.generate(
    constants.maxDifficulty,
    (index) {
      return (Difficulty(value: 1 + index, songList: []));
    },
  );

  // Populate difficulty folders
  // TODO: switch between doubles
  Future<List<Difficulty>> generateSongItems() async {
    List<Difficulty> newDiffList = difficulties;
    for (int i = 0; i < Songs.list.length; i++) {
      for (var difficulty in newDiffList) {
        // Map<String,dynamic> difficulties = Songs.list[i].mode.singles.toJson();
        if (Songs.list[i].levels.single
            .toJson()
            .containsValue(difficulty.value.toDouble())) {
          difficulty.songList.add(Songs.list[i]);
        }
      }
    }
    setState(() {
      difficulties = newDiffList;
    });
    return difficulties;
  }

  @override
  void initState() {
    super.initState();
    _songItemsPromise = Future<List<Difficulty>>(() => generateSongItems());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              surfaceTintColor: Colors.black,
              shadowColor: Colors.black,
              title: const Text(
                'Songlist',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.blueGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: <Widget>[
                PopupMenuButton(
                  initialValue: 0,
                  tooltip: "Sort",
                  icon: const Icon(Icons.sort),
                  itemBuilder: (BuildContext context) => <PopupMenuEntry>[
                    const PopupMenuItem(
                      child: ListTile(
                        leading: Icon(Icons.sort_by_alpha),
                        title: Text('Alphabetical'),
                      ),
                    ),
                    const PopupMenuItem(
                      child: ListTile(
                        leading: Icon(Icons.sports_esports_rounded),
                        title: Text('Version'),
                      ),
                    ),
                    const PopupMenuItem(
                      child: ListTile(
                        leading: Icon(Icons.not_interested_rounded),
                        title: Text('None'),
                      ),
                    ),
                  ],
                ),
                PopupMenuButton(
                  initialValue: 0,
                  tooltip: "Chart Type",
                  icon: const Icon(Icons.swap_vert),
                  itemBuilder: (BuildContext context) => <PopupMenuEntry>[
                    const PopupMenuItem(
                      child: ListTile(
                        leading: Icon(Icons.looks_one_rounded),
                        title: Text('Singles'),
                      ),
                    ),
                    const PopupMenuItem(
                      child: ListTile(
                        leading: Icon(Icons.looks_two_rounded),
                        title: Text('Doubles'),
                      ),
                    ),
                  ],
                ),
              ],
              iconTheme: const IconThemeData(color: Colors.blueGrey),
            ),
            body: CustomScrollView(
              slivers: <Widget>[songSearchBar(), songList()],
            ),
          ),
        );
      }),
    );
  }

  SliverList songList() {
    return SliverList(
        delegate: SliverChildListDelegate([
      FutureBuilder(
        future: _songItemsPromise,
        builder: (context, snapshot) {
          List<Widget> children;
          if (snapshot.hasData) {
            children = snapshot.data!.map<ListTile>((Difficulty difficulty) {
              return ListTile(
                title: RichText(
                  text: TextSpan(
                    text: 'Level ${difficulty.value}: ',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                    children: <TextSpan>[
                      TextSpan(
                          text: '${difficulty.songList.length} songs',
                          style: TextStyle(
                              fontWeight: FontWeight.normal,
                              fontSize: 16,
                              color: Colors.grey.shade400)),
                    ],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    {Navigator.push(context, difficultyList(difficulty))},
              );
            }).toList();
          } else {
            children = [];
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: children,
          );
        },
      ),
    ]));
  }

  SliverAppBar songSearchBar() {
    return SliverAppBar(
      floating: true,
      backgroundColor: Colors.transparent,
      flexibleSpace: SearchAnchor(
          isFullScreen: true,
          viewOnChanged: (value) => getMatch(value),
          viewHintText: "Search song...",
          builder: (BuildContext context, SearchController controller) {
            return SearchBar(
              controller: controller,
              onTap: () {
                controller.openView();
              },
              onChanged: (_) {
                controller.openView();
              },
              hintText: "Search song...",
              constraints: const BoxConstraints(
                  minWidth: 360.0, maxWidth: 800.0, minHeight: 56.0),
              shape: MaterialStateProperty.all(const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              )),
              padding: MaterialStateProperty.all(
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

  MaterialPageRoute<dynamic> difficultyList(Difficulty difficulty) {
    return MaterialPageRoute(
      builder: (context) => SafeArea(
          child: Scaffold(
        appBar: AppBar(
          surfaceTintColor: Colors.black,
          shadowColor: Colors.black,
          elevation: 2,
          centerTitle: true,
          title: Text(
            "Level ${difficulty.value}",
            style: const TextStyle(
                fontSize: 20,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600),
          ),
          iconTheme: const IconThemeData(color: Colors.blueGrey),
        ),
        body: ListView.builder(
            scrollDirection: Axis.vertical,
            itemCount: difficulty.songList.length,
            prototypeItem: SongListItem(
              songInfo: difficulty.songList.first,
              isSearch: false,
            ),
            itemBuilder: (context, index) {
              return SongListItem(
                songInfo: difficulty.songList[index],
                isSearch: false,
              );
            }),
      )),
    );
  }

  void showToast(BuildContext context, String message) {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
            label: 'DISMISS', onPressed: scaffold.hideCurrentSnackBar),
      ),
    );
  }
}
