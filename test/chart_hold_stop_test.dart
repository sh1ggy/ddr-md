/// Name: Hold and stop rendering tests
/// Parent: ChartPainter / ChartScroller
/// Description: Freezes stay beat-locked in playback and include stop duration
/// when paused; vertical drags follow that expanded timing map in both directions.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song/notes/chart_timing.dart';
import 'package:ddr_md/components/song/notes/ddr_atlas.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingSkin extends VectorNoteskin {
  final bodies = <({double head, double tail})>[];

  @override
  void paintHoldBody(Canvas canvas, double x, double yHead, double yTail,
      double size, NoteDir dir, bool isRoll) {
    bodies.add((head: yHead, tail: yTail));
  }
}

({double head, double tail}) _paintHold(
    StepNote hold, ChartTiming timing, double second,
    {bool playing = true, double? constantMs}) {
  final skin = _RecordingSkin();
  final playhead = ValueNotifier(second);
  final painter = ChartPainter(
    notes: [hold],
    holds: [hold],
    shockNotes: const {},
    shocks: const [],
    bpmMarkers: const [],
    stopMarkers: const [],
    feet: const {},
    footPrev: const {},
    dirs: kSingleDirs,
    colMap: const [0, 1, 2, 3],
    playhead: playhead,
    pxPerSecond: 288,
    pxPerBeat: 96,
    timing: timing,
    columnCount: 4,
    skin: skin,
    playing: playing,
    constantMs: constantMs,
  );
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(430, 932));
  recorder.endRecording().dispose();
  playhead.dispose();
  return skin.bodies.single;
}

