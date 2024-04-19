/// Name: BpmState -- ChangeNotifier
/// Description: Model for state relating to a player's BPM
library;

import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;

class BpmState extends ChangeNotifier {
  static const chosenReadSpeedSetting = "chosenReadSpeed";

  BpmState(int chosenReadSpeed) {
    chosenReadSpeed = chosenReadSpeed;
  }
  int bpm = constants.songBpm; // BPM init
  int chosenReadSpeed = constants.chosenReadSpeed; // Read speed init
  // Set BPM to new input
  void setBpm(String newBpm) {
    if (newBpm == "") return;
    bpm = int.parse(newBpm);
    notifyListeners();
  }
}
