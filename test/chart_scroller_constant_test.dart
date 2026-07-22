/// Tests for the DDR CONSTANT modifier's effect on the read speed surfaced by
/// the chart preview's tempo badge. CONSTANT is a wall-clock display window; it
/// converts to an ARCADE-equivalent read speed R = 370000 / ms — the
/// community-measured cabinet guideline (925ms ↔ SPEED 400, 740ms ↔ SPEED 500,
/// 1000ms ↔ SPEED 370). The live read speed is max(local BPM × mod, R): the
/// window only ever HIDES arrows, so it raises the effective read of slow
/// sections and leaves faster ones untouched.
library;

import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChartSteps _steps() => const ChartSteps(notes: [
      StepNote(beat: 0, second: 0, col: 0, type: StepType.tap),
      StepNote(beat: 4, second: 2, col: 1, type: StepType.tap),
    ]);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _scroller({required int chartBpm, Key? key}) => ChartScroller(
      key: key,
      steps: _steps(),
      mode: Modes.singles,
      songLength: 6,
      chartBpm: chartBpm,
      bpms: [Bpm(st: 0, ed: 10, val: chartBpm)],
      stops: const [],
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  testWidgets('CONSTANT window converts to its arcade-equivalent read speed',
      (tester) async {
    await Settings.setInt(Settings.chosenReadSpeedKey, 150);
    await Settings.setInt(Settings.constantOnKey, 1);
    await Settings.setInt(Settings.constantMsKey, 1000);
    // 150 BPM × 1.0x = 150 read; a 1000ms window reads like the cabinet's
    // C = 370000/1000 = 370, which outpaces 150 and binds.
    await tester.pumpWidget(_host(_scroller(chartBpm: 150)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('C370'), findsOneWidget);
  });

  testWidgets('halving the window doubles the equivalent read speed',
      (tester) async {
    await Settings.setInt(Settings.chosenReadSpeedKey, 150);
    await Settings.setInt(Settings.constantOnKey, 1);
    await Settings.setInt(Settings.constantMsKey, 500);
    await tester.pumpWidget(
        _host(_scroller(chartBpm: 150, key: const ValueKey('half'))));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('C740'), findsOneWidget);
  });

  testWidgets(
      'a window longer than the arcade natural travel does not bind the read',
      (tester) async {
    // 300 BPM × 2.0x = 600 read: on the cabinet arrows are visible only
    // 370/600 ≈ 0.62s, well inside a 3000ms window (equivalent C = 123).
    // CONSTANT must pass the faster natural read through unchanged.
    await Settings.setInt(Settings.chosenReadSpeedKey, 600);
    await Settings.setInt(Settings.constantOnKey, 1);
    await Settings.setInt(Settings.constantMsKey, 3000);
    await tester.pumpWidget(
        _host(_scroller(chartBpm: 300, key: const ValueKey('unbound'))));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('600'), findsWidgets); // tempo badge (and transport pane)
    expect(find.text('C600'), findsNothing);
    expect(find.text('C123'), findsNothing);
    expect(find.text('123'), findsNothing);
  });

  testWidgets('CONSTANT off never shows a C-prefixed read speed',
      (tester) async {
    await Settings.setInt(Settings.chosenReadSpeedKey, 150);
    await Settings.setInt(Settings.constantOnKey, 0);
    await Settings.setInt(Settings.constantMsKey, 1000);
    await tester.pumpWidget(
        _host(_scroller(chartBpm: 150, key: const ValueKey('off'))));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('150'), findsWidgets);
    expect(find.text('C370'), findsNothing);
  });
}
