/// Name: ScoringTiersTest
/// Description: Optional scoring metadata, exact decimal lettering, chart sorting
/// and content updates including rollback.
library;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/songlist/arcade/song_sections.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/content_updater.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/components/songlist/sort_menu_button.dart';
import 'package:ddr_md/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture({double tier = 14.90}) => {
      'name': 'A',
      'title': 'A',
      'sp': {'easy': 4, 'hard': 14},
      'dp': {'hard': 15},
      'charts': [],
      'scoring_tiers': {
        'schema': 1,
        'model': 'scoring-v31',
        'sp': {
          'hard': {'tier': tier, 'position': .901305, 'input_hash': 'hash'},
        }
      },
    };

String sha(String text) => sha256.convert(utf8.encode(text)).toString();

class MissingDifficultyArt extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key.startsWith('assets/difficulty/')) {
      return Future.error(FlutterError('Optional difficulty artwork absent'));
    }
    return rootBundle.load(key);
  }
}

void main() {
  test('the initial calculated preference migrates to the existing Level sort',
      () async {
    SharedPreferences.setMockInitialValues({
      Settings.songlistSortKey: SortType.title.index + 1,
      Settings.songlistCalculatedSortKey: 1,
    });
    await Settings.init();
    final state = SongState();
    addTearDown(state.dispose);
    expect(state.sortType, SortType.level);
    expect(Settings.getInt(Settings.songlistSortKey), SortType.level.index + 1);
    expect(Settings.getInt(Settings.songlistCalculatedSortKey), 0);
    expect(nextSortType(SortType.level), SortType.bpm);
    expect(sortLabel(SortType.level), 'Level');
  });

  test('old, unsupported and malformed scoring fields are optional', () {
    expect(SongInfo.fromJson({}).scoringTiers, isNull);
    for (final raw in [
      null,
      [],
      7,
      {'schema': 2},
      {'schema': 1, 'model': false}
    ]) {
      expect(
          SongInfo.fromJson({...fixture(), 'scoring_tiers': raw}).scoringTiers,
          isNull);
    }
    for (final tier in [14.01, double.nan, double.infinity, 20.0, 19.05]) {
      expect(
          SongInfo.fromJson(fixture(tier: tier))
              .scoringTierFor(Modes.singles, 1),
          isNull);
    }
  });

  test('selection uses available ordering, clamps, and keeps modes distinct',
      () {
    final song = SongInfo.fromJson(fixture());
    expect(song.scoringTierFor(Modes.singles, 0), isNull);
    expect(song.scoringTierFor(Modes.singles, 1)?.label, '14.9');
    expect(song.scoringTierFor(Modes.singles, 99)?.label, '14.9');
    expect(song.scoringTierFor(Modes.doubles, 0), isNull);
    expect(
        SongInfo.fromJson(song.toJson())
            .scoringTierFor(Modes.singles, 1)
            ?.label,
        '14.9');
    song.singles.hard = 15;
    expect(song.scoringTierFor(Modes.singles, 1), isNull);
  });

  testWidgets('a tier rides on its level numeral without optional artwork',
      (tester) async {
    final semantics = tester.ensureSemantics();

    for (final (tier, text) in [(14.05, '.05'), (14.90, '.9'), (19.90, '.9')]) {
      final data = fixture(tier: tier);
      (data['sp'] as Map)['hard'] = tier.floor();
      final song = SongInfo.fromJson(data);
      await tester.pumpWidget(DefaultAssetBundle(
          bundle: MissingDifficultyArt(),
          child: MaterialApp(
              theme: floorPopTheme(Brightness.dark),
              home: Scaffold(
                  body: LevelRow(
                      levels: song.singles,
                      highlightIndex: 1,
                      highlightTier: song
                          .scoringTierFor(Modes.singles, 1)
                          ?.hundredths)))));
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(find.bySemanticsLabel('${tier.floor()}$text'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets('tier decimals leave a compact gap before the next difficulty',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final levels = Difficulty.fromJson({
      'beginner': 4,
      'easy': 10,
      'medium': 14,
      'hard': 17,
      'challenge': 18,
    });
    for (final missingArt in [false, true]) {
      for (final packed in [false, true]) {
        final availableWidth = packed ? 92.0 : 140.0;
        for (final fraction in [5, 90, 95]) {
          Widget app = MaterialApp(
            theme: floorPopTheme(Brightness.dark),
            home: Scaffold(
                body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: availableWidth,
                  child: LevelRow(
                    packed: packed,
                    levels: levels,
                    height: 14,
                    highlightIndex: 2,
                    highlightTier: fraction,
                  )),
            )),
          );
          if (missingArt) {
            app =
                DefaultAssetBundle(bundle: MissingDifficultyArt(), child: app);
          }
          await tester.pumpWidget(app);
          if (!missingArt) {
            await tester.runAsync(() async {
              final context = tester.element(find.byType(LevelRow));
              await Future.wait(tester
                  .widgetList<Image>(find.byType(Image))
                  .map((image) => precacheImage(image.image, context)));
            });
          }
          await tester.pumpAndSettle();
          final numbers = find.byType(LevelNumber);
          expect(numbers, findsNWidgets(5));
          final highlighted = tester.getRect(numbers.at(2));
          final following = tester.getRect(numbers.at(3));
          expect(following.left - highlighted.right, inInclusiveRange(1, 4));
          expect(tester.getRect(numbers.last).right,
              lessThanOrEqualTo(availableWidth + .001));
          expect(find.bySemanticsLabel('14.${decimalDigits(fraction)}'),
              findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    }
    semantics.dispose();
  });

  test('Level sort orders tiers within official folders, missing ratings last',
      () {
    SongItem item(String name, double? tier, {int level = 14}) {
      final data = fixture(tier: tier ?? 14.0)..['name'] = name;
      data['title'] = name;
      (data['sp'] as Map)['hard'] = level;
      if (tier == null) data.remove('scoring_tiers');
      return SongItem(
          songInfo: SongInfo.fromJson(data),
          isFav: false,
          difficultyIndex: 1,
          level: level);
    }

    final rows = [
      item('missing', null),
      item('high', 14.9),
      item('low', 14.05),
      item('next', 15.0, level: 15)
    ];
    for (final descending in [false, true]) {
      final sections = groupSongItems(rows, SortType.level, Modes.singles,
          descending: descending);
      final folder = sections.singleWhere((s) => s.label == 'LEVEL 14');
      expect(folder.items.last.songInfo.name, 'missing');
      expect(folder.items.first.songInfo.name, descending ? 'high' : 'low');
      expect(sections.first.label, descending ? 'LEVEL 15' : 'LEVEL 14');
    }
    expect(SortType.level.isBest, isFalse);
    expect(SortType.level.isChartScoped, isTrue);
  });

  test('bundled scoring tier updates over OTA and rolls back', () async {
    final support = Directory.systemTemp.createTempSync('scoring-ota');
    addTearDown(() => support.deleteSync(recursive: true));
    final old = jsonEncode([fixture(tier: 14.05)]),
        fresh = jsonEncode([fixture()]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final path = utf8.decode(message!.buffer.asUint8List());
      return path == 'assets/songlist.json'
          ? ByteData.sublistView(Uint8List.fromList(utf8.encode(old)))
          : null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null));
    final bundle = ContentManifest(
        id: 'old',
        engine: kPatternEngineVersion,
        files: {'songlist.json': sha(old)});
    final remote = ContentManifest(
        id: 'fresh',
        engine: kPatternEngineVersion,
        files: {'songlist.json': sha(fresh)});
    final served = {
      'latest.json': jsonEncode({'id': 'fresh'}),
      'manifest.json': jsonEncode(remote),
      'objects/${sha(fresh)}.json': fresh
    };
    Future<List<int>> fetch(Uri uri) async =>
        utf8.encode(served[uri.path.substring(1)]!);
    Future<String?> label() async => SongInfo.fromJson(
            (jsonDecode(await ContentStore.loadString('assets/songlist.json'))
                    as List)
                .first)
        .scoringTierFor(Modes.singles, 1)
        ?.label;
    await ContentStore.init(support, bundle: bundle);
    expect(await label(), '14.05');
    expect(
        await ContentUpdater.check(support, base: 'https://x/', fetch: fetch),
        isTrue);
    await ContentStore.init(support, bundle: bundle);
    expect(await label(), '14.9');
    served['latest.json'] = jsonEncode({'id': 'old'});
    expect(
        await ContentUpdater.check(support, base: 'https://x/', fetch: fetch),
        isTrue);
    await ContentStore.init(support, bundle: bundle);
    expect(await label(), '14.05');
  });
}
