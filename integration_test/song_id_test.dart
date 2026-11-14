/// Name: Song ID integration test
/// Parent: integration_test
/// Description: The real mic, fingerprints and sheet: while a song plays out
/// loud, Song ID's sheet names it, notes it on the running credit, and
/// Follow along opens the preview in step with it. Needs the fingerprints
/// (tool/generate_fingerprints.dart). SONG_ID_CLIP, 16 kHz mono 16-bit PCM
/// of the song in the app's Documents (it's sandboxed, and its tmp gets
/// cleared), plays in place of the mic: a run started from a terminal gets
/// no mic on macOS. Without it the song must be playing near the mic.
///
///   flutter test integration_test/song_id_test.dart \
///     -d macos --dart-define=DB_NAME=song-id-test.db \
///     --dart-define=SONG_ID_EXPECT=PARANOiA \
///     --dart-define=SONG_ID_CLIP=<container>/Data/Documents/clip.raw
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ddr_md/components/session/listen_sheet.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_id_listener.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

const _expect = String.fromEnvironment('SONG_ID_EXPECT');
const _clip = String.fromEnvironment('SONG_ID_CLIP');

/// [file] as a mic would deliver it: a tenth of a second at a time.
Stream<Uint8List> _play(File file) async* {
  final bytes = file.readAsBytesSync();
  for (var at = 0; at < bytes.length; at += 3200) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    yield Uint8List.sublistView(bytes, at, min(at + 3200, bytes.length));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hears the song, notes it on the credit, follows along',
      (tester) async {
    await Settings.init();
    await DatabaseProvider.init();
    await ContentStore.init(await getApplicationSupportDirectory());
    await Songs.load();
    if (_clip.isNotEmpty) {
      SongIdListener.debugMic = () => _play(File(_clip));
    }
    final session = SessionState();
    final venue = await DatabaseProvider.addVenue(
        'Song ID test ${DateTime.now().millisecondsSinceEpoch}');
    final cabinet = (await DatabaseProvider.getCabinets(venue.id)).first;
    await session.start(venue, cabinet, PadSide.p1);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SongState()),
        ChangeNotifierProvider.value(value: session),
      ],
      child: MaterialApp(
        theme: floorPopTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                  onPressed: () => showListenSheet(context),
                  child: const Text('listen')),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('listen'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Listening…'), findsOneWidget);

    // Up to the sheet's 12 s, then a little for the last try.
    for (var i = 0;
        i < 70 && find.text('Follow along').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text("Couldn't place it"), findsNothing,
        reason: 'nothing placed: is the song playing near the mic?');
    expect(find.text('Follow along'), findsOneWidget);
    final song = Songs.list.firstWhere((s) => s.name == _expect);
    expect(find.text(song.title), findsWidgets);
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.heardSongs, contains(_expect));
    expect(find.textContaining('Noted on credit 1'), findsOneWidget);

    await tester.tap(find.text('Follow along'));
    for (var i = 0;
        i < 40 && find.text('WITH THE CAB').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('WITH THE CAB'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await session.discard();
    await DatabaseProvider.deleteVenue(venue.id);
  });
}
