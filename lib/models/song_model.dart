/// Name: SongState -- ChangeNotifier
/// Description: Model for state relating to the selected song
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:flutter/material.dart';

class SongState extends ChangeNotifier {
  SongInfo? _songInfo;
  SongInfo? get songInfo => _songInfo;

  void setSongInfo(SongInfo selectedSongInfo) {
    _songInfo = selectedSongInfo;
    notifyListeners();
  }
}

class Songs {
  static List<String> assets = [];
  static List<SongInfo> list = [];
}
