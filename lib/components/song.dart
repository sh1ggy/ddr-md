import 'dart:convert';

import 'package:ddr_md/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

class SongInfo {
  String name = "";
  String version = "";
  double song_length = 0;
  SongInfo.fromJson(Map json) {
    name = json['name'];
    version = json['version'];
    song_length = json['song_length'];
  }
}

class SongPage extends StatefulWidget {
  const SongPage({super.key});

  @override
  State<SongPage> createState() => _SongPageState();
}

class _SongPageState extends State<SongPage> {
  @override
  Widget build(BuildContext context) {
    late SongInfo? songInfo = null;

    Future<void> readSongJson() async {
      final String response = await rootBundle.loadString('assets/50th.json');
      final data = await json.decode(response);
      songInfo = new SongInfo.fromJson(data); // maybe remove this
    }

    var appState = context.watch<MyAppState>();

    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            body: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  songInfo == null
                      ? Text("nothing here")
                      : Column(
                          children: [
                            Text(songInfo!.name),
                            Text(songInfo!.version),
                            Text(songInfo!.song_length.toString()),
                          ],
                        ),
                  ElevatedButton(
                    child: const Text('Load Data'),
                    onPressed: readSongJson,
                  ),
                  const Image(image: AssetImage('assets/background.png')),
                ]),
          ),
        );
      }),
    );
  }
}

// // Fetch content from the json file
// class SongPage extends State<SongPage> {
//   List _items = [];

//   Future<void> readJson() async {
//     final String response = await rootBundle.loadString('assets/sample.json');
//     final data = await json.decode(response);
//     setState(() {
//       _items = data["items"];
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     var appState = context.watch<MyAppState>();

//     return SafeArea(
//       child: LayoutBuilder(builder: (context, constraints) {
//         return const Directionality(
//           textDirection: TextDirection.ltr,
//           child: Scaffold(
//             body: Column(
//                 crossAxisAlignment: CrossAxisAlignment.center,
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 mainAxisSize: MainAxisSize.max,
//                 children: [
//                   Text("swaws"),
//                   Image(image: AssetImage('assets/background.png'))
//                 ]),
//           ),
//         );
//       }),
//     );
//   }
// }
