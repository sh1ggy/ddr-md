/// Name: Binder landing integration test
/// Parent: integration_test
/// Description: Deals a dozen cards across several levels into the binder, as
/// a session wrap does, and reports how its tour renders: frame build and
/// raster times, and how many jackets on the sheet in view were still blank
/// (decoding) in any frame, which shows as jackets popping in.
///
/// Run in profile mode on macOS, on the seeded database:
///   flutter drive --profile -d macos --dart-define=DB_NAME=timing-preview.db \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/binder_landing_test.dart
library;

import 'package:ddr_md/components/song/jacket_edition/edition_binder_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyNames;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('cards land in the binder smoothly', (tester) async {
    await Settings.init();
    await DatabaseProvider.init();
    await ContentStore.init(await getApplicationSupportDirectory());
    await Songs.load();
    const mode = Modes.singles;
    await ChartBests.ensure(mode);

    // Two collected charts from each level down from the top, so the tour
    // jumps between levels past their covers.
    final byLevel = <int, List<BinderChart>>{};
    for (final SongInfo song in Songs.list) {
      final json = song.singles.toJson();
      for (final MapEntry(:key, :value) in kInGameDifficultyNames.entries) {
        if (json[key] is! int) continue;
        if (ChartBests.forChart(song.name, mode, value) == null) continue;
        byLevel
            .putIfAbsent(json[key] as int, () => [])
            .add((song: song.name, difficulty: value));
      }
    }
    final arrivals = <BinderChart, Null>{
      for (final level in byLevel.keys.toList()..sort((a, b) => b - a))
        for (final c in byLevel[level]!.take(2)) c: null,
    }.entries.take(12);
    final first = arrivals.first.key;
    final level = byLevel.entries
        .firstWhere((e) => e.value.contains(first))
        .key;

    PaintingBinding.instance.imageCache.clear();
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);

    var frames = 0, blankFrames = 0, mostBlank = 0;
    var probing = true;
    final sheetImages = find.descendant(
        of: find.byType(PageView), matching: find.byType(RawImage));
    void probe(Duration _) {
      if (!probing) return;
      frames++;
      final blank = sheetImages
          .evaluate()
          .where((e) => (e.widget as RawImage).image == null)
          .length;
      if (blank > 0) blankFrames++;
      if (blank > mostBlank) mostBlank = blank;
      SchedulerBinding.instance.addPostFrameCallback(probe);
    }

    SchedulerBinding.instance.addPostFrameCallback(probe);
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => SongState(),
        child: MaterialApp(
            theme: floorPopTheme(Brightness.dark),
            home: EditionBinderPage(
                level: level,
                song: first.song,
                difficulty: first.difficulty,
                arrivals: Map.fromEntries(arrivals)))));
    await Future<void>.delayed(const Duration(seconds: 20));
    probing = false;
    // The engine hands over frame timings in batches.
    await Future<void>.delayed(const Duration(seconds: 2));
    SchedulerBinding.instance.removeTimingsCallback(collect);

    final summary = FrameTimingSummarizer(timings).summary;
    binding.reportData = {
      'binder_landing': {
        ...summary,
        'frames_probed': frames,
        'frames_with_blank_jackets': blankFrames,
        'most_blank_jackets': mostBlank,
      }
    };
    debugPrint('BINDER ${binding.reportData}');
  }, semanticsEnabled: false);
}
