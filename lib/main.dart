/// Name: App
/// Description: Main page that hosts the navigator & determines
/// which page is getting rendered.
library;

import 'dart:io';

import 'package:ddr_md/components/bpm_page.dart';
import 'package:ddr_md/components/settings/settings_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/difficultylist_page.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
      home: const Layout(),
    );
  }
}

class Layout extends StatefulWidget {
  const Layout({super.key});

  @override
  State<Layout> createState() => _LayoutState();
}

class _LayoutState extends State<Layout> {
  int currentPageIndex = 0;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) => showDialog(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Exit Application'),
                content: const SingleChildScrollView(
                  child: ListBody(
                    children: <Widget>[
                      Text('Do you really want to exit the app?'),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'Cancel'),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text('OK'),
                  ),
                ],
              )),
      child: Scaffold(
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
          // Android-specific removal of navigators to make back gesture work
          // Note that this removes the bottom navigator
          if (Platform.isAndroid) ...{
            const BpmPage(),
            const DifficultyListPage(),
            const SettingsPage(),
          } else ...{
            Navigator(
              key: const Key("Bpm"),
              onGenerateRoute: (settings) {
                Widget page = const BpmPage();
                return MaterialPageRoute(builder: (_) => page);
              },
            ),
            Navigator(
              key: const Key("SongList"),
              onGenerateRoute: (settings) {
                Widget page = const DifficultyListPage();
                return MaterialPageRoute(builder: (_) => page);
              },
            ),
            Navigator(
                key: const Key("Settings"),
                onGenerateRoute: (settings) {
                  Widget page = const SettingsPage();
                  return MaterialPageRoute(builder: (_) => page);
                }),
          }
        ][currentPageIndex],
      ),
    );
  }
}
