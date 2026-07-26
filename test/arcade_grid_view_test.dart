/// Name: ArcadeGridViewTest
/// Description: The arcade song select's two-step pick — a first tap focuses
/// a jacket and raises the info panel, a second opens the song — plus the
/// focus surviving (or not) the list changing underneath it.
library;

import 'package:ddr_md/components/songlist/arcade/arcade_grid_view.dart';
import 'package:ddr_md/components/songlist/arcade/arcade_info_panel.dart';
import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

SongItem item(String title, {int? defaultDifficultyIndex}) {
  Difficulty diff() => Difficulty(easy: 5, medium: 8, hard: 12);
  return SongItem(
    songInfo: SongInfo(
      ssc: false,
      version: 'DDR World',
      name: title.toLowerCase(),
      title: title,
      titletranslit: title,
      artist: 'artist $title',
      artisttranslit: 'artist',
      songLength: 100,
      perChart: false,
      singles: diff(),
      doubles: diff(),
      radarSingles: const {},
      radarDoubles: const {},
      singlesNotecounts: Difficulty(),
      doublesNotecounts: Difficulty(),
      charts: <Chart>[
        Chart(
          dominantBpm: 150,
          trueMin: 150,
          trueMax: 150,
          bpmRange: '150',
          bpms: const [],
          stops: const [],
        ),
      ],
    ),
    isFav: false,
    defaultDifficultyIndex: defaultDifficultyIndex,
  );
}

Future<void> pumpGrid(
  WidgetTester tester,
  List<SongItem> items, {
  SongState? state,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<SongState>.value(
      value: state ?? SongState(),
      child: MaterialApp(
        home: Scaffold(
          body: ArcadeGridView(
            songItems: items,
            sortType: SortType.title,
            mode: Modes.singles,
            leadingSlivers: const <Widget>[],
            regenFavsCallback: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// The focused tile pulses on a repeating controller, so once anything is
// focused the tree never goes idle and pumpAndSettle would spin until it times
// out. Pump past the focus and panel transitions by hand instead.
Future<void> settleFocus(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  testWidgets('the panel stays down until a jacket is picked', (tester) async {
    await pumpGrid(tester, <SongItem>[item('Afronova'), item('Butterfly')]);

    expect(find.byType(ArcadeInfoPanel), findsNothing);
    // Both folders' jackets are on screen, under one A-C banner.
    expect(find.text('A-C'), findsOneWidget);
  });

  testWidgets('the first tap focuses and raises the panel for that song',
      (tester) async {
    await pumpGrid(tester, <SongItem>[item('Afronova'), item('Butterfly')]);

    await tester.tap(find.byType(Image).first);
    await settleFocus(tester);

    expect(find.byType(ArcadeInfoPanel), findsOneWidget);
    expect(find.text('Afronova'), findsOneWidget);
    expect(find.text('artist Afronova'), findsOneWidget);
    expect(find.text('150 BPM'), findsOneWidget);
  });

  testWidgets('focusing applies the level filter\'s default difficulty',
      (tester) async {
    final state = SongState();
    await pumpGrid(
      tester,
      <SongItem>[item('Afronova', defaultDifficultyIndex: 2)],
      state: state,
    );

    await tester.tap(find.byType(Image).first);
    await settleFocus(tester);

    expect(state.chosenDifficulty, 2);
  });

  testWidgets('picking a badge in the panel changes the chosen difficulty',
      (tester) async {
    final state = SongState();
    await pumpGrid(tester, <SongItem>[item('Afronova')], state: state);

    await tester.tap(find.byType(Image).first);
    await settleFocus(tester);
    expect(state.chosenDifficulty, 0);

    // The badges show each charted level; tapping the 12 picks hard (index 2).
    await tester.tap(find.text('12'));
    await settleFocus(tester);
    expect(state.chosenDifficulty, 2);
  });

  testWidgets('closing the panel clears the focus', (tester) async {
    await pumpGrid(tester, <SongItem>[item('Afronova')]);

    await tester.tap(find.byType(Image).first);
    await settleFocus(tester);
    expect(find.byType(ArcadeInfoPanel), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await settleFocus(tester);
    expect(find.byType(ArcadeInfoPanel), findsNothing);
  });

  testWidgets('a tap on the focused jacket opens the song', (tester) async {
    final state = SongState();
    await pumpGrid(tester, <SongItem>[item('Afronova')], state: state);

    await tester.tap(find.byType(Image).first);
    await settleFocus(tester);
    expect(state.songInfo, isNull);

    // Second tap on the same jacket confirms — the grid hands the song to
    // SongState on its way to the song page. The push itself isn't pumped:
    // SongPage reaches for sqflite, which isn't wired up under `flutter test`.
    await tester.tap(find.byType(Image).first);
    expect(state.songInfo?.title, 'Afronova');
  });

  testWidgets('the panel drops when a filter change removes the focused song',
      (tester) async {
    final state = SongState();
    final all = <SongItem>[item('Afronova'), item('Butterfly')];

    await pumpGrid(tester, all, state: state);
    await tester.tap(find.byType(Image).first);
    await settleFocus(tester);
    expect(find.text('Afronova'), findsOneWidget);

    // Refilter to a list the focused song isn't in.
    await tester.pumpWidget(
      ChangeNotifierProvider<SongState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: ArcadeGridView(
              songItems: <SongItem>[all[1]],
              sortType: SortType.title,
              mode: Modes.singles,
              leadingSlivers: const <Widget>[],
              regenFavsCallback: () {},
            ),
          ),
        ),
      ),
    );
    await settleFocus(tester);

    expect(find.byType(ArcadeInfoPanel), findsNothing);
  });
}
