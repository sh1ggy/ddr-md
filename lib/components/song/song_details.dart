import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Method for formatting time from a given time (s)
formattedTime({required int timeInSecond}) {
  int sec = timeInSecond % 60;
  int min = (timeInSecond / 60).floor();
  String minute = min.toString().length <= 1 ? "$min" : "$min";
  String second = sec.toString().length <= 1 ? "0$sec" : "$sec";
  return "$minute:$second";
}

class SongDetails extends StatelessWidget {
  const SongDetails({
    super.key,
    required this.songInfo,
    required this.chart,
  });

  final SongInfo songInfo;
  final Chart? chart;

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<AppState>();
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
              songInfo.name,
              softWrap: true,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Text(
              songInfo.version,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            RichText(
              text: TextSpan(
                style: TextStyle(
                    fontSize: 14.0,
                    color: Theme.of(context).textTheme.bodyMedium?.color),
                children: <TextSpan>[
                  const TextSpan(
                      text: 'Length: ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(
                      text: (formattedTime(
                              timeInSecond: songInfo.songLength.toInt()) +
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
                  songInfo.levels.single.beginner.toString(),
                  style: const TextStyle(
                      color: Colors.cyan, fontWeight: FontWeight.bold),
                ),
                Text(
                  songInfo.levels.single.easy.toString(),
                  style: const TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.bold),
                ),
                Text(
                  songInfo.levels.single.medium.toString(),
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold),
                ),
                Text(songInfo.levels.single.hard.toString(),
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold)),
                Text(songInfo.levels.single.challenge.toString(),
                    style: const TextStyle(
                        color: Colors.purple, fontWeight: FontWeight.bold)),
              ].expand((x) => [const SizedBox(width: 10), x]).skip(1).toList(),
            ),
          ],
        ),
      ]);
  }
}