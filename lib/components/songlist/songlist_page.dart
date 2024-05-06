/// Name: SettingsPage
/// Parent: Main
/// Description: Settings page for use with shared_preferences
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ddr_md/constants.dart' as constants;

class SonglistPage extends StatefulWidget {
  const SonglistPage({super.key});
  @override
  State<SonglistPage> createState() => _SonglistPageState();
}

// stores ExpansionPanel state information
class SongEntry {
  SongEntry({
    required this.expandedValue,
    required this.songInfo,
  });

  String expandedValue;
  SongInfo songInfo;
}

class Difficulty {
  Difficulty({
    required this.value,
    this.isExpanded = false,
    required this.songList,
  });
  int value;
  bool isExpanded;
  List<SongEntry> songList = [];
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
    SongInfo? songInfo;

    AssetBundle bundle = DefaultAssetBundle.of(context);
    AssetManifest asset = await AssetManifest.loadFromAssetBundle(bundle);
    List<String> assets = asset.listAssets();
    List<String> songDataPaths = assets
        .where((string) => string.startsWith("assets/song-data/"))
        .where((string) => string.endsWith(".json"))
        .map((e) => e.substring(0, e.length - 5))
        .toList();

    for (int i = 0; i < songDataPaths.length; i++) {
      var response = await rootBundle.loadString('${songDataPaths[i]}.json');
      songInfo = parseJson(response);

      for (var difficulty in difficulties) {
        if (songInfo.levels.single
            .toJson()
            .containsValue(difficulty.value.toDouble())) {
          difficulty.songList.add((SongEntry(
            expandedValue: 'This is item number $i',
            songInfo: songInfo,
          )));
        }
      }
    }

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
              iconTheme: const IconThemeData(color: Colors.blueGrey),
            ),
            body: CustomScrollView(
              slivers: <Widget>[
                SliverAppBar(
                  floating: true,
                  
                  backgroundColor: Colors.transparent,
                  flexibleSpace: SearchBar(
                    hintText: "Search song...",
                    constraints: const BoxConstraints(
                        minWidth: 360.0, maxWidth: 800.0, minHeight: 56.0),
                    shape:
                        MaterialStateProperty.all(const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    )),
                    padding: MaterialStateProperty.all(
                      const EdgeInsets.symmetric(
                          vertical: 5.0, horizontal: 20.0),
                    ),
                    leading: const Icon(Icons.search),
                  ),
                ),
                SliverList(
                    delegate: SliverChildListDelegate([
                  FutureBuilder(
                    future: _songItemsPromise,
                    builder: (context, snapshot) {
                      List<Widget> children;
                      if (snapshot.hasData) {
                        children = snapshot.data!
                            .map<ListTile>((Difficulty difficulty) {
                          return ListTile(
                            title: RichText(
                              text: TextSpan(
                                text: 'Level ${difficulty.value}: ',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                children: <TextSpan>[
                                  TextSpan(
                                      text:
                                          '${difficulty.songList.length} songs',
                                      style: TextStyle(fontWeight: FontWeight.normal,
                                           fontSize: 16, color: Colors.grey.shade400)),
                                ],
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => {
                              Navigator.push(
                                  context, difficultyList(difficulty))
                            },
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
                ]))
              ],
            ),
          ),
        );
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
            prototypeItem:
                SongListItem(songInfo: difficulty.songList.first.songInfo),
            itemBuilder: (context, index) {
              return SongListItem(
                  songInfo: difficulty.songList[index].songInfo);
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
