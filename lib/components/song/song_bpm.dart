import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/bpm_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    var bpmState = context.watch<BpmState>();
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
                  children: bpmState.mods.map<Widget>((e) {
                    var avg = e * chart!.dominantBpm;
                    var min = e * chart!.trueMin;
                    var max = e * chart!.trueMax;
                    return Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          color: nearestModIndex == bpmState.mods.indexOf(e)
                              ? Colors.redAccent.shade200
                              : Colors.transparent),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SongBpmTextItem(
                                text: avg.toString(),
                                nearestModIndex: nearestModIndex,
                                e: e),
                            if (isBpmChange!) ...[
                              SongBpmTextItem(
                                  text: min.toString(),
                                  nearestModIndex: nearestModIndex,
                                  e: e),
                              SongBpmTextItem(
                                  text: max.toString(),
                                  nearestModIndex: nearestModIndex,
                                  e: e),
                              SongBpmTextItem(
                                  text: e.toString(),
                                  nearestModIndex: nearestModIndex,
                                  e: e),
                            ],
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
      required this.e});

  final String text;
  final int nearestModIndex;
  final double e;

  @override
  Widget build(BuildContext context) {
    var bpmState = context.watch<BpmState>();
    return SizedBox(
      width: 50,
      child: Text(text,
          style: TextStyle(
              color: nearestModIndex == bpmState.mods.indexOf(e)
                  ? Colors.white
                  : Theme.of(context).textTheme.bodyMedium?.color)),
    );
  }
}
