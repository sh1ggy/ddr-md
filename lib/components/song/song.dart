import 'dart:convert';

import 'package:ddr_md/components/song/note.dart';
import 'package:ddr_md/components/songJson.dart';
import 'package:ddr_md/main.dart';
import 'package:flutter/material.dart';
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

  Future<void> readSongJson() async {
    final String response = await rootBundle.loadString('assets/888.json');
    final data = await json.decode(response);
    setState(() {
      songInfo = parseJson(response);
      isBpmChange = songInfo!.chart.trueMax != songInfo!.chart.trueMin;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (mounted) {
      readSongJson();
    }
    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            body: Column(
              children: [
                note(),
                if (songInfo != null) songDetails(),
                if (songInfo != null && isBpmChange != null) songBpm(),
              ].expand((x) => [const SizedBox(height: 20), x]).skip(1).toList(),
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

  Container songBpm() {
    var appState = context.watch<MyAppState>();
    var avgBpm = songInfo!.chart.dominantBpm;
    // TODO: find better way to do this
    final nearestSmaller = appState.mods.reduce((a, b) =>
        (a * avgBpm - Constants.chosen_bpm).abs() <=
                (b * avgBpm - Constants.chosen_bpm).abs()
            ? a
            : b);
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
                controller: FixedExtentScrollController(
                    initialItem: appState.mods.indexOf(nearestSmaller)),
                overAndUnderCenterOpacity: .5,
                itemExtent: 22,
                childDelegate: ListWheelChildListDelegate(
                  children: appState.mods.map<Widget>((e) {
                    var avg = e * songInfo!.chart.dominantBpm;
                    var min = e * songInfo!.chart.trueMin;
                    var max = e * songInfo!.chart.trueMax;
                    return Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          color: appState.mods.indexOf(nearestSmaller) ==
                                  appState.mods.indexOf(e)
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
