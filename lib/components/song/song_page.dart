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
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ddr_md/constants.dart' as constants;

class SongPage extends StatefulWidget {
  const SongPage({super.key});

  @override
  State<SongPage> createState() => _SongPageState();
}

class _SongPageState extends State<SongPage> {
  SongInfo? _songInfo;
  bool? _isBpmChange;
  int _nearestModIndex = 0;
  final List<FlSpot> _songBpmSpots = [];
  final List<FlSpot> _songStopSpots = [];
  Chart? _chart;

  Future<void> readSongJson() async {
    final String response =
        await rootBundle.loadString('assets/chaosterror.json');
    setState(() {
      _songInfo = parseJson(response);
      if (!_songInfo!.perChart) {
        _chart = _songInfo!.chart[0];
      } else {
        // TODO: better logic dependent on which difficulty is selected
        _chart = _songInfo!.chart[_songInfo!.chart.length - 1];
      }
      _isBpmChange = _chart!.trueMax != _chart!.trueMin;
    });
  }

  int findNearestBpm(int avgBpm, List array) {
    var nearest = 0;
    array.asMap().entries.forEach((entry) {
      var i = entry.key;
      // var a = array[i] * avgBpm; // BPM
      if (array[i] * avgBpm <= constants.chosenReadSpeed + constants.buffer) {
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
    List<Bpm> bpms = _chart!.bpms;
    if (_songBpmSpots.isNotEmpty)
      return; // TODO: remove this when doing dynamic songData

    for (int i = 0; i < bpms.length; i++) {
      _songBpmSpots.add(FlSpot(bpms[i].st, bpms[i].val.toDouble()));
      _songBpmSpots.add(FlSpot(bpms[i].ed, bpms[i].val.toDouble()));
    }
    for (int i = 0; i < _chart!.stops.length; i++) {
      double nearestBpm = findNearest(_chart!.stops[i].st, bpms).toDouble();
      _songStopSpots.add(FlSpot(_chart!.stops[i].st, nearestBpm));
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
    if (_songInfo != null) {
      _nearestModIndex = findNearestBpm(_chart!.dominantBpm, constants.mods);
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
                    if (_songInfo != null)
                      SongDetails(songInfo: _songInfo!, chart: _chart),
                    if (_songInfo != null && _isBpmChange != null) ...[
                      SongBpm(
                          nearestModIndex: _nearestModIndex,
                          isBpmChange: _isBpmChange,
                          chart: _chart),
                      SongChart(
                          songBpmSpots: _songBpmSpots,
                          songStopSpots: _songStopSpots,
                          context: context,
                          songInfo: _songInfo,
                          chart: _chart),
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
