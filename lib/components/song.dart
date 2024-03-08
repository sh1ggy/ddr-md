import 'dart:convert';

import 'package:ddr_md/components/songJson.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  Future<void> readSongJson() async {
    final String response = await rootBundle.loadString('assets/50th.json');
    final data = await json.decode(response);
    setState(() {
      songInfo = parseJson(response);
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
            body: songDetails(),
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
                if (songInfo != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        songInfo!.name,
                        softWrap: true,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
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
                                style:
                                    TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(
                                text: (formattedTime(
                                        timeInSecond:
                                            songInfo!.songLength.toInt()) +
                                    " min, ")),
                            const TextSpan(
                                text: 'BPM: ',
                                style:
                                    TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(text: songInfo!.chart.bpmRange),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            songInfo!.levels.single.beginner.toString(),
                            style: const TextStyle(
                                color: Colors.cyan,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            songInfo!.levels.single.easy.toString(),
                            style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            songInfo!.levels.single.medium.toString(),
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(songInfo!.levels.single.hard.toString(),
                              style: const TextStyle(
                                  color: Colors.purple,
                                  fontWeight: FontWeight.bold)),
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
