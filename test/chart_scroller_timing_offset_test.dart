/// Regression tests for the chart preview's two TIMING offset dials.
///
/// The two dials deliberately use DIFFERENT units, matching how the cabinet and
/// its players express them: VISUAL is the -5.0..+5.0 dial (表示タイミング),
/// AUDIO is whole milliseconds (判定タイミング, where players work in ~±10-20ms).
/// Conflating them is the mistake these tests exist to prevent.
///
/// The VISUAL sign convention is the other load-bearing part: the cabinet's own
/// guidance is many FAST → PLUS, many SLOW → MINUS. It is pinned from both ends
/// here (unit conversion and the rendered consequence) because an earlier
/// revision had it inverted.
library;

import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VISUAL dial', () {
    test('one unit is one 60fps frame of arrow travel (~16.67ms)', () {
      expect(visualOffsetSeconds(1), closeTo(1 / 60, 1e-9));
      expect(visualOffsetSeconds(0), 0);
      // Full dial is about +/-83ms, the right order for a display-lag fix.
      expect(visualOffsetSeconds(5.0), closeTo(0.0833, 1e-4));
    });

    test('clamps to +/-5.0 and snaps to the 0.1 grid', () {
      expect(visualOffsetClamp(9.9), 5.0);
      expect(visualOffsetClamp(-9.9), -5.0);
      expect(visualOffsetClamp(1.24), closeTo(1.2, 1e-9));
      expect(visualOffsetClamp(1.26), closeTo(1.3, 1e-9));
    });

    test('reads as a signed one-decimal dial, like the cabinet', () {
      expect(visualOffsetLabel(0), '+0.0');
      expect(visualOffsetLabel(1.5), '+1.5');
      expect(visualOffsetLabel(-2.3), '-2.3');
    });
  });

  group('AUDIO dial', () {
    test('is milliseconds, NOT the visual dial unit', () {
      // Guards the two dials being conflated: 10 on the AUDIO dial is 10ms,
      // whereas 10 on the VISUAL dial would be 10 frames (167ms).
      expect(audioOffsetLabel(10), '+10ms');
      expect(audioOffsetLabel(-20), '-20ms');
      expect(audioOffsetLabel(0), '+0ms');
    });

    test('clamps to +/-50ms in whole milliseconds', () {
      expect(audioOffsetClampMs(999), 50);
      expect(audioOffsetClampMs(-999), -50);
      // Players work in integers; there is no sub-ms dial.
      expect(audioOffsetClampMs(10.4), 10);
      expect(audioOffsetClampMs(10.6), 11);
    });

    test('covers the range players actually report using', () {
      // ~10-20ms typical, more on badly-synced songs — all inside the dial.
      for (final ms in [10.0, -10.0, 20.0, -20.0]) {
        expect(audioOffsetClampMs(ms), ms,
            reason: '${ms}ms must be reachable without clamping');
      }
    });
  });

  group('ARCADE SYNC gate', () {
    test('a stored offset is IGNORED while the gate is off', () {
      // The gate isn't only about hiding controls: an offset saved in an earlier
      // session must not silently shift the field or the tick once ARCADE SYNC
      // is switched back off. This is the exact code path the live state uses.
      expect(debugGatedVisualOffsetSeconds(arcadeSyncOn: false, units: 5.0), 0);
      expect(debugGatedAudioOffsetSeconds(arcadeSyncOn: false, ms: 50), 0);
    });

    test('the same stored offset applies once the gate is on', () {
      expect(debugGatedVisualOffsetSeconds(arcadeSyncOn: true, units: 5.0),
          closeTo(5.0 / 60, 1e-9));
      expect(debugGatedAudioOffsetSeconds(arcadeSyncOn: true, ms: 50),
          closeTo(0.05, 1e-9));
    });
  });

  group('rendered effect', () {
    test('PLUS advances the field reference — the FAST-bias correction', () {
      // The whole renderer keys off the painter's `second`, so this IS the
      // rendered effect: advancing the reference by dt is identical to pulling
      // every arrow dt closer to the receptor.
      final r = debugVisualOffsetEffect(3.0);
      expect(r.offsetSecond, greaterThan(r.neutralSecond),
          reason: 'PLUS is the cabinet correction for getting many FAST');
      expect(r.offsetSecond - r.neutralSecond, closeTo(3.0 / 60, 1e-9));
    });

    test('MINUS retards the field reference — the SLOW-bias correction', () {
      final r = debugVisualOffsetEffect(-3.0);
      expect(r.offsetSecond, lessThan(r.neutralSecond),
          reason: 'MINUS is the cabinet correction for getting many SLOW');
      expect(r.offsetSecond - r.neutralSecond, closeTo(-3.0 / 60, 1e-9));
    });

    test('changing the visual offset alone forces a repaint', () {
      // While PAUSED the playhead notifier never fires, so shouldRepaint is the
      // only thing that can report a dial change — without it, dragging VISUAL
      // would do nothing visible until playback resumed. Isolated to the offset:
      // the two painters share every other input by construction.
      expect(debugVisualOffsetEffect(3.0).repaints, isTrue);
    });

    test('a zero offset leaves the field bit-for-bit unchanged', () {
      final r = debugVisualOffsetEffect(0);
      expect(r.repaints, isFalse,
          reason: 'neutral must not invalidate the field');
      expect(r.offsetSecond, r.neutralSecond);
    });
  });
}
