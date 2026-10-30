/// Name: Chart timing option tests
/// Parent: ChartScroller
/// Description: Pins the display dial scale and shared audio clock behaviour,
/// persistence migration, and separation of display from judgement vs music.
library;

import 'package:ddr_md/components/song/notes/chart_chrome.dart';
import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('display +1.0 delays alignment by 10ms, +0.1 by 1ms', () {
    expect(visualOffsetSeconds(1), -.01);
    expect(visualOffsetSeconds(.1), -.001);
    expect(visualOffsetSeconds(-1), .01);
    expect(visualOffsetSeconds(0), 0);
    final effect = debugVisualOffsetEffect(1.5);
    expect(effect.offsetSecond - effect.neutralSecond, closeTo(-.015, 1e-9));
    expect(effect.repaints, isTrue);
    expect(debugVisualOffsetEffect(0).repaints, isFalse);
  });

  test('display is ±5.0 in 0.1 steps; relative audio correction is whole ms',
      () {
    expect(visualOffsetClamp(99), 5);
    expect(visualOffsetClamp(-99), -5);
    expect(visualOffsetClamp(1.24), 1.2);
    expect(visualOffsetClamp(1.26), 1.3);
    expect(audioOffsetClampMs(999), 50);
    expect(audioOffsetClampMs(-999), -50);
    expect(audioOffsetClampMs(12.4), 12);
    expect(audioOffsetClampMs(12.6), 13);
    expect(visualOffsetLabel(0), '+0.0');
    expect(visualOffsetLabel(1.5), '+1.5');
    expect(visualOffsetLabel(-1.5), '-1.5');
    expect(audioOffsetLabel(20), '+20ms');
    expect(audioOffsetLabel(-20), '-20ms');
  });

  test('disabled sync ignores both stored dials', () {
    expect(
        debugGatedVisualOffsetSeconds(
            arcadeSyncOn: false, units: 5, audioMs: 50),
        0);
    expect(debugGatedAudioOffsetSeconds(arcadeSyncOn: false, ms: 50), 0);
    expect(debugGatedVisualOffsetSeconds(arcadeSyncOn: true, units: 5), -.05);
    expect(debugGatedAudioOffsetSeconds(arcadeSyncOn: true, ms: 50), -.05);
  });

  test('audio calibration shifts both clocks without creating a ghost gap', () {
    for (final audioMs in [-20.0, 0.0, 20.0]) {
      final judgement =
          debugGatedAudioOffsetSeconds(arcadeSyncOn: true, ms: audioMs);
      final field = debugGatedVisualOffsetSeconds(
          arcadeSyncOn: true, units: 1.5, audioMs: audioMs);
      expect(judgement, closeTo(-audioMs / 1000, 1e-9));
      expect(field - judgement, closeTo(-.015, 1e-9));
      expect(
          debugGatedVisualOffsetSeconds(
              arcadeSyncOn: true, units: 0, audioMs: audioMs),
          judgement);
    }
  });

  testWidgets('migrates the old visual dial and keeps visual out of audio sync',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      Settings.arcadeSyncOnKey: 1,
      Settings.chartPreviewVisualOffsetKey: 15,
      Settings.chartPreviewAudioOffsetMsKey: -20,
      Settings.chartPreviewOffsetForBiasKey: 2000,
    });
    await Settings.init();
    final prefs = await SharedPreferences.getInstance();
    addTearDown(prefs.clear);

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChartScroller(
      steps: const ChartSteps(notes: [
        StepNote(beat: 0, second: 0, col: 0, type: StepType.tap),
      ]),
      mode: Modes.singles,
      songLength: 10,
      chartBpm: 120,
      sync: Sync.fromJson({'bias_ms': 20}),
    ))));
    await tester.tap(find.byKey(menuTabKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    TimingOffsetChip visual() => tester.widget(find.byKey(visualOffsetChipKey));
    ArcadeSyncHeader header() => tester.widget(find.byKey(arcadeSyncTileKey));
    expect(prefs.getInt(Settings.chartPreviewAudioOffsetMsKey), 20);
    expect(visual().value, 1.5);
    expect(visual().valueLabel, '+1.5');
    expect(prefs.getInt(Settings.chartPreviewVisualOffsetMsKey), 15);
    expect(prefs.getInt(Settings.chartPreviewTimingFormatKey), 2);
    expect(header().summary, 'on the beat');

    await tester.ensureVisible(find.byKey(visualOffsetChipKey));
    await tester.pump();
    await tester.drag(find.byKey(visualOffsetChipKey), const Offset(26, 0));
    await tester.pump();
    expect(visual().value, greaterThan(1.5));
    expect(header().summary, 'on the beat');

    await tester.drag(find.byKey(audioOffsetChipKey), const Offset(26, 0));
    await tester.pump();
    expect(header().summary, startsWith('SLOW by'));

    await tester.tap(find.byKey(visualOffsetChipKey));
    await tester.pump();
    expect(visual().value, 0);
    expect(prefs.getInt(Settings.chartPreviewVisualOffsetMsKey), 0);
    await tester.ensureVisible(find.byKey(arcadeSyncTileKey));
    await tester.pump();
    await tester.tap(find.byKey(arcadeSyncTileKey));
    await tester.pump();
    expect(header().summary, 'FAST by 20.0ms');
    expect(tester.takeException(), isNull);
  });
}
