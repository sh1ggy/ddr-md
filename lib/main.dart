/// Name: App
/// Description: Entry point; initialises global state and hands
/// navigation to the router.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/content_updater.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/models/development_snippets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

void main() async {
  // Avoid errors caused by flutter upgrade.
  WidgetsFlutterBinding.ensureInitialized();
  // Initialise global objects
  await Settings.init();
  await DatabaseProvider.init();
  if (kDebugMode) await seedDevelopmentSnippets();
  final support = await getApplicationSupportDirectory();
  await ContentStore.init(support);
  await Songs.load();
  await LevelProfiles.load();
  final session = SessionState();
  await session.restore();
  final eamuse = EamuseSyncState();
  await eamuse.restore();

  // Wrapped app with providers
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (context) => SongState()),
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: eamuse),
    ],
    child: const App(),
  ));

  // Newer chart content, if any, is downloaded and applied in the background.
  ContentUpdater.update(support).catchError((Object e) {
    debugPrint('Content update failed: $e');
    return false;
  });
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
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
      routerConfig: router,
    );
  }
}
