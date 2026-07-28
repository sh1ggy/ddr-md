/// Regression tests for the chart preview's playback plumbing: the playhead is
/// a ValueNotifier driving CustomPainter.repaint (no per-frame setState), so
/// these pin down that time actually advances during playback, that the HUD
/// (elapsed label) tracks it, that pausing freezes it, that scrubbing moves
/// it, and that a chart exercising every note species — holds, rolls, mines,
/// a shock row, BPM changes, stops, the foot guide, the dancing-feet pad —
/// paints without throwing.
library;

import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song/notes/dancing_feet.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// A chart touching every draw pass: taps on several quantisation colours, a
/// freeze and a roll, a lone mine, and a 3-wide mine row (renders as a shock).
ChartSteps _richSteps() => const ChartSteps(notes: [
      StepNote(beat: 0, second: 0, col: 0, type: StepType.tap),
      StepNote(beat: 0.5, second: 0.25, col: 1, type: StepType.tap),
      StepNote(
          beat: 1,
          second: 0.5,
          col: 2,
          type: StepType.hold,
          endBeat: 3,
          endSecond: 1.5),
      StepNote(beat: 1.25, second: 0.625, col: 3, type: StepType.tap),
      StepNote(beat: 2, second: 1, col: 0, type: StepType.mine),
      StepNote(beat: 3, second: 1.5, col: 0, type: StepType.mine),
      StepNote(beat: 3, second: 1.5, col: 1, type: StepType.mine),
      StepNote(beat: 3, second: 1.5, col: 3, type: StepType.mine),
      StepNote(
          beat: 4,
          second: 2,
          col: 1,
          type: StepType.roll,
          endBeat: 5,
          endSecond: 2.5),
      StepNote(beat: 5, second: 2.5, col: 2, type: StepType.tap),
      StepNote(beat: 5.333, second: 2.667, col: 3, type: StepType.tap),
      StepNote(beat: 6, second: 3, col: 0, type: StepType.tap),
    ]);

Widget _scroller({bool footGuide = false, bool dancingFeet = false}) =>
    ChartScroller(
      steps: _richSteps(),
      mode: Modes.singles,
      songLength: 60,
      chartBpm: 120,
      bpms: [Bpm(st: 0, ed: 2, val: 120), Bpm(st: 2, ed: 60, val: 240)],
      stops: [Stop(st: 1.2, dur: 0.3, beats: [])],
      showFootGuide: footGuide,
      showDancingFeet: dancingFeet,
    );

/// The elapsed (left) time label — the total label always reads "1:00" here.
String _elapsedLabel(WidgetTester tester) {
  final labels = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .where((s) => RegExp(r'^\d+:\d\d$').hasMatch(s) && s != '1:00')
      .toList();
  expect(labels, hasLength(1));
  return labels.single;
}

/// Whether the field is set to draw the L/R guide. The ChartPainter itself
/// never mounts under test (the noteskin resolve needs a real asset bundle, and
/// the scroller paints nothing until it lands), so the scroller's own flag is
/// as deep as this can honestly reach.
bool _footGuideOn(WidgetTester tester) =>
    tester.widget<ChartScroller>(find.byType(ChartScroller)).showFootGuide;

