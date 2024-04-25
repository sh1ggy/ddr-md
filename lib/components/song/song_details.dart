/// Name: SongDetails
/// Parent: SongPage
/// Description: Widgets that display base song information.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:flutter/material.dart';

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
    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          GestureDetector(
            child: Image(
              image: AssetImage(
                  'assets/jackets-lowres/${songInfo.name}-jacket.png'),
              height: 100,
            ),
            // Zooming image onTap
            onTap: () {
              Navigator.of(context).push(PageRouteBuilder(
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  opaque: true,
                  barrierDismissible: true,
                  pageBuilder: (BuildContext context, _, __) {
                    return GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Hero(
                        transitionOnUserGestures: true,
                        tag: "zoom",
                        child: Image(
                          height: MediaQuery.of(context).size.height * .7,
                          image: AssetImage(
                              'assets/jackets/${songInfo.name}-jacket.png'),
                        ),
                      ),
                    );
                  }));
            },
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontSize: 14.0,
                      color: Theme.of(context).textTheme.bodyMedium?.color),
                  children: <TextSpan>[
                    const TextSpan(
                        text: 'Version: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: songInfo.version),
                  ],
                ),
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
                    TextSpan(text: chart!.dominantBpm.toString()),
                  ],
                ),
              ),
              // Only show BPM range if there is one
              RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontSize: 14.0,
                      color: Theme.of(context).textTheme.bodyMedium?.color),
                  children: <TextSpan>[
                    const TextSpan(
                        text: 'BPM: ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    if (chart!.trueMin != chart!.trueMax)
                      TextSpan(text: '(${chart!.trueMin.toString()})'),
                    TextSpan(text: chart!.bpmRange),
                    if (chart!.trueMin != chart!.trueMax)
                      TextSpan(text: '(${chart!.trueMax.toString()})'),
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
                  if (songInfo.levels.single.challenge != null)
                    Text(songInfo.levels.single.challenge.toString(),
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
}