void main() {
  final timing = ChartTiming.build(
    [Bpm(st: 0, ed: 10, val: 120)],
    [Stop(st: 2, dur: 1, beats: const [])],
  );
  const hold = StepNote(
      beat: 4,
      second: 2,
      col: 0,
      type: StepType.hold,
      endBeat: 4.5,
      endSecond: 3.25);

  test('playback freeze stays still through a stop, then drains', () {
    final start = _paintHold(hold, timing, 2);
    final middle = _paintHold(hold, timing, 2.5);
    final resumed = _paintHold(hold, timing, 3);
    expect(start.tail - start.head, closeTo(48, 1e-6));
    expect(middle, start);
    expect(resumed, start);
    final draining = _paintHold(hold, timing, 3.125);
    expect(draining.head, start.head);
    expect(draining.tail - draining.head, closeTo(24, 1e-6));
    final end = _paintHold(hold, timing, 3.25);
    expect(end.tail, closeTo(end.head, 1e-6));
  });

  test('approaching freeze shares the field stop without extra length', () {
    final before = _paintHold(hold, timing, 1.5);
    expect(before.tail - before.head, closeTo(48, 1e-6));
    final constant = _paintHold(hold, timing, 2.5, constantMs: 500);
    expect(constant, _paintHold(hold, timing, 2.5));
  });

  test('paused freeze includes the remaining stop duration', () {
    final start = _paintHold(hold, timing, 2, playing: false);
    final middle = _paintHold(hold, timing, 2.5, playing: false);
    final resumed = _paintHold(hold, timing, 3, playing: false);
    expect(start.tail - start.head, closeTo(48 + 288, 1e-6));
    expect(middle.tail - middle.head, closeTo(48 + 144, 1e-6));
    expect(resumed.tail - resumed.head, closeTo(48, 1e-6));
  });

  test('playback length comes from beats despite rounded tail seconds', () {
    const rounded = StepNote(
      beat: 4,
      second: 2,
      col: 0,
      type: StepType.hold,
      endBeat: 4.5,
      endSecond: 3.249,
    );
    final start = _paintHold(rounded, timing, 2);
    final duringStop = _paintHold(rounded, timing, 2.5);
    expect(start.tail - start.head, closeTo(48, 1e-6));
    expect(duringStop, start);
    final end = _paintHold(rounded, timing, rounded.endSecond!);
    expect(end.tail, closeTo(end.head, 1e-6));
  });

  test('freeze spanning a stop gains no extra playback length', () {
    const spanning = StepNote(
        beat: 3,
        second: 1.5,
        col: 0,
        type: StepType.hold,
        endBeat: 6,
        endSecond: 4);
    final before = _paintHold(spanning, timing, 1);
    expect(before.tail - before.head, closeTo(3 * 96, 1e-6));
    final stopped = _paintHold(spanning, timing, 2.5);
    expect(stopped.tail - stopped.head, closeTo(2 * 96, 1e-6));
  });

  testWidgets('freeze pixels are independent of the tap palette',
      (tester) async {
    await tester.runAsync(() async {
      final atlas = await DdrAtlas.tryLoad();
      expect(atlas, isNotNull);
      Future<List<int>> freezePixels(bool arrowBlink) async {
        final playhead = ValueNotifier(1.0);
        final painter = ChartPainter(
          notes: const [hold],
          holds: const [hold],
          shockNotes: const {},
          shocks: const [],
          bpmMarkers: const [],
          stopMarkers: const [],
          feet: const {},
          footPrev: const {},
          dirs: kSingleDirs,
          colMap: const [0, 1, 2, 3],
          playhead: playhead,
          pxPerSecond: 288,
          pxPerBeat: 96,
          timing: timing,
          columnCount: 4,
          skin: const VectorNoteskin(),
          playing: true,
          arrowBlink: arrowBlink,
          ddr: atlas,
        );
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), const Size(384, 720));
        final picture = recorder.endRecording();
        final image = await picture.toImage(384, 720);
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = rgba!.buffer.asUint8List();
        // The entire approaching freeze, clear of the receptors above it.
        final pixels = <int>[
          for (var y = 145; y < 410; y++)
            ...bytes.sublist(y * 384 * 4, (y * 384 + 96) * 4),
        ];
        image.dispose();
        picture.dispose();
        playhead.dispose();
        return pixels;
      }

      expect(await freezePixels(false), await freezePixels(true));
    });
  },
      skip: !File('assets/noteskin/arrow-atlas.png').existsSync() ||
          !File('assets/noteskin/freeze-palette.png').existsSync());

  final songFile = File('assets/songs/Go For The Top.json');
  final stepsFile = File('assets/steps/Go For The Top.json');
  test('Go For The Top SP Challenge stop holds use the playback beat map', () {
    final song = SongInfo.fromJson(jsonDecode(songFile.readAsStringSync()));
    final chart = song.charts.first;
    final map = ChartTiming.build(chart.bpms, chart.stops);
    final data = jsonDecode(stepsFile.readAsStringSync());
    final notes = ChartSteps.fromJson(data['charts']['sp']['challenge']).notes;
    var checked = 0;
    for (final n in notes.where((n) => n.isHold)) {
      for (final stop in chart.stops) {
        if ((stop.st - n.second).abs() > 0.001 ||
            stop.st + stop.dur > n.endSecond!) {
          continue;
        }
        final start = _paintHold(n, map, n.second);
        final middle = _paintHold(n, map, stop.st + stop.dur / 2);
        final expected = (n.endBeat! - n.beat) * 96;
        expect(start.tail - start.head, closeTo(expected, 1e-6));
        expect(middle.tail, closeTo(start.tail, 1e-6));
        final paused = _paintHold(n, map, n.second, playing: false);
        final pausedLength =
            (map.beatAt(n.endSecond!) - map.beatAt(n.second)) * 96 +
                stop.dur * 288;
        expect(paused.tail - paused.head, closeTo(pausedLength, 1e-6));
        checked++;
      }
    }
    expect(checked, greaterThan(0));
  }, skip: !songFile.existsSync() || !stepsFile.existsSync());

  testWidgets(
      'vertical scrub crosses a stop with the finger in both directions',
      (tester) async {
    await tester.runAsync(() => SpriteNoteskin.tryLoad());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ChartScroller(
        steps: const ChartSteps(notes: [
          StepNote(beat: 3.8, second: 1.9, col: 0, type: StepType.tap),
          hold,
        ]),
        mode: Modes.singles,
        songLength: 10,
        chartBpm: 120,
        bpms: [Bpm(st: 0, ed: 10, val: 120)],
        stops: [Stop(st: 2, dur: 1, beats: const [])],
        initialSecond: 1.9,
      )),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    ChartPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<ChartPainter>()
        .single;
    double position() {
      final p = painter();
      return p.timing.beatAt(p.second) * p.pxPerBeat +
          p.timing.stopSecondsAt(p.second) * p.pxPerSecond;
    }

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    final before = position();
    // Travel beyond the whole band, then return to the exact starting point.
    final distance = painter().pxPerSecond + painter().pxPerBeat;
    await gesture.moveBy(Offset(0, -distance));
    await tester.pump();
    expect(painter().second, greaterThan(3));
    expect(position() - before, closeTo(distance, 1e-5));
    await gesture.moveBy(Offset(0, distance));
    await tester.pump();
    expect(position(), closeTo(before, 1e-5));
    await gesture.cancel();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
