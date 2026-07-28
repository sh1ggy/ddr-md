/// Tests that the DDR CONSTANT modifier does NOT alter the read speed shown on
/// the chart preview's tempo badge.
///
/// The cabinet's speed readout never references the CONSTANT display-time
/// value, and the scroll multiplier is identical whether CONSTANT is on or
/// off. CONSTANT changes
/// arrow VISIBILITY (a fixed wall-clock display window), not scroll velocity —
/// so the badge's READ value is always localBpm × mod. An earlier revision
/// clamped slow sections up to the window's "equivalent read speed" and showed
/// a "C###" badge; that speed floor is a fabrication and is what made
/// CONSTANT + a speed type feel wrong.
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

// The READ value on the tempo badge. Scoped to the badge so it can't be
// satisfied by the transport pane, and taken as the text immediately after the
// "READ" label so it can't pick up the neighbouring BPM number instead. A
// C prefix (which should never appear now) would fail the int.parse, so the
// helper also guards against the old behaviour regressing.
int badgeRead(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.descendant(
          of: find.byKey(tempoBadgeKey), matching: find.byType(Text)))
      .map((t) => t.data)
      .whereType<String>()
      .toList();
  final i = texts.indexOf('READ');
  if (i == -1 || i + 1 >= texts.length) {
    throw StateError('no READ stat on the tempo badge: $texts');
  }
  return int.parse(texts[i + 1]);
}

// True if any text on the badge carries the old CONSTANT "C###" read-speed
// prefix — which the arcade-accurate badge must never do.
bool _badgeHasCPrefix(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
        of: find.byKey(tempoBadgeKey), matching: find.byType(Text)))
    .any((t) => RegExp(r'^C\d+$').hasMatch(t.data ?? ''));

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

  testWidgets('CONSTANT does not change the badge read speed of a slow chart',
      (tester) async {
    // 150 BPM × x1.00 = 150. A cabinet leaves this untouched no matter the
    // CONSTANT window — CONSTANT only hides arrows, it never speeds them up.
    await tester.pumpWidget(_host(_scroller(chartBpm: 150)));
    await tester.pump(const Duration(milliseconds: 16));
    final withoutConstant = badgeRead(tester);

    await Settings.setInt(Settings.constantOnKey, 1);
    await Settings.setInt(Settings.constantMsKey, 1000);
    await tester.pumpWidget(
        _host(_scroller(chartBpm: 150, key: const ValueKey('on'))));
    await tester.pump(const Duration(milliseconds: 16));

    expect(badgeRead(tester), withoutConstant,
        reason: 'CONSTANT must not alter the tempo badge read speed');
    expect(_badgeHasCPrefix(tester), isFalse,
        reason: 'the fabricated "C###" read-speed floor must not return');
  });

  testWidgets('the badge always reads localBpm x mod, CONSTANT on or off',
      (tester) async {
    // 300 BPM × x2.00 (read-speed pref 600) = 600. Same with CONSTANT on.
    await Settings.setInt(Settings.chosenReadSpeedKey, 600);
    await Settings.setInt(Settings.constantOnKey, 0);
    await tester.pumpWidget(
        _host(_scroller(chartBpm: 300, key: const ValueKey('off'))));
    await tester.pump(const Duration(milliseconds: 16));
    expect(badgeRead(tester), 600);
    expect(_badgeHasCPrefix(tester), isFalse);

    await Settings.setInt(Settings.constantOnKey, 1);
    await Settings.setInt(Settings.constantMsKey, 3000);
    await tester.pumpWidget(
        _host(_scroller(chartBpm: 300, key: const ValueKey('on'))));
    await tester.pump(const Duration(milliseconds: 16));
    expect(badgeRead(tester), 600);
    expect(_badgeHasCPrefix(tester), isFalse);
  });
}
