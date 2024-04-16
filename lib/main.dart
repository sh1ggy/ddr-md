/// Name: App
/// Description: Main page that hosts the navigator & determines
/// which page is getting rendered.
library;

import 'package:ddr_md/components/bpm_page.dart';
import 'package:ddr_md/components/song/song_page.dart';
import 'package:ddr_md/models/bpm_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => BpmState(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ddr_bpm',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff8cb2dd),
              primary: const Color(0xff2f4d89),
              secondary: const Color(0xffb6445b),
              tertiary: Colors.grey.shade800),
        ),
        darkTheme: ThemeData.dark(useMaterial3: true),
        themeMode: ThemeMode.system,
        home: const Navbar(),
      ),
    );
  }
}

class Navbar extends StatefulWidget {
  const Navbar({super.key});

  @override
  State<Navbar> createState() => _NavbarState();
}

class _NavbarState extends State<Navbar> {
  int currentPageIndex = 0;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        elevation: 5,
        surfaceTintColor: Colors.black,
        onDestinationSelected: (int index) {
          setState(() {
            currentPageIndex = index;
          });
        },
        indicatorColor: Colors.primaries.first,
        selectedIndex: currentPageIndex,
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
          // NavigationDestination(
          //   selectedIcon: Icon(
          //     Icons.abc,
          //     color: Colors.white,
          //   ),
          //   icon: Icon(Icons.abc),
          //   label: 'Scores',
          // ),
          // NavigationDestination(
          //   selectedIcon: Icon(
          //     Icons.people,
          //     color: Colors.white,
          //   ),
          //   icon: Icon(Icons.people),
          //   label: 'Social',
          // ),
          NavigationDestination(
            selectedIcon: Icon(
              Icons.settings,
              color: Colors.white,
            ),
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      body: <Widget>[
        /// Home page
        const BPMPage(),
        Navigator(
          key: const Key("Song"),
          onGenerateRoute: (settings) {
            Widget page = const SongPage();
            return MaterialPageRoute(builder: (_) => page);
          },
        ),
        // const Placeholder(),
        // const Placeholder(),
        Navigator(
            key: const Key("Settings"),
            onGenerateRoute: (settings) {
              Widget page = const Placeholder();
              return MaterialPageRoute(builder: (_) => page);
            }),
      ][currentPageIndex],
    );
  }
}
