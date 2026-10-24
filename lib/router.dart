/// Name: Router
/// Parent: App
/// Description: The app's routes. Each bottom-bar tab keeps its own navigator,
/// so back (Android button/gesture, iOS swipe) pops within the current tab,
/// and every page reachable by link has a path for deep links to target.
library;

import 'package:ddr_md/components/nav_bar.dart';
import 'package:ddr_md/components/ocr/ocr_page.dart';
import 'package:ddr_md/components/session/app_settings_page.dart';
import 'package:ddr_md/components/session/session_page.dart';
import 'package:ddr_md/components/session/visits.dart';
import 'package:ddr_md/components/settings/settings_page.dart';
import 'package:ddr_md/components/snippets/snippets_page.dart';
import 'package:ddr_md/components/song/song_page.dart';
import 'package:ddr_md/components/songlist/difficultylist_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Path of a song's page; [difficulty] is the chart index to open on.
String songPath(SongInfo song, {int? difficulty}) => Uri(
        path: '/songs/song/${Uri.encodeComponent(song.name)}',
        queryParameters:
            difficulty == null ? null : {'difficulty': '$difficulty'})
    .toString();

// go_router only builds Material pages for material_ui's MaterialApp, not
// Flutter's, and otherwise falls back to pages with no transition and no iOS
// back swipe; so every route builds its own.
Page<void> _page(GoRouterState state, Widget child) =>
    MaterialPage(key: state.pageKey, child: child);

final router = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => Layout(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/songs',
            pageBuilder: (context, state) =>
                _page(state, const DifficultyListPage()),
            routes: [
              GoRoute(
                path: 'song/:name',
                // SongPage reads the selected song from SongState, so a link
                // selects it here before the page builds.
                redirect: (context, state) {
                  final name = state.pathParameters['name'];
                  final song =
                      Songs.list.where((s) => s.name == name).firstOrNull;
                  if (song == null) return '/songs';
                  final songState = context.read<SongState>();
                  if (songState.songInfo != song) songState.setSongInfo(song);
                  final difficulty = int.tryParse(
                      state.uri.queryParameters['difficulty'] ?? '');
                  if (difficulty != null &&
                      songState.chosenDifficulty != difficulty) {
                    songState.setChosenDifficulty(difficulty);
                  }
                  return null;
                },
                pageBuilder: (context, state) => _page(state, const SongPage()),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/snippets',
              pageBuilder: (context, state) =>
                  _page(state, const SnippetsPage())),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/home',
              pageBuilder: (context, state) =>
                  _page(state, const SessionPage()),
              routes: [
                GoRoute(
                    path: 'sessions',
                    pageBuilder: (context, state) =>
                        _page(state, const SessionsPage()),
                    routes: [
                      GoRoute(
                          path: ':key',
                          pageBuilder: (context, state) => _page(
                              state,
                              VisitPage(
                                  visitKey: state.pathParameters['key']!,
                                  play: int.tryParse(
                                      state.uri.queryParameters['play'] ??
                                          '')))),
                    ]),
                GoRoute(
                    path: 'settings',
                    pageBuilder: (context, state) =>
                        _page(state, const AppSettingsPage())),
              ]),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/scan',
              pageBuilder: (context, state) => _page(state, const OcrPage())),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/profile',
              pageBuilder: (context, state) =>
                  _page(state, const SettingsPage())),
        ]),
      ],
    ),
  ],
);

class Layout extends StatelessWidget {
  const Layout({super.key, required this.shell});

  final StatefulNavigationShell shell;

  // Back only reaches here once the current tab is at its root: other tabs
  // return to Home, Home asks before exiting.
  void _onRootBack(BuildContext context) {
    if (shell.currentIndex != kHomeTab) {
      shell.goBranch(kHomeTab);
      return;
    }
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Exit Application'),
              content: const Text('Do you really want to exit the app?'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: const Text('OK'),
                ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onRootBack(context);
      },
      // A tab's navigator reaching its root reports that nothing can handle
      // back, which with predictive back makes Android close the app without
      // asking. This shell always handles it, so report that instead.
      child: NotificationListener<NavigationNotification>(
        onNotification: (notification) {
          if (notification.canHandlePop) return false;
          const NavigationNotification(canHandlePop: true).dispatch(context);
          return true;
        },
        child: Scaffold(
          // The bar floats: pages scroll on under it rather than stopping at
          // a strip above it.
          extendBody: true,
          bottomNavigationBar: FloorPopNavBar(
            index: shell.currentIndex,
            // Re-tapping the current tab returns it to its root.
            onSelected: (index) => shell.goBranch(index,
                initialLocation: index == shell.currentIndex),
          ),
          body: shell,
        ),
      ),
    );
  }
}
