/// Tests the DDR WORLD SPEED TYPE derivation — REAL SPEED (the cabinet's
/// ScrollSpeed) divides the dialled number by the song's `bpmmax`, which the app
/// reconstructs as the highest BPM the chart SUSTAINS for >= 2 seconds. Brief
/// soflan spikes are excluded, so they don't shrink the multiplier.
///
/// Worked example is SMASH: the WORLD cabinet stores bpmmin=80 / bpmmax=160,
/// even though the chart flashes 320 momentarily. Because that 320 isn't
/// sustained, the divisor is 160, and REAL SPEED 600 reads:
///   round(600 * 100 / 160) = x3.75  ->  main section 160 * 3.75 = 600,
/// matching HI-SPEED x3.75 exactly — the arcade-correct feel. A prior revision
/// divided by the raw note-stream peak (320), halving the read speed to ~300, a
/// value the cabinet has no data for. See docs/ddr-world-speed.md.
library;

import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chart_scroller_constant_test.dart' show badgeRead;

ChartSteps _steps() => const ChartSteps(notes: [
      StepNote(beat: 0, second: 0, col: 0, type: StepType.tap),
      StepNote(beat: 4, second: 2, col: 1, type: StepType.tap),
    ]);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// A SMASH-shaped chart: a long [mainBpm] section, a brief [spikeBpm] flash
