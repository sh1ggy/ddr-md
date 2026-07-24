/// Name: TickClock integration test
/// Parent: integration_test
/// Description: Drives the real SoLoud engine (desktop/device) to verify the
/// assist-tick clock: the silent carrier loads, its position advances
/// monotonically without wrapping, and scheduling stays anchored to it.
///
/// Run on macOS desktop:
///   flutter test integration_test/tick_clock_test.dart -d macos
library;

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ddr_md/components/song/notes/tick_clock.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('clock loads and advances monotonically past a loop boundary', () async {
    final clock = TickClock();
    await clock.load('assets/audio/assist_tick.wav');
    expect(clock.isReady, isTrue, reason: 'engine + sample should load');

    // Read the raw clock voice position over ~1.5s. The tick sample is far
    // shorter than that, so a looping carrier would wrap and go backwards; the
    // long silent carrier must not.
    final soloud = SoLoud.instance;
    // Reach into the same reading the scheduler uses via a short play/measure.
    clock.start(chartSecond: 0, rate: 1.0);
    double last = -1;
    bool everWentBackwards = false;
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final pos = clock.debugClockSecond();
      expect(pos, isNotNull);
      if (pos! < last - 0.001) everWentBackwards = true;
      last = pos;
    }
    expect(everWentBackwards, isFalse,
        reason: 'clock must be monotonic — no loop wrap');
    expect(last, greaterThan(1.0),
        reason: 'clock should have advanced ~1.5s, got $last');

    clock.dispose();
    expect(soloud.isInitialized, isTrue, reason: 'shared engine stays up');
  });

  test('scheduling fires ticks close to their target times', () async {
    final clock = TickClock();
    await clock.load('assets/audio/assist_tick.wav');

    // Rows at a steady 12 notes/sec for 2s — dense enough to matter.
    final rows = [for (var i = 1; i <= 24; i++) i / 12.0];
    clock.debugSetOnFire((chartSecond, clockError) {
      // Each fire records how far the audio clock was from the row's target at
      // release time; assert it stays sub-frame.
      expect(clockError.abs(), lessThan(0.02),
          reason: 'tick for $chartSecond fired ${clockError * 1000}ms off');
    });
    clock.setRows(rows);
    clock.start(chartSecond: 0, rate: 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 2400));
    expect(clock.debugFiredCount, rows.length,
        reason: 'every row must fire exactly once');
    clock.dispose();
  });
}
