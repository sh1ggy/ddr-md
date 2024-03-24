import 'dart:convert';
import 'package:ddr_md/components/song/prevNote.dart';
import 'package:ddr_md/components/songJson.dart';
import 'package:ddr_md/main.dart';
import 'package:fl_chart/fl_chart.dart';
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
  int nearestModIndex = 0;
  List<FlSpot> songSpots = [];
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

  void genBpmPoints() {
    List<Bpm> bpms = chart!.bpms;
    if (songSpots.isNotEmpty)
      return; // TODO: remove this when doing dynamic songData

    for (int i = 0; i < bpms.length; i++) {
      songSpots.add(FlSpot(bpms[i].st, bpms[i].val.toDouble()));
      songSpots.add(FlSpot(bpms[i].ed, bpms[i].val.toDouble()));
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
    var appState = context.watch<MyAppState>();
    if (songInfo != null) {
      nearestModIndex = findNearest(chart!.dominantBpm, appState.mods);
      genBpmPoints();
    }
    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
                elevation: 1,
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
                      onPressed: () =>
                          Navigator.pushNamed(context, 'NotePage')),
                ]),
            body: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.fromLTRB(5, 10, 5, 0),
                child: Column(
                  children: [
                    note(context),
                    if (songInfo != null) songDetails(),
                    if (songInfo != null && isBpmChange != null) ...[
                      songBpm(appState, nearestModIndex),
                      songChart(),
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

  Container songChart() {
    Color lineColor = Colors.orangeAccent;
    List<LineChartBarData> lineChartBarData = [
      LineChartBarData(
          spots: songSpots,
          barWidth: 1.25,
          color: lineColor,
          isCurved: false,
          dotData: const FlDotData(show: false))
    ];
    return Container(
      padding: const EdgeInsets.all(1.0),
      height: MediaQuery.of(context).size.height / 3,
      child: LineChart(
        curve: Easing.standard,
        LineChartData(
          titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: 10,
                    getTitlesWidget: (value, meta) {
                      Widget axisTitle = Text(value.floor().toString());
                      // A workaround to hide the max value title as FLChart is overlapping it on top of previous
                      if (value == meta.max) {
                        final remainder = value % meta.appliedInterval;
                        if (remainder != 0.0 &&
                            remainder / meta.appliedInterval < 0.5) {
                          axisTitle = const SizedBox.shrink();
                        }
                      }
                      return SideTitleWidget(
                          axisSide: meta.axisSide, child: axisTitle);
                    }),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 38,
                  interval: 100,
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(
                  showTitles: false,
                ),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(
                  showTitles: false,
                ),
              )),
          lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                  tooltipBgColor: Colors.grey.shade900,
                  tooltipPadding: const EdgeInsets.all(2),
                  tooltipBorder: const BorderSide(color: Colors.black))),
          clipData: const FlClipData.all(),
          borderData:
              FlBorderData(border: Border.all(color: Colors.black, width: 1)),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (value) {
              return const FlLine(
                color: Colors.grey,
                strokeWidth: 1,
              );
            },
            drawVerticalLine: true,
            getDrawingVerticalLine: (value) {
              return const FlLine(
                color: Colors.grey,
                strokeWidth: 1,
              );
            },
          ),
          minX: 1,
          minY: 0,
          maxX: songInfo!.songLength,
          maxY: chart!.trueMax.toDouble(),
          lineBarsData: lineChartBarData,
        ),
      ),
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
                    TextSpan(text: chart!.bpmRange),
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
        mainAxisSize: MainAxisSize.min,
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
                    var avg = e * chart!.dominantBpm;
                    var min = e * chart!.trueMin;
                    var max = e * chart!.trueMax;
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
