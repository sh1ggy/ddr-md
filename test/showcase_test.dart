/// Name: Showcase tests
/// Parent: ShowcasePage
/// Description: Published cards, selection, caption edits and failed saves.
library;

import 'package:ddr_md/components/circle/showcase_page.dart';
import 'package:ddr_md/components/circle/circle_person_page.dart';
import 'package:ddr_md/components/circle/circle_live_page.dart';
import 'package:ddr_md/components/circle/circle_sheets.dart';
import 'package:ddr_md/components/circle/circle_credit_card.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/showcase.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const first = ShowcaseCard(
    id: 'first',
    song: 'first',
    mode: Modes.singles,
    difficulty: 'EXPERT',
    best: (score: 990000, grade: Grade.aaa, lamp: ClearLamp.pfc, flare: 'IX'),
    caption: 'First milestone');
const second = ShowcaseCard(
    id: 'second',
    song: 'second',
    mode: Modes.doubles,
    difficulty: 'CHALLENGE',
    best: (score: 900000, grade: Grade.aa, lamp: ClearLamp.clear, flare: null),
    caption: 'Stamina arc');

class _Circle extends CircleState {
  List<ShowcaseCard?> cards = [first, second, null];
  List<ShowcaseCard?>? saved;
  bool succeeds = false;
  int showcaseReads = 0;
  @override
  Future<void> poll() async {}
  _Circle() {
    id = 'owner';
  }
  @override
  Future<List<ShowcaseCard?>> loadShowcase(String person) async {
    showcaseReads++;
    return [...cards];
  }

  @override
  Future<bool> saveShowcase(List<ShowcaseCard?> cards) async {
    saved = [...cards];
    error = 'Try saving again';
    return succeeds;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {Settings.jacketMotionOffKey: 1, Settings.jacketEffectsOffKey: 1});
    await Settings.init();
  });
  testWidgets(
      'friend profile keeps showcase and previous session while live opens separately',
      (tester) async {
    final circle = _Circle();
    final CirclePerson person = (
      id: 'friend',
      name: 'MIKA',
      ddrCode: '12345678',
      friend: true,
      live: (
        venue: 'Arcade',
        credit: 2,
        side: '1P',
        session: 'current',
        at: DateTime.now()
      )
    );
    CircleCredit credit(String session) => (
          by: person,
          session: session,
          credit: 1,
          at: DateTime.now(),
          plays: const [],
          cheers: const [],
          mine: null
        );
    circle.following = [person];
    circle.feed = [credit('current'), credit('previous')];
    await tester.pumpWidget(ChangeNotifierProvider<CircleState>.value(
        value: circle,
        child: MaterialApp(
            theme: floorPopTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!),
            home: CirclePersonPage(person: person, tie: CircleTie.friends))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircleShowcase), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(CircleSessionCard), 200);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        tester
            .widget<CircleSessionCard>(find.byType(CircleSessionCard))
            .credits
            .first
            .session,
        'previous');
    expect(find.byType(CircleCreditCard), findsNothing);
    final reads = circle.showcaseReads;
    await tester.scrollUntilVisible(find.text('View live session'), -200);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('View live session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CircleLivePage), findsOneWidget);
    expect(find.byType(CircleShowcase), findsNothing);
    expect(find.byType(CircleSessionCard), findsNothing);
    expect(
        tester
            .widget<CircleCreditCard>(find.byType(CircleCreditCard))
            .credit
            .session,
        'current');
    expect(circle.showcaseReads, reads);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('snapshot round trip retains chart identity, caption and score layers',
      () {
    final card = ShowcaseCard.fromJson(
        {...first.toJson(), 'cheers': 3, 'cheered': true});
    expect(card.toJson(), first.toJson());
    expect(card.best, first.best);
    expect(card.withCaption('New caption').id, first.id);
    expect(card.cheers, 3);
    expect(card.cheered, isTrue);
  });
  testWidgets(
      'fan switches card details and cheers the selected chart on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ShowcaseCard? cheered;
    await tester.pumpWidget(MaterialApp(
        theme: floorPopTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: ShowcaseDisplay(
                    cards: const [first, second, null],
                    onCheer: (c) => cheered = c)))));
    await tester.pumpAndSettle();
    expect(find.text('“First milestone”'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('showcase-slot-1')));
    await tester.pumpAndSettle();
    expect(find.text('“Stamina arc”'), findsOneWidget);
    await tester.ensureVisible(find.text('Cheer this card'));
    await tester.tap(find.text('Cheer this card'));
    expect(cheered?.id, 'second');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'picker preserves slot captions, clears a slot, and retries failed saves',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await DatabaseProvider.open(inMemoryDatabasePath);
      await DatabaseProvider.withTestDatabase(db, () async {
        final oldSongs = Songs.list;
        Songs.list = [
          for (final name in ['first', 'second', 'third'])
            SongInfo.fromJson({
              'name': name,
              'title': name,
              'version': 'DDR WORLD',
              'sp': {'hard': 15},
              'dp': {'challenge': 17}
            })
        ];
        await DatabaseProvider.saveScoreRecords([
          for (final name in ['first', 'third'])
            ScoreRecord(
                id: name,
                source: ScoreRecordSource.manual,
                song: name,
                title: name,
                mode: Modes.singles,
                difficulty: 'EXPERT',
                score: name == 'first' ? 990000 : 850000,
                rank: name == 'first' ? 'AAA' : 'A+',
                clearLamp: ClearLamp.clear,
                updatedAt: DateTime(2026))
        ]);
        final circle = _Circle();
        await tester.pumpWidget(ChangeNotifierProvider<CircleState>.value(
            value: circle,
            child: MaterialApp(
                theme: floorPopTheme(Brightness.dark),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: true),
                    child: child!),
                home: Builder(
                    builder: (context) => Scaffold(
                        body: TextButton(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const ShowcasePickerPage())),
                            child: const Text('Open picker')))))));
        await tester.tap(find.text('Open picker'));
        await tester.pump();
        for (var frame = 0; frame < 15; frame++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        final third =
            find.byKey(const ValueKey('showcase-best-singles:third:EXPERT'));
        await tester.scrollUntilVisible(third, 150);
        await tester.pumpAndSettle();
        await tester.tap(third);
        await tester.pumpAndSettle();
        final firstBest =
            find.byKey(const ValueKey('showcase-best-singles:first:EXPERT'));
        await tester.ensureVisible(firstBest);
        await tester.pumpAndSettle();
        await tester.tap(firstBest);
        await tester.pumpAndSettle();
        await tester
            .ensureVisible(find.byKey(const ValueKey('showcase-slot-2')));
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'My milestone');
        await tester.pump();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester
            .ensureVisible(find.byKey(const ValueKey('showcase-slot-1')));
        await tester.tap(find.byKey(const ValueKey('showcase-slot-1')));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'Stamina arc'), findsOneWidget);
        await tester.tap(find.byTooltip('Take this card out'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Show my circle'));
        await tester.pumpAndSettle();
        expect(circle.saved![2]!.caption, 'My milestone');
        expect(circle.saved![0]!.song, 'third');
        expect(circle.saved![1], isNull);
        expect(find.text('Try saving again'), findsOneWidget);
        expect(find.byType(ShowcasePickerPage), findsOneWidget);
        circle.succeeds = true;
        await tester.tap(find.text('Show my circle'));
        await tester.pumpAndSettle();
        expect(find.text('Open picker'), findsOneWidget);
        expect(find.byType(ShowcasePickerPage), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        Songs.list = oldSongs;
      });
      await db.close();
    });
  });
}
