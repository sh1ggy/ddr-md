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

  final List<Difficulty> difficulties = List<Difficulty>.generate(
    constants.maxDifficulty,
    (index) {
      return (Difficulty(value: 1 + index, songList: []));
    },
  );

  Future<List<Difficulty>> generateSongItems() async {
    for (int i = 0; i < Songs.list.length; i++) {
      for (var difficulty in difficulties) {
        if (Songs.list[i].levels.single
            .toJson()
            .containsValue(difficulty.value.toDouble())) {
          difficulty.songList.add(Songs.list[i]);
        }
      }
    }
    return difficulties;
  }

  final List<SongListItem> _searchResultWidgets = [];

  void getMatch(String value) {
    setState(() {
      value = value.toLowerCase().trim();
      if (value == "") {
        print(_searchResultWidgets.isEmpty);
        _searchResultWidgets.clear();
        return;
      }

      _searchResultWidgets.clear();
      List<SongInfo> filteredSongList = Songs.list
          .where((SongInfo song) =>
              song.title.toLowerCase().contains(value) ||
              song.titletranslit.toLowerCase().contains(value))
          .toList();
      for (SongInfo song in filteredSongList) {
        _searchResultWidgets.add(SongListItem(songInfo: song));
      }
      return;
    });
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
            children = <Widget>[const Text('Loading...')];
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
            if (_searchResultWidgets.isEmpty || controller.text == "")
              return List.empty();
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
            prototypeItem: SongListItem(songInfo: difficulty.songList.first),
            itemBuilder: (context, index) {
              return SongListItem(songInfo: difficulty.songList[index]);
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
