/// Name: BpmState -- ChangeNotifier
/// Description: Model for state relating to a player's BPM
library;

import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;

class BpmState extends ChangeNotifier {
  static const chosenReadSpeedSetting = "chosenReadSpeed";

  BpmState(int chosenReadSpeed) {
    _chosenReadSpeed = chosenReadSpeed;
  }
  int bpm = constants.songBpm; // BPM init
  int _chosenReadSpeed = constants.chosenReadSpeed; // Read speed init
}
