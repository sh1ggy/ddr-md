/// Name: SongSectionOrderTest
/// Description: Order persistence + reorder maths for the song page's
/// drag-to-rearrange sections.
library;

import 'package:ddr_md/components/song/song_page.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  group('saved order', () {
    test('defaults to the declared section order when nothing is saved', () {
      expect(readSongSectionOrder(), SongSection.values);
    });

    test('round-trips a custom order', () async {
      final custom = <SongSection>[
        SongSection.grooveRadar,
        SongSection.speedMod,
        SongSection.sync,
        SongSection.bpmGraph,
        SongSection.latestScore,
        SongSection.latestNote,
      ];
      await Settings.setString(Settings.songSectionOrderKey,
          custom.map((s) => s.name).join(','));

      expect(readSongSectionOrder(), custom);
    });

    test('drops ids this build no longer knows, keeping the rest in order',
        () async {
      await Settings.setString(Settings.songSectionOrderKey,
          'grooveRadar,someRemovedSection,speedMod');

      final order = readSongSectionOrder();
      expect(order.first, SongSection.grooveRadar);
      expect(order[1], SongSection.speedMod);
      // Everything else survives, exactly once.
      expect(order.toSet(), SongSection.values.toSet());
      expect(order.length, SongSection.values.length);
    });

    test('appends sections added since the order was saved', () async {
      await Settings.setString(
          Settings.songSectionOrderKey, 'latestNote,grooveRadar');

      final order = readSongSectionOrder();
      expect(order.first, SongSection.latestNote);
      expect(order[1], SongSection.grooveRadar);
      expect(order.length, SongSection.values.length);
      expect(order.toSet(), SongSection.values.toSet());
    });

    test('ignores a duplicated id rather than listing a section twice',
        () async {
      await Settings.setString(
          Settings.songSectionOrderKey, 'sync,sync,speedMod');

      final order = readSongSectionOrder();
      expect(order.where((s) => s == SongSection.sync).length, 1);
      expect(order.length, SongSection.values.length);
    });
  });

  group('reorder', () {
    // The full order every case below starts from.
    List<SongSection> full() => SongSection.values.toList();

    test('moving down within a fully-visible list lands where dropped', () {
      final next = reorderSongSections(
        order: full(),
        visible: full(),
        oldIndex: 0, // speedMod
        newIndex: 2, // past sync and grooveRadar
      );
      expect(next.take(3),
          [SongSection.sync, SongSection.grooveRadar, SongSection.speedMod]);
    });

    test('moving up within a fully-visible list lands where dropped', () {
      final next = reorderSongSections(
        order: full(),
        visible: full(),
        oldIndex: 2, // grooveRadar
        newIndex: 0,
      );
      expect(next.take(2), [SongSection.grooveRadar, SongSection.speedMod]);
    });

    // The case the visible/full split exists for: dragging the cards that ARE
    // shown must not disturb where hidden ones sit for songs that show them.
    test('a hidden section keeps its neighbours when visible cards move', () {
      // sync and bpmGraph hidden: the user only ever drags the other four.
      final visible = <SongSection>[
        SongSection.speedMod,
        SongSection.grooveRadar,
        SongSection.latestScore,
        SongSection.latestNote,
      ];

      // Drag grooveRadar (visible index 1) to the top.
      final next = reorderSongSections(
        order: full(),
        visible: visible,
        oldIndex: 1,
        newIndex: 0,
      );

      expect(next.first, SongSection.grooveRadar);
      // sync was hidden between speedMod and grooveRadar; it must stay after
      // speedMod rather than being dragged to the top along with the move.
      expect(next.indexOf(SongSection.sync),
          greaterThan(next.indexOf(SongSection.speedMod)));
      expect(next.length, SongSection.values.length);
      expect(next.toSet(), SongSection.values.toSet());
    });

    test('dropping a card back where it started changes nothing', () {
      final next = reorderSongSections(
        order: full(),
        visible: full(),
        oldIndex: 2,
        newIndex: 2,
      );
      expect(next, SongSection.values);
    });
  });
}
