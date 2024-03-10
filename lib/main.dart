import 'package:ddr_md/components/bpm.dart';
import 'package:ddr_md/components/song/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'ddr_bpm',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        ),
        home: const Navbar(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  int bpm = 200; // bpm init

  // set BPM to new input
  void setBpm(newBpm) {
    if (newBpm == "") return;
    bpm = int.parse(newBpm);
    notifyListeners();
  }

  // generate the list of mods programmatically
  generateMods() {
    double start = 0.25, end = 4.25; 
    // generating numbers from [0 to 4 in .25 inc.]
    var list = [for (var i = start; i < end; i += .25) i];
    start = 4.5;
    end = 8.5;
    // generating numbers from [4 to 8 in .5 inc.]
    [for (var i = start; i < end; i += .5) list.add(i)]; 
    mods = list;
    return list;
  }
  late var mods = generateMods();
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
        onDestinationSelected: (int index) {
          setState(() {
            currentPageIndex = index;
          });
        },
        indicatorColor: Colors.amber,
        selectedIndex: currentPageIndex,
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.onetwothree),
            icon: Icon(Icons.onetwothree),
            label: 'BPM',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.music_note),
            icon: Icon(Icons.music_note),
            label: 'Songs',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.abc),
            icon: Icon(Icons.abc),
            label: 'Scores',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.people),
            icon: Icon(Icons.people),
            label: 'Social',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.settings),
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      body: <Widget>[
        /// Home page
        const BPMPage(),
        const SongPage(),
        const Placeholder(),
        const Placeholder(),
        const Placeholder(),
      ][currentPageIndex],
    );
  }
}
