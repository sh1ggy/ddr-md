import 'dart:convert';

import 'package:ddr_md/components/song/prevNote.dart';
import 'package:ddr_md/components/songJson.dart';
import 'package:ddr_md/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ddr_md/constants.dart' as Constants;

formattedTime({required int timeInSecond}) {
  int sec = timeInSecond % 60;
  int min = (timeInSecond / 60).floor();
  String minute = min.toString().length <= 1 ? "$min" : "$min";
  String second = sec.toString().length <= 1 ? "0$sec" : "$sec";
  return "$minute:$second";
}

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

  Future<void> readSongJson() async {
    final String response = await rootBundle.loadString('assets/888.json');
    final data = await json.decode(response);
    setState(() {
      songInfo = parseJson(response);
      isBpmChange = songInfo!.chart.trueMax != songInfo!.chart.trueMin;
    });
  }

  int findNearest(int avgBpm, List array) {
    var nearest = 0;
    array.asMap().entries.forEach((entry) {
      var i = entry.key;
      var a = array[i] * avgBpm;
      if (array[i] * avgBpm <= Constants.chosen_bpm + Constants.buffer) {
        nearest = i;
      }
    });
    return nearest;
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
    var appState = context.watch<MyAppState>();
    if (songInfo != null) {
      nearestModIndex = findNearest(songInfo!.chart.dominantBpm, appState.mods);
    }
    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
                title: const Text(
                  'Song',
                  style: TextStyle(fontSize: 15),
                ),
                actions: <Widget>[
                  IconButton(
                      icon: const Icon(Icons.format_list_numbered_rounded),
                      tooltip: "Add score",
                      onPressed: () {
                        print('add score');
                      }),
                  IconButton(
                      icon: const Icon(Icons.note_add),
                      tooltip: "Add note",
                      onPressed: () => Navigator.pushNamed(context, 'NotePage')),
                ]),
            body: Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  note(context),
                  if (songInfo != null) songDetails(),
                  if (songInfo != null && isBpmChange != null)
                    songBpm(appState, nearestModIndex),
                ]
                    .expand((x) => [const SizedBox(height: 20), x])
                    .skip(1)
                    .toList(),
              ),
            ),
          ),
        );
      }),
    );
  }

  Row songDetails() {
    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          const Image(
            image: AssetImage('assets/background.png'),
            height: 100,
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                songInfo!.name,
                softWrap: true,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                songInfo!.version,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 14.0,
                    color: Colors.black,
                  ),
                  children: <TextSpan>[
                    const TextSpan(
                        text: 'Length: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(
                        text: (formattedTime(
                                timeInSecond: songInfo!.songLength.toInt()) +
                            " min, ")),
                    const TextSpan(
                        text: 'BPM: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: songInfo!.chart.bpmRange),
                  ],
                ),
              ),
              Row(
                children: [
                  Text(
                    songInfo!.levels.single.beginner.toString(),
                    style: const TextStyle(
                        color: Colors.cyan, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    songInfo!.levels.single.easy.toString(),
                    style: const TextStyle(
                        color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    songInfo!.levels.single.medium.toString(),
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  Text(songInfo!.levels.single.hard.toString(),
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold)),
                  Text(songInfo!.levels.single.challenge.toString(),
                      style: const TextStyle(
                          color: Colors.purple, fontWeight: FontWeight.bold)),
                ]
                    .expand((x) => [const SizedBox(width: 10), x])
                    .skip(1)
                    .toList(),
              ),
            ],
          ),
        ]);
  }

  Container songBpm(MyAppState appState, int nearestModIndex) {
    return Container(
      padding: const EdgeInsets.all(7.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                  width: 50,
                  child: Text(
                    'Avg',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  )),
              const SizedBox(width: 30),
              if (isBpmChange!) ...[
                const SizedBox(
                    width: 50,
                    child: Text(
                      'Min',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    )),
                const SizedBox(width: 30),
                const SizedBox(
                    width: 50,
                    child: Text(
                      'Max',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    )),
                const SizedBox(width: 30),
              ],
              const SizedBox(
                  width: 50,
                  child: Text(
                    'Mod',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  )),
            ],
          ),
          SizedBox(
              height: MediaQuery.of(context).size.height / 9,
              child: ListWheelScrollView.useDelegate(
                onSelectedItemChanged: (index) {
                  setState(() {
                    selectedItemIndex = index;
                  });
                },
                physics: const FixedExtentScrollPhysics(),
                controller:
                    FixedExtentScrollController(initialItem: nearestModIndex),
                overAndUnderCenterOpacity: .5,
                itemExtent: 22,
                childDelegate: ListWheelChildListDelegate(
                  children: appState.mods.map<Widget>((e) {
                    var avg = e * songInfo!.chart.dominantBpm;
                    var min = e * songInfo!.chart.trueMin;
                    var max = e * songInfo!.chart.trueMax;
                    return Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          color: nearestModIndex == appState.mods.indexOf(e)
                              ? Colors.amberAccent
                              : Colors.white70),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 50, child: Text('$avg')),
                            if (isBpmChange!) ...[
                              SizedBox(width: 50, child: Text('$min')),
                              SizedBox(width: 50, child: Text('$max')),
                            ],
                            SizedBox(
                              width: 50,
                              child: Text('$e',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                          ]
                              .expand((x) => [const SizedBox(width: 30), x])
                              .skip(1)
                              .toList()),
                    );
                  }).toList(),
                ),
              )),
        ],
      ),
    );
  }
}
