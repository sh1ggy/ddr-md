/// Name: ChartScrollerConstantDefaultTest
/// Description: The CONSTANT window is derived from the saved read speed
/// (R = k × 1000 / N) on every load and on-tap, snapped DOWN to the 10ms grid.
library;

import 'package:ddr_md/components/song/notes/chart_chrome.dart';
import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart' as constants;
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

Widget _scroller({Key? key, int chartBpm = 180}) => ChartScroller(
      key: key,
      steps: _steps(),
      mode: Modes.singles,
      songLength: 6,
      chartBpm: chartBpm,
      bpms: [Bpm(st: 0, ed: 10, val: chartBpm)],
      stops: const [],
    );

// The window the scroller handed the CONSTANT chip.
double chipMs(WidgetTester tester) =>
    tester.widget<ConstantChip>(find.byType(ConstantChip)).ms;

// The travel law's exact window for a read speed, before grid snapping.
double _exactMs(int readSpeed) => 370.0 * 1000.0 / readSpeed;

Future<void> _open(WidgetTester tester, {required Key key}) async {
  await tester.pumpWidget(_host(_scroller(key: key)));
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  setUp(() async {
    await Settings.setInt(Settings.constantOnKey, 1);
  });

  testWidgets('read speed 370 opens on CONSTANT\'s own 1000ms default',
      (tester) async {
    // The identity the whole derivation is anchored on: k = 370 means a 1000ms
    // window IS read speed 370.
    await Settings.setInt(Settings.chosenReadSpeedKey, 370);
    await _open(tester, key: const ValueKey('370'));
    expect(chipMs(tester), 1000);
  });

  testWidgets('an off-grid read speed snaps DOWN to the tighter window',
      (tester) async {
    // 600 → 616.67ms exact. Flooring gives 610ms (equivalent ~607, meets 600);
    // rounding to nearest would give 620ms (~597) and open the preview reading
    // slower than the saved preference.
    await Settings.setInt(Settings.chosenReadSpeedKey, 600);
    await _open(tester, key: const ValueKey('600'));
    expect(chipMs(tester), 610);
    expect(chipMs(tester), lessThan(_exactMs(600)));
  });

  testWidgets('the derived window always reads at or above the saved speed',
      (tester) async {
    // Sweep the dial: whatever the saved speed, the window's equivalent read
    // speed (370000/N) must never fall below it, and must be the TIGHTEST 10ms
    // step for which that holds.
    for (final speed in [100, 250, 333, 400, 555, 600, 750, 888, 1000]) {
      await Settings.setInt(Settings.chosenReadSpeedKey, speed);
      await _open(tester, key: ValueKey('sweep-$speed'));
      final ms = chipMs(tester);
      expect(ms % 10, 0, reason: 'window must sit on the cabinet 10ms grid');
      expect(370000.0 / ms, greaterThanOrEqualTo(speed.toDouble()),
          reason: 'window for $speed must read at least that fast');
      expect(370000.0 / (ms - 10), greaterThanOrEqualTo(speed.toDouble()),
          reason: 'a tighter step also qualifies, so $ms is not the lowest');
      expect(ms, lessThanOrEqualTo(_exactMs(speed)));
    }
  });

  testWidgets('a stale saved window does not outrank the read speed',
      (tester) async {
    // A window dialled last session against some other speed must not survive
    // into a preview whose saved read speed says otherwise.
    await Settings.setInt(Settings.chosenReadSpeedKey, 500);
    await Settings.setInt(Settings.constantMsKey, 2500);
    await _open(tester, key: const ValueKey('stale'));
    expect(chipMs(tester), 740);
  });

  testWidgets('switching CONSTANT on re-seeds from the read speed',
      (tester) async {
    await Settings.setInt(Settings.chosenReadSpeedKey, 500);
    await Settings.setInt(Settings.constantOnKey, 0);
    await _open(tester, key: const ValueKey('toggle'));

    // The chip only takes gestures once the options shade is open.
    await tester.tap(find.byKey(shadeTabKey));
    await tester.pumpAndSettle();

    // Drag the window well off the derived value, then cycle the modifier: the
    // on-tap must land back on the saved speed's window rather than resuming the
    // dragged one.
    await tester.drag(find.byType(ConstantChip), const Offset(120, 0));
    await tester.pump();
    final dragged = chipMs(tester);
    expect(dragged, isNot(740), reason: 'drag should have moved the window');

    await tester.tap(find.byType(ConstantChip)); // off
    await tester.pump();
    await tester.tap(find.byType(ConstantChip)); // on → re-seed
    await tester.pump();
    expect(chipMs(tester), 740);
  });

  testWidgets('a read speed with no saved preference falls back to the default',
      (tester) async {
    // "Never set" (0) derives from the app's default read speed, not from a
    // bare 1000ms — so it lands on exactly the window that default would.
    await Settings.setInt(Settings.chosenReadSpeedKey, 0);
    await _open(tester, key: const ValueKey('unset'));
    expect(chipMs(tester), 610,
        reason: 'unset must derive from the ${constants.chosenReadSpeed} '
            'default, giving the same window as saving it explicitly');
  });
}
