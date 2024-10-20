/// Name: BpmPage
/// Parent: Main
/// Description: Page that displays BPM wheel selector
library;

import 'package:ddr_md/components/song/song_bpm.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ddr_md/constants.dart' as constants;

class BpmPage extends StatefulWidget {
  const BpmPage({super.key});

  @override
  State<BpmPage> createState() => _BpmPageState();
}

class _BpmPageState extends State<BpmPage> {
  int bpm = constants.songBpm; // BPM init
  int _chosenReadSpeed = constants.chosenReadSpeed; // Read speed init
  int nearestModIndex = 0;

  // Calculate the index of the nearest mod to the chosen
  // read speed in shared_preferences
  void calcIndex() {
    _chosenReadSpeed = Settings.getInt(Settings.chosenReadSpeedKey);
    nearestModIndex =
        findNearestReadSpeed(bpm, constants.mods, _chosenReadSpeed);
  }

  // Set BPM to new input & calc nearestReadSpeed
  void setBpm(String newBpm) {
    if (newBpm == "") {
      setState(() {
        bpm = constants.songBpm;
      });
    } else {
      setState(() {
        bpm = int.parse(newBpm);
      });
    }
    setState(() {
      calcIndex();
    });
    return;
  }

  @override
  void initState() {
    super.initState();
    calcIndex();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
            },
            child: Scaffold(
              appBar: AppBar(
                surfaceTintColor: Colors.black,
                shadowColor: Colors.black,
                elevation: 2,
                title: const Text(
                  'BPM',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.blueGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                iconTheme: const IconThemeData(color: Colors.blueGrey),
              ),
              body: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      maxLength: 3,
                      style: const TextStyle(fontSize: 25),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      textAlign: TextAlign.center,
                      onChanged: (value) => setBpm(value),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        hintText: bpm.toString(),
                        hintStyle: const TextStyle(fontSize: 25),
                      ),
                    ),
                    Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                                width: 60,
                                child: Text(
                                  'Mod',
                                  textAlign: TextAlign.left,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                )),
                            SizedBox(width: 30),
                            SizedBox(
                                width: 60,
                                child: Text(
                                  'Speed',
                                  textAlign: TextAlign.left,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                )),
                          ],
                        ),
                        SizedBox(
                          height: MediaQuery.of(context).size.height / 2,
                          child: ListWheelScrollView.useDelegate(
                              controller: FixedExtentScrollController(
                                  initialItem: nearestModIndex),
                              useMagnifier: true,
                              magnification: 1.1,
                              diameterRatio: 1.5,
                              itemExtent: 25,
                              onSelectedItemChanged: (value) {
                                HapticFeedback.selectionClick();
                              },
                              childDelegate: ListWheelChildListDelegate(
                                children: constants.mods.map<Widget>((mod) {
                                  var readSpeed = mod * bpm;
                                  return Container(
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(7),
                                        color: nearestModIndex ==
                                                    constants.mods
                                                        .indexOf(mod) &&
                                                nearestModIndex != 0
                                            ? Colors.redAccent.shade200
                                            : Colors.transparent),
                                    child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SongBpmTextItem(
                                              text: mod.toString(),
                                              nearestModIndex: nearestModIndex,
                                              mod: mod),
                                          SongBpmTextItem(
                                              text:
                                                  readSpeed.round().toString(),
                                              nearestModIndex: nearestModIndex,
                                              mod: mod),
                                        ]
                                            .expand((x) =>
                                                [const SizedBox(width: 30), x])
                                            .skip(1)
                                            .toList()),
                                  );
                                }).toList(),
                              )),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
