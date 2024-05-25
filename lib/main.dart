/// Name: App
/// Description: Main page that hosts the navigator & determines
/// which page is getting rendered.
library;

import 'package:ddr_md/components/bpm_page.dart';
import 'package:ddr_md/components/settings/settings_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/songlist_page.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// Function to load song list JSONs from asset bundle into static class for global use
void loadSongList() async {
  AssetManifest asset = await AssetManifest.loadFromAssetBundle(rootBundle);
  Songs.assets = asset.listAssets();

  List<String> songDataPaths = Songs.assets
      .where((string) => string.startsWith("assets/song-data/"))
      .where((string) => string.endsWith(".json"))
      .map((e) => e.substring(0, e.length - 5))
      .toList();

  for (int i = 0; i < songDataPaths.length; i++) {
    var response = await rootBundle.loadString('${songDataPaths[i]}.json');
    SongInfo songInfo = parseJson(response);
    Songs.list.add(songInfo);
  }
}

void main() async {
  // Avoid errors caused by flutter upgrade.
  WidgetsFlutterBinding.ensureInitialized();
  // Initialise global objects
  await Settings.init();
  await DatabaseProvider.init();
  loadSongList();

  // Wrapped app with providers
  runApp(MultiProvider(
    providers: [ChangeNotifierProvider(create: (context) => SongState())],
    child: const App(),
  ));
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
        const BpmPage(),
        Navigator(
          key: const Key("Song"),
          onGenerateRoute: (settings) {
            Widget page = const SonglistPage();
            return MaterialPageRoute(builder: (_) => page);
          },
        ),
        // const Placeholder(),
        // const Placeholder(),
        Navigator(
            key: const Key("Settings"),
            onGenerateRoute: (settings) {
              Widget page = const SettingsPage();
              return MaterialPageRoute(builder: (_) => page);
            }),
      ][currentPageIndex],
    );
  }
}
