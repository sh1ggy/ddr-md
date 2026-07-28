/// Name: ArcadeGridViewTest
/// Description: The grid's one-tap pick — a tap hands the song and its implied
/// difficulty to SongState on the way to the song page — and the jacket
/// captions.
library;

import 'package:ddr_md/components/songlist/arcade/arcade_grid_tile.dart';
import 'package:ddr_md/components/songlist/arcade/arcade_grid_view.dart';
import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

SongItem item(String title, {int? difficultyIndex}) {
  // Singles and doubles carry different levels so tests can tell which set a
  // widget is reading.
  Difficulty diff() => Difficulty(easy: 5, medium: 8, hard: 12);
  Difficulty doublesDiff() => Difficulty(easy: 6, medium: 9, hard: 13);
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
      doubles: doublesDiff(),
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
    difficultyIndex: difficultyIndex,
  );
}

Future<void> pumpGrid(
  WidgetTester tester,
  List<SongItem> items, {
  SongState? state,
  Modes mode = Modes.singles,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<SongState>.value(
      value: state ?? SongState(),
      child: MaterialApp(
        home: Scaffold(
          body: ArcadeGridView(
            songItems: items,
            sortType: SortType.title,
            mode: mode,
            leadingSlivers: const <Widget>[],
            regenFavsCallback: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  testWidgets('a jacket captions itself with its title and charted levels',
      (tester) async {
    // The fixture charts easy/medium/hard only, so beginner and challenge are
    // skipped rather than rendered as blanks.
    await pumpGrid(tester, <SongItem>[item('Afronova')]);

    expect(find.text('Afronova'), findsOneWidget);
    // The caption is title and levels only — BPM was dropped from the tile, so
    // the fixture's 150 must not appear.
    expect(find.text('150'), findsNothing);

    Color colourOf(String level) =>
        tester.widget<Text>(find.text(level)).style!.color!;
    expect(colourOf('5'), difficultyColor('easy'));
    expect(colourOf('8'), difficultyColor('medium'));
    expect(colourOf('12'), difficultyColor('hard'));
  });

  testWidgets('the levels follow the selected mode', (tester) async {
    // The doubles fixture charts different numbers, so the mode decides which
    // set the tile reports.
    await pumpGrid(tester, <SongItem>[item('Afronova')], mode: Modes.doubles);

    expect(find.text('6'), findsOneWidget);
    expect(find.text('5'), findsNothing);
  });

  testWidgets('a tap opens the tapped song at its implied difficulty',
      (tester) async {
    // The push itself isn't pumped: SongPage reaches for sqflite, which isn't
    // wired up under `flutter test`.
    final state = SongState();
    await pumpGrid(
      tester,
      <SongItem>[
        item('Afronova'),
        item('Butterfly', difficultyIndex: 2),
      ],
      state: state,
    );
    expect(state.songInfo, isNull);

    await tester.tap(find.byType(Image).at(1));

    expect(state.songInfo?.title, 'Butterfly');
    expect(state.chosenDifficulty, 2);
  });

  testWidgets('a song with no implied difficulty opens on the first chart',
      (tester) async {
    final state = SongState();
    state.setChosenDifficulty(3);
    await pumpGrid(tester, <SongItem>[item('Afronova')], state: state);

    await tester.tap(find.byType(Image).first);

    expect(state.chosenDifficulty, 0);
  });

  testWidgets('tapping a banner folds its jackets away and back',
      (tester) async {
    await pumpGrid(tester, <SongItem>[item('Afronova')]);
    expect(find.byType(ArcadeGridTile), findsOneWidget);

    await tester.tap(find.text('A-C'));
    await tester.pumpAndSettle();
    expect(find.byType(ArcadeGridTile), findsNothing);
    // The banner stays, so the folder can be reopened.
    expect(find.text('A-C'), findsOneWidget);

    await tester.tap(find.text('A-C'));
    await tester.pumpAndSettle();
    expect(find.byType(ArcadeGridTile), findsOneWidget);
  });

  testWidgets('folding one section leaves its neighbours open', (tester) async {
    await pumpGrid(tester, <SongItem>[item('Afronova'), item('Dynamite')]);

    await tester.tap(find.text('A-C'));
    await tester.pumpAndSettle();

    expect(find.byType(ArcadeGridTile), findsOneWidget);
    expect(find.text('Dynamite'), findsOneWidget);
  });
}
