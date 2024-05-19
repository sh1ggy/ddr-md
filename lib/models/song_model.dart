/// Name: SongState -- ChangeNotifier
/// Description: Model for state relating to the selected song
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:flutter/material.dart';

class SongState extends ChangeNotifier {
  SongInfo? _songInfo;
  SongInfo? get songInfo => _songInfo;

  Modes _mode = Modes.singles;
  Modes get modes => _mode;

  Difficulties _chosenDifficulty = Difficulties.beginner;
  Difficulties get chosenDifficulty => _chosenDifficulty;

  void setSongInfo(SongInfo selectedSongInfo) {
    _songInfo = selectedSongInfo;
    notifyListeners();
  }

  void setMode(Modes newMode) {
    _mode = newMode;
    notifyListeners();
  }

  void setChosenDifficulty(Difficulties difficulty) {
    _chosenDifficulty = difficulty;
    notifyListeners();
  }
}

class Songs {
  static List<String> assets = [];
  static List<SongInfo> list = [];
}
