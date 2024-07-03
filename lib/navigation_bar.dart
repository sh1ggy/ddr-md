import 'package:ddr_md/models/navigation_model.dart';
import 'package:flutter/material.dart';

class LayoutNavigationBar extends StatelessWidget {
  const LayoutNavigationBar({
    super.key,
    required this.navigationState,
  });
  final NavigationState navigationState;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      elevation: 5,
      surfaceTintColor: Colors.black,
      onDestinationSelected: (int index) {
        navigationState.setCurrentPage(index, context);
      },
      indicatorColor: Colors.primaries.first,
      selectedIndex: navigationState.currentPage,
      destinations: const <Widget>[
        NavigationDestination(
          selectedIcon: Icon(
            Icons.onetwothree,
            color: Colors.white,
          ),
          icon: Icon(Icons.onetwothree),
          label: 'BPM',
        ),
        NavigationDestination(
          selectedIcon: Icon(
            Icons.music_note,
            color: Colors.white,
          ),
          icon: Icon(Icons.music_note),
          label: 'Songs',
        ),
        NavigationDestination(
          selectedIcon: Icon(
            Icons.settings,
            color: Colors.white,
          ),
          icon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }
}