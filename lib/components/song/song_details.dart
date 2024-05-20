/// Name: SongDetails
/// Parent: SongPage
/// Description: Widgets that display base song information.
library;

import 'package:ddr_md/components/song/song_diff_picker.dart';
import 'package:ddr_md/components/song/song_difficulties.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
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
    var songState = context.watch<SongState>();

    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          GestureDetector(
            child: Hero(
              tag: "imgZoom",
              child: Image(
                image: AssetImage(
                    'assets/jackets-lowres/${songInfo.name}-jacket.png'),
                height: 100,
              ),
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
                        tag: "imgZoom",
                        transitionOnUserGestures: true,
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
                      color: DefaultTextStyle.of(context).style.color),
                  children: <TextSpan>[
                    TextSpan(
                      text: (formattedTime(
                              timeInSecond: songInfo.songLength.toInt()) +
                          " min"),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Text(
                songInfo.version,
                style: const TextStyle(
                    color: Colors.grey, fontStyle: FontStyle.italic),
              ),
              Align(
                  alignment: AlignmentDirectional.bottomCenter,
                  child: () {
                    Difficulty songDifficulty = songState.modes == Modes.singles
                        ? songInfo.modes.singles
                        : songInfo.modes.doubles;
                    if (songInfo.perChart) {
                      return SongDifficultyPicker(difficulty: songDifficulty);
                    }
                    return SongDifficulty(difficulty: songDifficulty);
                  }()),
            ],
          ),
        ]);
  }
}
