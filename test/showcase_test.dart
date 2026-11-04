/// Name: Showcase tests
/// Parent: ShowcasePage
/// Description: Published cards, card-only selection, slot swaps and failed saves.
library;

import 'package:ddr_md/components/circle/showcase_page.dart';
import 'package:ddr_md/components/circle/circle_person_page.dart';
import 'package:ddr_md/components/circle/circle_live_page.dart';
import 'package:ddr_md/components/circle/circle_sheets.dart';
import 'package:ddr_md/components/circle/circle_credit_card.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
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
    best: (score: 990000, grade: Grade.aaa, lamp: ClearLamp.pfc, flare: 'IX'));
const second = ShowcaseCard(
    id: 'second',
    song: 'second',
    mode: Modes.doubles,
    difficulty: 'CHALLENGE',
    best: (score: 900000, grade: Grade.aa, lamp: ClearLamp.clear, flare: null));

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
        {Settings.jacketMotionOffKey: 1, Settings.jacketEffectsOffKey: 0});
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

  test('snapshot ignores legacy captions and reactions', () {
    final card = ShowcaseCard.fromJson({
      ...first.toJson(),
      'caption': 'Legacy subtitle',
      'cheers': 3,
      'cheered': true
    });
    expect(card.toJson(), first.toJson());
    expect(card.toJson().keys, isNot(contains('caption')));
    expect(card.toJson().keys, isNot(contains('cheers')));
  });
  testWidgets('cards fill the viewer without details, captions or actions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: floorPopTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!),
        home: const Scaffold(
            body: ShowcaseDisplay(cards: [first, second, null]))));
    await tester.pumpAndSettle();
    final firstSlot = find.byKey(const ValueKey('showcase-slot-0'));
    final secondSlot = find.byKey(const ValueKey('showcase-slot-1'));
    expect(tester.getSize(firstSlot).width, inInclusiveRange(180, 200));
    final rect = tester.getRect(secondSlot);
    await tester.tapAt(Offset(rect.left + 15, rect.center.dy));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(secondSlot).properties.selected, isTrue);
    expect(find.byType(DifficultyLabel), findsNWidgets(2));
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('SHOWCASE'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('fan animates selection and shows chart levels', (tester) async {
    final oldSongs = Songs.list;
    addTearDown(() => Songs.list = oldSongs);
    Songs.list = [
      SongInfo.fromJson({
        'name': 'first',
        'title': 'first',
        'version': 'DDR WORLD',
        'sp': {'hard': 15},
        'dp': <String, dynamic>{}
      })
    ];
    await tester.pumpWidget(MaterialApp(
        theme: floorPopTheme(Brightness.dark),
        home: const Scaffold(
            body: SizedBox(
                width: 390,
                child: ShowcaseDisplay(cards: [first, second, null])))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<DifficultyLabel>(find.byType(DifficultyLabel))
            .any((label) => label.difficulty == 'EXPERT' && label.level == 15),
        isTrue);
    final secondSlot = find.byKey(const ValueKey('showcase-slot-1'));
    final before = tester.getRect(secondSlot);
    await tester.tapAt(Offset(before.left + 35, before.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final during = tester.getRect(secondSlot);
    await tester.pumpAndSettle();
    final after = tester.getRect(secondSlot);
    expect(during.center.dx, isNot(before.center.dx));
    expect(during.center.dx, isNot(after.center.dx));
    expect(tester.widget<Semantics>(secondSlot).properties.selected, isTrue);
    await tester.fling(secondSlot, const Offset(-150, 0), 600);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('showcase-slot-0')))
            .properties
            .selected,
        isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('picker swaps cards, clears a slot, and retries failed saves',
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
        expect(find.byType(TextField), findsNothing);
        await tester
            .ensureVisible(find.byKey(const ValueKey('showcase-slot-1')));
        final secondSlot =
            tester.getRect(find.byKey(const ValueKey('showcase-slot-1')));
        await tester.tapAt(Offset(secondSlot.right - 15, secondSlot.center.dy));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Take this card out'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Show my circle'));
        await tester.pumpAndSettle();
        expect(circle.saved![2]!.song, 'first');
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