/// under the 2s sustain threshold, and the playhead parked in [headBpm] (which
/// section the badge reads). The spike is short, so bpmmax = mainBpm.
Widget _smash({
  required int mainBpm,
  required int spikeBpm,
  required int slowBpm,
  required int headBpm,
  required Key key,
}) {
  // Playhead starts at 0; put the section we want the badge to read first.
  // Spike is 1.0s (< 2s sustain), main and slow are long.
  return ChartScroller(
    key: key,
    steps: _steps(),
    mode: Modes.singles,
    songLength: 30,
    chartBpm: mainBpm,
    minBpm: slowBpm,
    maxBpm: spikeBpm, // true_max: preserved, but NOT the divisor
    bpms: [
      Bpm(st: 0, ed: 1, val: headBpm), // playhead sits here (1s window is fine)
      Bpm(st: 1, ed: 12, val: mainBpm), // long sustained main tempo
      Bpm(st: 12, ed: 12.8, val: spikeBpm), // 0.8s transient spike
      Bpm(st: 12.8, ed: 22, val: mainBpm),
      Bpm(st: 22, ed: 30, val: slowBpm),
    ],
    stops: const [],
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  setUp(() async {
    await Settings.setInt(Settings.constantOnKey, 0);
  });

  testWidgets('REAL SPEED ignores a transient spike: SMASH reads the full 600',
      (tester) async {
    // Divisor = sustained peak = mainBpm 160 (the 320 flash lasts 0.8s < 2s).
    //   REAL SPEED 600 -> round(600*100/160) = x3.75 -> head 160*3.75 = 600.
    await Settings.setInt(Settings.chartPreviewSpeedTypeKey, 0); // REAL SPEED
    await Settings.setInt(Settings.chartPreviewScrollSpeedKey, 600);

    await tester.pumpWidget(_host(_smash(
      mainBpm: 160,
      spikeBpm: 320,
      slowBpm: 80,
      headBpm: 160,
      key: const ValueKey('real'),
    )));
    await tester.pump(const Duration(milliseconds: 16));

    expect(badgeRead(tester), 600,
        reason: 'the 320 spike is not sustained, so the divisor is 160');
  });

  testWidgets('REAL SPEED and HI-SPEED agree on SMASH at matching numbers',
      (tester) async {
    // The point of the fix: REAL SPEED 600 and HI-SPEED x3.75 read the SAME.
    await Settings.setInt(Settings.chartPreviewSpeedTypeKey, 1); // HI-SPEED
    await Settings.setInt(Settings.chartPreviewHispeedKey, 375);

    await tester.pumpWidget(_host(_smash(
      mainBpm: 160,
      spikeBpm: 320,
      slowBpm: 80,
      headBpm: 160,
      key: const ValueKey('hi'),
    )));
    await tester.pump(const Duration(milliseconds: 16));

    expect(badgeRead(tester), 600,
        reason: 'HI-SPEED x3.75 reads 600, same as REAL SPEED 600');
  });

  testWidgets('a SUSTAINED fast section IS the divisor, not a spike',
      (tester) async {
    // Distinguish sustained from transient. Here 320 is held 10s, so it counts
    // as the sustained peak and becomes the divisor. REAL SPEED 600 ->
    // round(600*100/320) = x1.88; the 160 head then reads 160*1.88 = 301. This
    // is correct: the cabinet's bpmmax for such a chart really is 320.
    await Settings.setInt(Settings.chartPreviewSpeedTypeKey, 0);
    await Settings.setInt(Settings.chartPreviewScrollSpeedKey, 600);

    await tester.pumpWidget(_host(ChartScroller(
      key: const ValueKey('sustained'),
      steps: _steps(),
      mode: Modes.singles,
      songLength: 20,
      chartBpm: 160,
      minBpm: 160,
      maxBpm: 320,
      bpms: [
        Bpm(st: 0, ed: 1, val: 160), // playhead here
        Bpm(st: 1, ed: 20, val: 320), // 19s -> sustained -> divisor
      ],
      stops: const [],
    )));
    await tester.pump(const Duration(milliseconds: 16));

    expect(badgeRead(tester), 301,
        reason: 'a fast section held past the 2s threshold is the divisor');
  });

  testWidgets('the fast head section reads faster than the dialled number',
      (tester) async {
    // With divisor = 160 (spike excluded), parking in the 320 flash reads
    // 320 * 3.75 = 1200 — genuinely faster, uncapped, like a cabinet. This is
    // the arcade feel the old raw-max divisor flattened away.
    await Settings.setInt(Settings.chartPreviewSpeedTypeKey, 0);
    await Settings.setInt(Settings.chartPreviewScrollSpeedKey, 600);

    await tester.pumpWidget(_host(_smash(
      mainBpm: 160,
      spikeBpm: 320,
      slowBpm: 80,
      headBpm: 320, // playhead in the fast flash
      key: const ValueKey('fast'),
    )));
    await tester.pump(const Duration(milliseconds: 16));

    expect(badgeRead(tester), 1200,
        reason: 'the fast section reads localBpm x mod (320 x 3.75), uncapped');
  });

  testWidgets('on a constant-BPM chart REAL SPEED equals its number',
      (tester) async {
    await Settings.setInt(Settings.chartPreviewSpeedTypeKey, 0);
    await Settings.setInt(Settings.chartPreviewScrollSpeedKey, 600);

    await tester.pumpWidget(_host(ChartScroller(
      key: const ValueKey('flat-real'),
      steps: _steps(),
      mode: Modes.singles,
      songLength: 20,
      chartBpm: 160,
      minBpm: 160,
      maxBpm: 160,
      bpms: [Bpm(st: 0, ed: 20, val: 160)],
      stops: const [],
    )));
    await tester.pump(const Duration(milliseconds: 16));

    expect(badgeRead(tester), 600);
  });

  testWidgets('falls back to dominant when no segment clears the sustain window',
      (tester) async {
    // A chart too short for any tempo to reach 2s: divisor falls back to the
    // dominant chartBpm (160), so REAL SPEED 600 reads 600.
    await Settings.setInt(Settings.chartPreviewSpeedTypeKey, 0);
    await Settings.setInt(Settings.chartPreviewScrollSpeedKey, 600);

    await tester.pumpWidget(_host(ChartScroller(
      key: const ValueKey('fallback'),
      steps: _steps(),
      mode: Modes.singles,
      songLength: 2,
      chartBpm: 160,
      bpms: [
        Bpm(st: 0, ed: 0.5, val: 160),
        Bpm(st: 0.5, ed: 1.5, val: 320), // 1s, under threshold
      ],
      stops: const [],
    )));
    await tester.pump(const Duration(milliseconds: 16));

    expect(badgeRead(tester), 600,
        reason: 'no sustained segment -> divisor falls back to dominant 160');
  });

  _readoutTests();
}

// --- The min–core–max readout: three numbers on any spread; folds only when
// --- all three coincide (true constant BPM). Arcade-accurate. -------------

/// The REAL SPEED trio label as rendered under the dial ("min–core–max").
String? _trioLabel(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .where((s) => RegExp(r'^\d+–\d+–\d+$').hasMatch(s))
      .toList();
  return texts.isEmpty ? null : texts.first;
}

void _readoutTests() {
  testWidgets('REAL SPEED shows all three even when min == core', (tester) async {
    // min == core (both 160), max sustained 320. Cabinet still renders three.
    await Settings.setInt(Settings.chartPreviewSpeedTypeKey, 0);
    await Settings.setInt(Settings.chartPreviewScrollSpeedKey, 600);

    await tester.pumpWidget(_host(ChartScroller(
      key: const ValueKey('min-eq-core'),
      steps: _steps(),
      mode: Modes.singles,
      songLength: 20,
      chartBpm: 160,
      minBpm: 160,
      maxBpm: 320,
      bpms: [
        Bpm(st: 0, ed: 1, val: 160),
        Bpm(st: 1, ed: 20, val: 320), // sustained -> divisor 320
      ],
      stops: const [],
    )));
    await tester.pump(const Duration(milliseconds: 16));

    // divisor 320 -> x1.88; 160*1.88=301, 320*1.88=602.
    expect(_trioLabel(tester), '301–301–602');
  });

  testWidgets('REAL SPEED shows all three even when core == max', (tester) async {
    // A plain soflan: slow 80, main/dominant 160 held throughout, no faster
    // sustained section, so core == max == 160.
    await Settings.setInt(Settings.chartPreviewSpeedTypeKey, 0);
    await Settings.setInt(Settings.chartPreviewScrollSpeedKey, 600);

    await tester.pumpWidget(_host(ChartScroller(
      key: const ValueKey('core-eq-max'),
      steps: _steps(),
      mode: Modes.singles,
      songLength: 20,
      chartBpm: 160,
      minBpm: 80,
      maxBpm: 160,
      bpms: [
        Bpm(st: 0, ed: 10, val: 160),
        Bpm(st: 10, ed: 20, val: 80),
      ],
      stops: const [],
    )));
    await tester.pump(const Duration(milliseconds: 16));

    // divisor 160 -> x3.75; 80*3.75=300, 160*3.75=600, 160*3.75=600.
    expect(_trioLabel(tester), '300–600–600');
  });

  testWidgets('constant-BPM chart folds the trio to one number', (tester) async {
    // The only case that collapses: a true constant-BPM chart (min==core==max).
    // min==core or core==max still show all three (tested above).
    await Settings.setInt(Settings.chartPreviewSpeedTypeKey, 0);
    await Settings.setInt(Settings.chartPreviewScrollSpeedKey, 600);

    await tester.pumpWidget(_host(ChartScroller(
      key: const ValueKey('flat-trio'),
      steps: _steps(),
      mode: Modes.singles,
      songLength: 20,
      chartBpm: 160,
      minBpm: 160,
      maxBpm: 160,
      bpms: [Bpm(st: 0, ed: 20, val: 160)],
      stops: const [],
    )));
    await tester.pump(const Duration(milliseconds: 16));

    // Folds to "600"; the trio regex must NOT match it.
    expect(_trioLabel(tester), isNull);
  });

  testWidgets('HI-SPEED hides the trio', (tester) async {
    await Settings.setInt(Settings.chartPreviewSpeedTypeKey, 1);
    await Settings.setInt(Settings.chartPreviewHispeedKey, 375);

    await tester.pumpWidget(_host(ChartScroller(
      key: const ValueKey('hi-no-trio'),
      steps: _steps(),
      mode: Modes.singles,
      songLength: 20,
      chartBpm: 160,
      minBpm: 80,
      maxBpm: 160,
      bpms: [Bpm(st: 0, ed: 20, val: 160)],
      stops: const [],
    )));
    await tester.pump(const Duration(milliseconds: 16));

    expect(_trioLabel(tester), isNull,
        reason: 'HI-SPEED shows a bare multiplier, no scroll-speed trio');
  });
}
