/// Name: SongPage
/// Parent: Main
/// Description: Page that displays selected song information
library;

import 'package:ddr_md/components/song/notes/note_page.dart';
import 'package:ddr_md/components/song/notes/prev_note.dart';
import 'package:ddr_md/components/song/song_chart.dart';
import 'package:ddr_md/components/song/song_details.dart';
import 'package:ddr_md/components/song/song_bpm.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/main.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ddr_md/constants.dart' as constants;

class SongPage extends StatefulWidget {
  const SongPage({super.key});

  @override
  State<SongPage> createState() => _SongPageState();
}

class _SongPageState extends State<SongPage> {
  SongInfo? songInfo;
  double mod = 1.0;
  bool? isBpmChange;
  int selectedItemIndex = 0;
  int nearestModIndex = 0;
  List<FlSpot> songBpmSpots = [];
  List<FlSpot> songStopSpots = [];
  Chart? chart;

  Future<void> readSongJson() async {
    final String response =
        await rootBundle.loadString('assets/aceforaces.json');
    setState(() {
      songInfo = parseJson(response);
      if (!songInfo!.perChart) {
        chart = songInfo!.chart[0];
      } else {
        // TODO: better logic dependent on which difficulty is selected
        chart = songInfo!.chart[songInfo!.chart.length - 1];
      }
      isBpmChange = chart!.trueMax != chart!.trueMin;
    });
  }

  int findNearestBpm(int avgBpm, List array) {
    var nearest = 0;
    array.asMap().entries.forEach((entry) {
      var i = entry.key;
      var a = array[i] * avgBpm;
      if (array[i] * avgBpm <= constants.chosenBpm + constants.buffer) {
        nearest = i;
      }
    });
    return nearest;
  }

  int findNearest(double st, List array) {
    var nearest = 0;
    array.asMap().entries.forEach((entry) {
      var i = entry.key;
      Bpm a = array[i];
      if (a.st <= st) {
        nearest = a.val;
        return;
      }
    });
    return nearest;
  }

  void genBpmPoints() {
    List<Bpm> bpms = chart!.bpms;
    if (songBpmSpots.isNotEmpty)
      return; // TODO: remove this when doing dynamic songData

    for (int i = 0; i < bpms.length; i++) {
      songBpmSpots.add(FlSpot(bpms[i].st, bpms[i].val.toDouble()));
      songBpmSpots.add(FlSpot(bpms[i].ed, bpms[i].val.toDouble()));
    }
    for (int i = 0; i < chart!.stops.length; i++) {
      double nearestBpm = findNearest(chart!.stops[i].st, bpms).toDouble();
      print(nearestBpm);
      print(chart!.stops[i].st);
      songStopSpots.add(FlSpot(chart!.stops[i].st, nearestBpm));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      readSongJson();
    });
    // SchedulerBinding.instance.addPostFrameCallback((_) {
    //   print("SchedulerBinding");
    // });
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<AppState>();
    if (songInfo != null) {
      nearestModIndex = findNearestBpm(chart!.dominantBpm, appState.mods);
      genBpmPoints();
    }
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
                      icon: const Icon(
                        Icons.format_list_numbered_rounded,
                      ),
                      tooltip: "Add score",
                      onPressed: () {
                        print('add score');
                      }),
                  IconButton(
                    icon: const Icon(Icons.note_add),
                    tooltip: "Add note",
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const NotePage())),
                  )
                ]),
            body: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  children: [
                    const PrevNote(),
                    if (songInfo != null)
                      SongDetails(songInfo: songInfo!, chart: chart),
                    if (songInfo != null && isBpmChange != null) ...[
                      SongBpm(nearestModIndex: nearestModIndex, isBpmChange: isBpmChange, chart: chart),
                      SongChart(
                          songBpmSpots: songBpmSpots,
                          songStopSpots: songStopSpots,
                          context: context,
                          songInfo: songInfo,
                          chart: chart),
                    ]
                  ]
                      .expand((x) => [const SizedBox(height: 20), x])
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
