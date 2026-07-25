/// Unit tests for beat-locked chart scrolling: the second→beat [ChartTiming]
/// map that makes the preview speed up on BPM rises and freeze on stops.
/// (Widget-level "renders without throwing" coverage lives in
/// chart_scroller_playback_test.dart's every-note-species case.)
library;

import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song/notes/chart_timing.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ChartTiming', () {
    test('empty without BPM data', () {
      expect(ChartTiming.build(const [], const []).isEmpty, isTrue);
    });

    test('constant BPM: beat advances linearly with time', () {
      // 120 BPM = 2 beats/sec over [0, 10) seconds.
      final t = ChartTiming.build([Bpm(st: 0, ed: 10, val: 120)], const []);
      expect(t.isEmpty, isFalse);
      expect(t.beatAt(0), closeTo(0, 1e-6));
      expect(t.beatAt(1), closeTo(2, 1e-6));
      expect(t.beatAt(5), closeTo(10, 1e-6));
    });

    test('BPM change: slope doubles at the transition', () {
      // 120 BPM for [0,4) then 240 BPM for [4,8). At 240 BPM = 4 beats/sec.
      final t = ChartTiming.build([
        Bpm(st: 0, ed: 4, val: 120),
        Bpm(st: 4, ed: 8, val: 240),
      ], const []);
      expect(t.beatAt(4), closeTo(8, 1e-6)); // 4s * 2 beats/s
      // One more second at the faster tempo adds 4 beats, not 2.
      expect(t.beatAt(5), closeTo(12, 1e-6));
    });

    test('stop: beat is held flat for the stop duration', () {
      // 120 BPM. A 1s stop begins at second 2 (beat 4). Real seconds 2..3 all
      // map to beat 4; time resumes advancing after.
      final t = ChartTiming.build(
        [Bpm(st: 0, ed: 10, val: 120)],
        [Stop(st: 2, dur: 1, beats: const [])],
      );
      expect(t.beatAt(2), closeTo(4, 1e-6));
      expect(t.beatAt(2.5), closeTo(4, 1e-6)); // frozen mid-stop
      expect(t.beatAt(3), closeTo(4, 1e-6)); // stop end
      expect(t.beatAt(4), closeTo(6, 1e-6)); // 1s of motion past the stop
    });

    test('secondAt inverts beatAt and lands past a stop', () {
      final t = ChartTiming.build(
        [Bpm(st: 0, ed: 10, val: 120)],
        [Stop(st: 2, dur: 1, beats: const [])],
      );
      // Beat 4 spans real seconds [2, 3] (the stop); secondAt resolves to the end.
      expect(t.secondAt(4), closeTo(3, 1e-6));
      expect(t.secondAt(6), closeTo(4, 1e-6));
    });
  });

  // The no-BPM-data path has no timing map, so it can't be a unit test; this
  // smoke test guards that the constant-time fallback still renders (the
  // every-note-species case in playback_test.dart always supplies BPMs).
  testWidgets('a chart with no BPM data still renders (constant-time fallback)',
      (tester) async {
    await tester.pumpWidget(_host(const ChartScroller(
      steps: ChartSteps(notes: [
        StepNote(beat: 0, second: 0, col: 0, type: StepType.tap),
        StepNote(beat: 4, second: 2, col: 1, type: StepType.tap),
      ]),
      mode: Modes.singles,
      songLength: 6,
      chartBpm: 150,
      bpms: [],
      stops: [],
    )));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });
}
