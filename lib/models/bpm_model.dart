/// Name: BpmState -- ChangeNotifier
/// Description: Model for state relating to a player's BPM
library;

import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;

class BpmState extends ChangeNotifier {
  int bpm = constants.chosenReadSpeed; // BPM init

  // Set BPM to new input
  void setBpm(newBpm) {
    if (newBpm == "") return;
    bpm = int.parse(newBpm);
    notifyListeners();
  }
}
