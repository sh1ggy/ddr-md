import 'package:ddr_md/components/bpm_page.dart';
import 'package:ddr_md/components/settings/settings_page.dart';
import 'package:ddr_md/components/songlist/difficultylist_page.dart';
import 'package:ddr_md/navigation_bar.dart';
import 'package:flutter/material.dart';

class NavigationState extends ChangeNotifier {
  int _currentPage = 0;
  int get currentPage => _currentPage;
  void setCurrentPage(int currentPage, BuildContext context) {
    _currentPage = currentPage;
    switch (currentPage) {
      case 0:
        Navigator.push(
            context, MaterialPageRoute(builder: (context) => const BpmPage()));
      case 1:
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const DifficultyListPage()));
      case 2:
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const SettingsPage()));
    }
    notifyListeners();
  }
}
