/// Name: SongPage
/// Parent: SongListPage
/// Description: Page that displays selected song information
library;

import 'package:ddr_md/components/song/notes/note_page.dart';
import 'package:ddr_md/components/song/song_chart.dart';
import 'package:ddr_md/components/song/song_details.dart';
import 'package:ddr_md/components/song/song_bpm.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class SongPage extends StatefulWidget {
  const SongPage({super.key});

  @override
  State<SongPage> createState() => _SongPageState();
}

class _SongPageState extends State<SongPage> {
  // Late initialisation of chart-related data
  late bool _isBpmChange;
  late Chart _chart;
  late int _chosenReadSpeed;
  late int _nearestModIndex;

  Favorite? favorite;
  Note? latestNote;

  void initFav(String songTitleTranslit) async {
    Favorite? initFav =
        await DatabaseProvider.getFavoriteBySong(songTitleTranslit);
    setState(() {
      favorite = initFav;
    });
  }

  void initNote(String songTitleTranslit) async {
    Note? initNote =
        await DatabaseProvider.getLatestNoteBySong(songTitleTranslit);
    setState(() {
      latestNote = initNote;
    });
  }

  // Initialise chosen read speed.
  @override
  void initState() {
    super.initState();
    _chosenReadSpeed = Settings.getInt(Settings.chosenReadSpeedKey);
  }

  // Latching onto when this class's dependencies change
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SongState songState = Provider.of<SongState>(context);
    SongInfo? songInfo = songState.songInfo;
    int chosenDifficulty = songState.chosenDifficulty;

    if (songInfo != null) {
      initFav(songInfo.titletranslit);
      initNote(songInfo.titletranslit);
      // Set variables based on state
      if (songInfo.perChart) {
        setState(() {
          _chart = songInfo.charts[chosenDifficulty];
        });
      } else {
        setState(() {
          // First index because no individual chart information
          _chart = songInfo.charts.first;
        });
      }
      setState(() {
        _isBpmChange = _chart.trueMax != _chart.trueMin;
        _nearestModIndex = findNearestReadSpeed(
            _chart.dominantBpm, constants.mods, _chosenReadSpeed);
      });
    }
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
                surfaceTintColor: Colors.black,
                shadowColor: Colors.black,
                elevation: 2,
                centerTitle: true,
                title: const Text(
                  "Song",
                  style: TextStyle(
                      fontSize: 20,
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.w600),
                ),
                iconTheme: const IconThemeData(color: Colors.blueGrey),
                actions: <Widget>[
                  IconButton(
                      icon: Icon(
                        favorite == null ? Icons.star_border : Icons.star,
                      ),
                      tooltip: favorite == null ? "Favourite" : "Unfavourite",
                      onPressed: () async {
                        HapticFeedback.lightImpact();
                        SongInfo? songStateInfo = songState.songInfo;
                        if (songStateInfo == null) {
                          return;
                        }
                        if (favorite == null) {
                          Favorite fav = Favorite(
                              id: 0,
                              isFav: true,
                              songTitle: songStateInfo.titletranslit);
                          await DatabaseProvider.addFavorite(fav);
                          setState(() {
                            favorite = fav;
                          });
                        } else {
                          await DatabaseProvider.deleteFavorite(favorite!);
                          setState(() {
                            favorite = null;
                          });
                        }
                        if (context.mounted) {
                          showToast(context, "Favourite updated");
                        }
                      }),
                  IconButton(
                    icon: const Icon(Icons.note_add),
                    tooltip: "Add note",
                    onPressed: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const NotePage()));
                      initNote(songState.songInfo!.titletranslit);
                    },
                  )
                ]),
            body: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  children: [
                    Text(
                      songState.songInfo!.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SongDetails(songInfo: songState.songInfo!, chart: _chart),
                    SongBpm(
                        nearestModIndex: _nearestModIndex,
                        isBpmChange: _isBpmChange,
                        chart: _chart),
                    if (_isBpmChange || _chart.stops.isNotEmpty)
                      SongChart(
                          context: context,
                          songInfo: songState.songInfo,
                          chart: _chart),
                    if (latestNote != null)
                      GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const NotePage()));
                          initNote(songState.songInfo!.titletranslit);
                        },
                        child: Card(
                          child: ListTile(
                            title: Column(
                              children: [
                                Text(
                                  "Latest Note",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                ),
                                Text(
                                  latestNote!.contents,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  formatDate(DateTime.parse(latestNote!.date)),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                ),
                              ]
                                  .expand(
                                      (x) => [const SizedBox(height: 10), x])
                                  .skip(1)
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                  ]
                      .expand((x) => [const SizedBox(height: 10), x])
                      .skip(1)
                      .toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// TODO: UNUSED
class NoteScore extends StatelessWidget {
  const NoteScore({super.key});

  @override
  Widget build(BuildContext context) => const Column(
        children: [
          Text(
            "Recent Score:",
            style: TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image(
                  image: AssetImage('assets/rank_s_aaa.png'),
                ),
                Image(
                  image: AssetImage('assets/full_mar.png'),
                ),
              ],
            ),
          ),
          Text(
            '1,000,000',
            style: TextStyle(fontFamily: 'Handel'),
          ),
        ],
      );
}
