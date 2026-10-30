import 'package:ddr_md/components/settings/development_page.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_lab_page.dart';
import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_artwork_picker.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lab opens the shared interactive viewer and closes cleanly',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditionLabPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edition-lab-card')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final viewer =
        tester.widgetList<JacketEdition>(find.byType(JacketEdition)).last;
    expect(viewer.options.motion, isTrue);
    expect(viewer.frozenLight, isNull);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(EditionLabPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('all loaded jackets are searchable beyond the first three',
      (tester) async {
    final original = Songs.list;
    Songs.list = [
      for (var i = 0; i < 6; i++)
        SongInfo.fromJson({
          'name': 'fixture-$i',
          'title': 'Jacket $i',
          'artist': 'Test',
          'version': 'DDR WORLD',
          'sp': {'hard': 17}
        })
    ];
    addTearDown(() => Songs.list = original);
    await tester.pumpWidget(const MaterialApp(home: EditionLabPage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(EditionArtworkPicker), 350);
    await tester.tap(find.byType(EditionArtworkPicker));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Jacket 5');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Jacket 5'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('edition-lab-card')), -350);
    final preview =
        tester.widgetList<JacketEdition>(find.byType(JacketEdition)).first;
    expect(preview.facts.chart.song, 'fixture-5');
    expect(preview.facts.level, 17);
    expect(
        find.byWidgetPredicate(
            (w) => w is SongArtwork && w.songName == 'fixture-5'),
        findsWidgets);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'development hub opens the permanent lab without an experiment flag',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DevelopmentToolsTile())));
    await tester.tap(find.text('Development'));
    await tester.pumpAndSettle();
    expect(find.text('Seeded score combinations'), findsOneWidget);
    await tester.tap(find.text('Jacket edition lab'));
    await tester.pumpAndSettle();
    expect(find.byType(EditionLabPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('leaving a lab that never captured timings releases cleanly',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditionLabPage()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
