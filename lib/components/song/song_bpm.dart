/// Name: SongBpm
/// Parent: SongPage
/// Description: Widgets relating to the song's BPM & mods
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;

class SongBpm extends StatelessWidget {
  const SongBpm(
      {super.key,
      required this.nearestModIndex,
      required this.isBpmChange,
      required this.chart});
  final int nearestModIndex;
  final bool? isBpmChange;
  final Chart? chart;

  @override
  Widget build(BuildContext context) {
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
                physics: const FixedExtentScrollPhysics(),
                controller:
                    FixedExtentScrollController(initialItem: nearestModIndex),
                overAndUnderCenterOpacity: .5,
                itemExtent: 22,
                // -- If you wanna use this, refactor Widget to be Stateful
                // onSelectedItemChanged: (index) {
                //   setState(() {
                //     selectedItemIndex = index;
                //   });
                // },
                childDelegate: ListWheelChildListDelegate(
                  children: constants.mods.map<Widget>((mod) {
                    var avg = mod * chart!.dominantBpm;
                    var min = mod * chart!.trueMin;
                    var max = mod * chart!.trueMax;
                    return Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          color: nearestModIndex == constants.mods.indexOf(mod)
                              ? Colors.redAccent.shade200
                              : Colors.transparent),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SongBpmTextItem(
                                text: avg.toString(),
                                nearestModIndex: nearestModIndex,
                                mod: mod),
                            if (isBpmChange!) ...[
                              SongBpmTextItem(
                                  text: min.toString(),
                                  nearestModIndex: nearestModIndex,
                                  mod: mod),
                              SongBpmTextItem(
                                  text: max.toString(),
                                  nearestModIndex: nearestModIndex,
                                  mod: mod),
                            ],
                            SongBpmTextItem(
                                text: mod.toString(),
                                nearestModIndex: nearestModIndex,
                                mod: mod),
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

class SongBpmTextItem extends StatelessWidget {
  const SongBpmTextItem(
      {super.key,
      required this.text,
      required this.nearestModIndex,
      required this.mod});

  final String text;
  final int nearestModIndex;
  final double mod;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      child: Text(text,
          style: TextStyle(
              color: nearestModIndex == constants.mods.indexOf(mod)
                  ? Colors.white
                  : Theme.of(context).textTheme.bodyMedium?.color)),
    );
  }
}
