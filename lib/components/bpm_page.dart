/// Name: BpmPage
/// Parent: Main
/// Description: Page that displays BPM wheel selector
library;

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
    if (newBpm == "") return;
    bpm = int.parse(newBpm);
    setState(() {
      calcIndex();
    });
  }

  @override
  void initState() {
    super.initState();
    calcIndex();
  }

  @override
  Widget build(BuildContext context) {
    // var bpmState = context.watch<BpmState>();
    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
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
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    keyboardType: TextInputType.number,
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
                    ),
                  ),
                  Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                              width: 50,
                              child: Text(
                                'Mod',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              )),
                          SizedBox(width: 30),
                          SizedBox(
                              width: 50,
                              child: Text(
                                'Speed',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              )),
                        ],
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).size.height / 2,
                        child: ListWheelScrollView.useDelegate(
                            useMagnifier: true,
                            magnification: 1.1,
                            diameterRatio: 1.5,
                            itemExtent: 22,
                            childDelegate: ListWheelChildListDelegate(
                              children: constants.mods.map<Widget>((mod) {
                                var readSpeed = mod * bpm;
                                return Container(
                                  decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(7),
                                      color: nearestModIndex ==
                                                  constants.mods.indexOf(mod) &&
                                              nearestModIndex != 0
                                          ? Colors.redAccent.shade200
                                          : Colors.transparent),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                            width: 50, child: Text('$mod')),
                                        SizedBox(
                                            width: 50,
                                            child: Text('$readSpeed')),
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
        );
      }),
    );
  }
}
