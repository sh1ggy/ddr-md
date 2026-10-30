/// Name: SongSearchSheet tests
/// Parent: SongSearchSheet
/// Description: Fuzzy ranking, scoped chart selection, keyboard layout and
/// cabinet lettering across the shared OCR and Trends picker.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/components/songlist/song_search_sheet.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openPicker<T>(
  WidgetTester tester, {
  required List<SongSearchOption<T>> options,
  String initialQuery = '',
  T? selected,
  bool browseWhenEmpty = false,
  ({String label, T value})? allOption,
  ValueChanged<T?>? onPicked,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: floorPopTheme(Brightness.dark),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await showSongSearchSheet<T>(
              context,
              options: options,
              initialQuery: initialQuery,
              selected: selected,
              browseWhenEmpty: browseWhenEmpty,
              allOption: allOption,
            );
            onPicked?.call(result);
          },
          child: const Text('Open picker'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open picker'));
  await tester.pumpAndSettle();
}

void main() {
  final butterfly = SongInfo.fromJson({
    'name': 'butterfly-fixture',
    'title': 'BUTTERFLY',
    'sp': {'easy': 3, 'medium': 8, 'hard': 12},
    'dp': {'hard': 13},
  });
  final sakura = SongInfo.fromJson({
    'name': 'sakura-fixture',
    'title': '桜',
    'titletranslit': 'SAKURA',
    'sp': {'hard': 13},
  });

  testWidgets('OCR prefill tolerates typos and shows jackets and level art',
      (tester) async {
    SongInfo? picked;
    await openPicker<SongInfo>(tester,
        initialQuery: 'buterfly',
        options: [
          for (final song in [sakura, butterfly])
            SongSearchOption(value: song, song: song, mode: Modes.singles),
        ],
        onPicked: (value) => picked = value);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'buterfly');
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.widget<ListTile>(find.byType(ListTile).first).title,
        isA<Text>().having((text) => text.data, 'title', 'BUTTERFLY'));
    expect(tester.getSize(find.byType(JacketImage).first), const Size(40, 40));
    expect(find.byType(LevelRow), findsNWidgets(2));
    expect(
        tester
            .widgetList<LevelNumber>(find.byType(LevelNumber))
            .map((n) => n.level),
        containsAll([3, 8, 12]));
    await tester.tap(find.text('BUTTERFLY'));
    await tester.pumpAndSettle();
    expect(picked, same(butterfly));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Trends searches transliteration and keeps distinct chart values',
      (tester) async {
    // The eligible song is deliberately absent from the master list.
    final previous = Songs.list;
    Songs.list = [butterfly];
    addTearDown(() => Songs.list = previous);
    String? picked;
    await openPicker<String>(tester,
        options: [
          SongSearchOption(
              value: 'sp',
              song: sakura,
              mode: Modes.singles,
              difficulty: 'EXPERT',
              level: 13),
          SongSearchOption(
              value: 'dp',
              song: sakura,
              mode: Modes.doubles,
              difficulty: 'CHALLENGE',
              level: 15),
        ],
        selected: 'dp',
        browseWhenEmpty: true,
        allOption: (label: 'All charts', value: ''),
        onPicked: (value) => picked = value);
    await tester.enterText(find.byType(TextField), 'sakra');
    await tester.pumpAndSettle();
    expect(
        tester.widgetList<ListTile>(find.byType(ListTile)).where(
            (tile) => tile.title is Text && (tile.title as Text).data == '桜'),
        hasLength(2));
    expect(find.text('BUTTERFLY'), findsNothing);
    expect(find.byType(DifficultyLabel), findsNWidgets(2));
    expect(find.bySemanticsLabel(RegExp('CHALLENGE 15')), findsOneWidget);
    expect(
        tester.widget<ListTile>(find.byType(ListTile).last).selected, isTrue);
    await tester.tap(find.text('DP'));
    await tester.pumpAndSettle();
    expect(picked, 'dp');
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear restores browsing and All charts clears the filter',
      (tester) async {
    String? picked;
    await openPicker<String>(tester,
        initialQuery: 'butterfly',
        options: [
          SongSearchOption(
              value: 'chart',
              song: butterfly,
              mode: Modes.singles,
              difficulty: 'EXPERT',
              level: 12),
        ],
        selected: 'chart',
        browseWhenEmpty: true,
        allOption: (label: 'All charts', value: ''),
        onPicked: (value) => picked = value);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('BUTTERFLY'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    await tester.tap(find.text('All charts'));
    await tester.pumpAndSettle();
    expect(picked, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact phone keeps search and rows above the keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final long = SongInfo.fromJson({
      'name': 'long-title-fixture',
      'title': 'A very long song title that wraps in the shared picker',
      'titletranslit': 'A very long transliteration that also needs truncation',
    });
    await openPicker<String>(tester,
        options: [
          SongSearchOption(
              value: 'chart',
              song: long,
              mode: Modes.singles,
              difficulty: 'CHALLENGE',
              level: 19)
        ],
        browseWhenEmpty: true,
        allOption: (label: 'All charts', value: ''));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    const keyboardTop = 568 - 260;
    expect(tester.getBottomRight(find.byType(TextField)).dy,
        lessThan(keyboardTop));
    expect(tester.getBottomRight(find.byType(ListView)).dy,
        lessThanOrEqualTo(keyboardTop));
    expect(tester.takeException(), isNull);
  });
}
