/// Name: SongState -- ChangeNotifier
/// Description: Model for state relating to the selected song
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/difflist_page.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter/material.dart';

class SongState extends ChangeNotifier {
  SongInfo? _songInfo;
  SongInfo? get songInfo => _songInfo;

  Modes _mode = Modes.singles;
  Modes get modes => _mode;

  int _chosenDifficulty = 0;
  int get chosenDifficulty => _chosenDifficulty;

  List<Note>? _notesPromise;
  List<Note>? get notesPromise => _notesPromise;

  void setSongInfo(SongInfo selectedSongInfo) {
    _songInfo = selectedSongInfo;
    notifyListeners();
  }

  void setMode(Modes newMode) {
    _mode = newMode;
    notifyListeners();
  }

  void setNotePromise(List<Note>? newNotesPromise) {
    _notesPromise = newNotesPromise;
    notifyListeners();
  }

  void setChosenDifficulty(int difficulty) {
    _chosenDifficulty = difficulty;
    notifyListeners();
  }
}

class Songs {
  static List<String> assets = [];
  static List<SongInfo> list = [];
}
