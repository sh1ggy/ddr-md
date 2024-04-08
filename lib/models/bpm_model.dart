import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;

class BpmState extends ChangeNotifier {
  int bpm = constants.chosenBpm; // BPM init

  // Set BPM to new input
  void setBpm(newBpm) {
    if (newBpm == "") return;
    bpm = int.parse(newBpm);
    notifyListeners();
  }

  // Generate list of mods programmatically
  List<double> generateMods() {
    double start = 0.25, end = 4.25;
    // Generate numbers from [0 to 4 in .25 inc.]
    var list = [for (var i = start; i < end; i += .25) i];
    start = 4.5;
    end = 8.5;
    // Generate numbers from [4 to 8 in .5 inc.]
    [for (var i = start; i < end; i += .5) list.add(i)];
    mods = list;
    return list;
  }

  late var mods = generateMods();
}