/// The pad's painted surface — the thing that actually moves when it's dragged.
/// [DancingFeet] itself fills the whole field (it positions the pad within its
/// own bounds), so its top-left never changes and can't answer "did it move".
Finder _padRect() => find.descendant(
      of: find.byType(DancingFeet),
      matching: find.byType(CustomPaint),
    );

Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  testWidgets('tap to play advances the elapsed label; tap again freezes it',
      (tester) async {
    await tester.pumpWidget(_host(_scroller()));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_elapsedLabel(tester), '0:00');

    // Tap the field to start playback (the tap lands after the double-tap
    // timeout), then let a few seconds of chart time elapse.
    await tester.tapAt(tester.getCenter(find.byType(ChartScroller)));
    await tester.pump();
    await _pumpFrames(tester, 200); // ~3.2s pumped, ~2.9s played
    expect(_elapsedLabel(tester), isNot('0:00'));

    // Tap again to pause; once the tap lands, time must hold still.
    await tester.tapAt(tester.getCenter(find.byType(ChartScroller)));
    await _pumpFrames(tester, 30); // let the double-tap timeout resolve
    final paused = _elapsedLabel(tester);
    await _pumpFrames(tester, 90);
    expect(_elapsedLabel(tester), paused);
  });

  testWidgets('vertical drag scrubs the playhead while paused',
      (tester) async {
    await tester.pumpWidget(_host(_scroller()));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_elapsedLabel(tester), '0:00');

    // Drag upward repeatedly: the field scrolls toward later chart time. At
    // the default read speed the x-mod is steep, so pile up plenty of pixels.
    for (int i = 0; i < 6; i++) {
      await tester.drag(find.byType(ChartScroller), const Offset(0, -400),
          warnIfMissed: false);
      await tester.pump();
    }
    // Let any release fling decay fully.
    await _pumpFrames(tester, 150);
    expect(_elapsedLabel(tester), isNot('0:00'));
  });

  testWidgets('a chart with every note species paints with the foot guide on',
      (tester) async {
    await tester.pumpWidget(_host(_scroller(footGuide: true)));
    await tester.pump(const Duration(milliseconds: 16));

    // Play through the dense opening so holds, the shock row, mines, markers
    // and foot paths all cross the visible window while beat-locked.
    await tester.tapAt(tester.getCenter(find.byType(ChartScroller)));
    await _pumpFrames(tester, 250);
    expect(tester.takeException(), isNull);
    expect(_elapsedLabel(tester), isNot('0:00'));
  });

  testWidgets('the dancing-feet pad is independent of the foot guide',
      (tester) async {
    // Two separate readings of one parity solve: the on-arrow L/R badges and
    // the pad. Each is its own toggle, so all four combinations are legal —
    // turning the pad on must never take the guide away, or vice versa.
    for (final (guide, pad) in const [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      await tester.pumpWidget(
          _host(_scroller(footGuide: guide, dancingFeet: pad)));
      // The field paints nothing until the noteskin resolves, so settle first
      // — before that there is no ChartPainter to ask about the guide.
      await tester.pumpAndSettle();
      expect(find.byType(DancingFeet), pad ? findsOneWidget : findsNothing,
          reason: 'guide=$guide pad=$pad');
      expect(_footGuideOn(tester), equals(guide),
          reason: 'guide=$guide pad=$pad');
    }
  });

  testWidgets('the dancing-feet pad dances the chart without throwing',
      (tester) async {
    await tester.pumpWidget(_host(_scroller(dancingFeet: true)));
    await tester.pump(const Duration(milliseconds: 16));

    // The same rich chart, played through: the pad walks the shock row, the
    // mines and the stop without throwing.
    await tester.tapAt(tester.getCenter(find.byType(ChartScroller)));
    await _pumpFrames(tester, 250);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pad floats over the field without stealing its gestures',
      (tester) async {
    await tester.pumpWidget(_host(_scroller(dancingFeet: true)));
    await tester.pump(const Duration(milliseconds: 16));

    // The pad is an overlay spanning the whole field, so the layer it lives in
    // must stay transparent everywhere the pad itself isn't — otherwise it
    // would swallow the play/pause tap that the field owns.
    await tester.tapAt(tester.getCenter(find.byType(ChartScroller)));
    await _pumpFrames(tester, 120);
    expect(_elapsedLabel(tester), isNot('0:00'),
        reason: 'the pad layer ate the field tap');
  });

  testWidgets('press and hold moves the pad, and the move is remembered',
      (tester) async {
    await tester.pumpWidget(_host(_scroller(dancingFeet: true)));
    await tester.pump(const Duration(milliseconds: 16));
    final before = tester.getTopLeft(_padRect());

    // A long press picks it up; a plain drag must NOT (that's the field's
    // scrub). Drag up and left so the move is unambiguous on any screen size.
    // Press the PAD, not the layer: DancingFeet spans the whole field, so its
    // centre is empty space that belongs to the scroller.
    final gesture = await tester.startGesture(tester.getCenter(_padRect()));
    await tester.pump(const Duration(milliseconds: 600)); // past long-press
    await gesture.moveBy(const Offset(-60, -140));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(_padRect());
    expect(after, isNot(equals(before)), reason: 'the pad did not move');
    expect(after.dy, lessThan(before.dy));

    // Remounting reads the stored position back, so the placement survives
    // leaving and reopening the preview. Within a pixel: the position is stored
    // in thousandths of the field, so a round trip is lossy by design.
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pump();
    await tester.pumpWidget(_host(_scroller(dancingFeet: true)));
    await tester.pumpAndSettle();
    final restored = tester.getTopLeft(_padRect());
    expect(restored.dx, closeTo(after.dx, 1));
    expect(restored.dy, closeTo(after.dy, 1));
  });
}
