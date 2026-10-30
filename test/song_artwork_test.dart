/// Name: Song artwork tests
/// Parent: SongDetails, SongArtwork
/// Description: Missing-art songs keep their compact layout, zoom, and dismiss gestures
/// at compact phone sizes and in both app themes.
library;

import 'dart:ui' as ui;

import 'package:ddr_md/components/song/song_details.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/generated_jacket.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  final song = SongInfo.fromJson({
    'name': 'missing-art-fixture',
    'title': 'A Long Song Title Without Artwork',
    'artist': 'An artist with a longer name',
    'version': 'DDR WORLD',
    'song_length': 123,
    'sp': {'easy': 5, 'medium': 9, 'hard': 13, 'challenge': 16},
    'radar': {
      'sp': {
        'easy': {
          'stream': 50,
          'voltage': 40,
          'air': 30,
          'freeze': 20,
          'chaos': 10,
        }
      }
    },
  });

  testWidgets('decoded jacket stays present throughout opening and closing',
      (tester) async {
    final bytes = await tester.runAsync(() async {
      final image = await createTestImage(width: 8, height: 8, cache: false);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return png!;
    });
    final loaded = SongInfo.fromJson({
      'name': 'loaded-art-fixture',
      'title': 'Loaded artwork',
    });
    final state = SongState()..setSongInfo(loaded);
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: _JacketBundle(bytes!),
      child: ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
            theme: floorPopTheme(Brightness.dark),
            home: Scaffold(body: SongDetails(songInfo: loaded, chart: null))),
      ),
    ));
    final source = find.byType(SongArtwork).last;
    final provider = tester
        .widget<Image>(
            find.descendant(of: source, matching: find.byType(Image)))
        .image;
    await tester
        .runAsync(() => precacheImage(provider, tester.element(source)));
    await tester.pumpAndSettle();

    void expectDecodedSquare() {
      final image = find.descendant(
          of: find.byType(SongArtwork).last, matching: find.byType(RawImage));
      expect(tester.widget<RawImage>(image).image, isNotNull);
      expect(tester.getSize(image).aspectRatio, closeTo(1, 0.001));
      // An independent image fade would expose the generated cover mid-flight.
      for (final opacity in tester.widgetList<AnimatedOpacity>(find.descendant(
          of: find.byType(SongArtwork).last,
          matching: find.byType(AnimatedOpacity)))) {
        expect(opacity.opacity, 1);
      }
    }

    for (var cycle = 0; cycle < 2; cycle++) {
      await tester.tap(find.byType(SongArtwork).last);
      await tester.pump();
      await tester.pump();
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        expectDecodedSquare();
      }
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byType(SongArtwork).last),
          tester.getCenter(find.byType(Scaffold).last));
      await tester.tap(find.byType(SongArtwork).last);
      await tester.pump();
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        expectDecodedSquare();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(SongArtwork).last), const Size(96, 96));
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('artwork fills the top during overscroll / $brightness',
        (tester) async {
      final state = SongState()..setSongInfo(song);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: floorPopTheme(brightness),
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              child: Column(children: [
                SongDetails(songInfo: song, chart: null),
                const SizedBox(height: 1000),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
      scroll.jumpTo(-120);
      await tester.pump();
      // The details move down during overscroll, but their backdrop still
      // covers the space above them, right up to the viewport's top edge.
      expect(tester.getTopLeft(find.byType(SongDetails)).dy, greaterThan(top));
      expect(tester.getTopLeft(find.byType(SongArtwork).first).dy,
          closeTo(top, 0.01));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 430.0]) {
      testWidgets('missing jacket details and zoom at $width / $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = SongState()..setSongInfo(song);
        await tester.pumpWidget(ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: floorPopTheme(brightness),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: SongDetails(songInfo: song, chart: null))),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final art = find.byType(SongArtwork).last;
        // The jacket, frame and all; the art sits inside its frame.
        final rect = tester.getRect(find
            .ancestor(of: art, matching: find.byType(SizedBox))
            .first);
        expect(rect.width, 96);
        expect(rect.size.aspectRatio, 1);
        expect(find.byType(GeneratedJacket), findsNWidgets(2));
        await tester.tap(art);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final zoom = find.byType(SongArtwork).last;
        expect(tester.getSize(zoom).width, greaterThan(rect.width));
        // The card lands square, not stretched to the screen.
        expect(tester.getSize(zoom).aspectRatio, closeTo(1, 0.001));
        await tester.tap(zoom);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SongDetails), findsOneWidget);
      });
    }
  }
}

// Tiny decoded artwork, so this regression runs without copyrighted assets.
class _JacketBundle extends CachingAssetBundle {
  _JacketBundle(this.png);
  final ByteData png;

  @override
  Future<ByteData> load(String key) {
    if (key.endsWith('/loaded-art-fixture.png')) return Future.value(png);
    return rootBundle.load(key);
  }
}
