/// Name: Chart sync hit rendering tests
/// Parent: ChartPainter
/// Description: Ghost receptors and arrow impacts follow the audio clock while
/// their positions follow the field's visual clock, including tempo and stops.
library;

import 'dart:ui' as ui;

import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song/notes/chart_timing.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingSkin extends VectorNoteskin {
  final receptors = <double>[];
  final arrows = <double>[];
  final flashes = <({double y, double age})>[];
  final bodies = <({double head, double tail})>[];

  @override
  void paintReceptor(Canvas canvas, double x, double y, double size,
          NoteDir dir, double glow) =>
      receptors.add(y);

  @override
  void paintArrow(Canvas canvas, double x, double y, double size, NoteDir dir,
          double beat) =>
      arrows.add(y);

  @override
  void paintNoteFlash(Canvas canvas, double x, double y, double size,
          NoteDir dir, double progress) =>
      flashes.add((y: y, age: progress * .12));

  @override
  void paintHoldBody(Canvas canvas, double x, double head, double tail,
          double size, NoteDir dir, bool isRoll) =>
      bodies.add((head: head, tail: tail));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const size = Size(430, 932);
  const tap = StepNote(beat: 2, second: 1, col: 0, type: StepType.tap);

  ChartPainter painter({
    double second = 0.97,
    double visual = 0,
    double? audio,
    _RecordingSkin? skin,
    List<StepNote> notes = const [tap],
    ChartTiming? timing,
    bool playing = true,
  }) {
    final clock = ValueNotifier(second);
    addTearDown(clock.dispose);
    return ChartPainter(
      notes: notes,
      holds: notes.where((n) => n.isHold).toList(),
      shockNotes: const {},
      shocks: const [],
      bpmMarkers: const [],
      stopMarkers: const [],
      feet: const {},
      footPrev: const {},
      dirs: kSingleDirs,
      colMap: const [0, 1, 2, 3],
      playhead: clock,
      pxPerSecond: 300,
      pxPerBeat: 150,
      timing: timing ?? ChartTiming.build(const [], const []),
      columnCount: 4,
      skin: skin ?? _RecordingSkin(),
      playing: playing,
      visualOffset: visual,
      hitOffset: audio,
    );
  }

  void paint(ChartPainter p) {
    final recorder = ui.PictureRecorder();
    p.paint(Canvas(recorder), size);
    recorder.endRecording().dispose();
  }

  test('ghost row uses the same receptor art at the actual audio hit position',
      () {
    for (final audio in [-.02, 0.0, .02]) {
      final skin = _RecordingSkin();
      final p = painter(skin: skin, visual: .04, audio: audio);
      paint(p);
      expect(skin.receptors.take(4), everyElement(56.0));
      expect(skin.receptors.skip(4), everyElement(closeTo(p.hitY(size), 1e-6)));
      expect(skin.receptors, hasLength(8));
      expect(p.hitY(size), closeTo(56 + (audio - .04) * 300, 1e-6));
    }
  });

  test(
      'arrows remain past alignment until the audio tick, then flash at the ghost',
      () {
    final beforeSkin = _RecordingSkin();
    final before = painter(skin: beforeSkin, visual: .04, audio: .02);
    paint(before);
    expect(beforeSkin.arrows, hasLength(1));
    expect(beforeSkin.arrows.single, lessThan(56));
    expect(beforeSkin.flashes, isEmpty);

    final hitSkin = _RecordingSkin();
    final hit = painter(second: .981, skin: hitSkin, visual: .04, audio: .02);
    paint(hit);
    expect(hitSkin.arrows, isEmpty);
    expect(hitSkin.flashes.single.y, closeTo(hit.hitY(size), 1e-6));
    expect(hitSkin.flashes.single.age, closeTo(.001, 1e-6));
  });

  test('audio advance hits below the receptors before visual alignment', () {
    final skin = _RecordingSkin();
    final p = painter(second: .981, audio: .02, skin: skin);
    paint(p);
    expect(skin.arrows, isEmpty);
    expect(skin.flashes.single.y, greaterThan(56));
    expect(skin.flashes.single.age, closeTo(.001, 1e-6));
  });

  test('audio calibration keeps the ghost gap fixed while delaying the hit',
      () {
    for (final audioMs in [-20.0, 0.0, 20.0]) {
      final field = debugGatedVisualOffsetSeconds(
          arcadeSyncOn: true, units: 1, audioMs: audioMs);
      final judgement =
          debugGatedAudioOffsetSeconds(arcadeSyncOn: true, ms: audioMs);
      final skin = _RecordingSkin();
      final p = painter(
          second: 1 + audioMs / 1000 + .001,
          visual: field,
          audio: judgement,
          skin: skin);
      paint(p);
      expect(p.hitY(size), closeTo(59, 1e-6));
      expect(skin.flashes.single.y, closeTo(59, 1e-6));
      expect(skin.flashes.single.age, closeTo(.001, 1e-6));
    }
  });

  test('ghost matches the arrow at its hit across BPM changes and a stop', () {
    final timing = ChartTiming.build(
      [Bpm(st: 0, ed: 2, val: 120), Bpm(st: 2, ed: 5, val: 240)],
      [Stop(st: 1, dur: .2, beats: const [])],
    );
    for (final playing in [false, true]) {
      for (final t in [.99, 1.1, 1.99, 2.01]) {
        final p = painter(
            second: t - .02,
            audio: .02,
            visual: -.03,
            timing: timing,
            playing: playing);
        expect(p.hitY(size), closeTo(p.rowY(t, size), 1e-6));
      }
    }
  });

  test('holds anchor and finish at the audio target', () {
    const hold = StepNote(
        beat: 2,
        second: 1,
        col: 0,
        type: StepType.hold,
        endBeat: 4,
        endSecond: 2);
    final skin = _RecordingSkin();
    final p = painter(
        second: 1.1, audio: -.02, visual: .04, notes: const [hold], skin: skin);
    paint(p);
    expect(skin.bodies.single.head, closeTo(p.hitY(size), 1e-6));
    expect(skin.arrows.single, closeTo(p.hitY(size), 1e-6));
  });

  test('a ghost above the visible chart is clipped, never wrapped below', () {
    final skin = _RecordingSkin();
    final p = painter(visual: .5, audio: -.1, skin: skin);
    expect(p.hitY(size), lessThan(0));
    paint(p);
    expect(skin.receptors, hasLength(4));
    expect(skin.receptors, everyElement(56.0));
  });

  test('disabling sync restores a single receptor row and visual arrivals', () {
    final skin = _RecordingSkin();
    final p = painter(visual: .04, skin: skin);
    paint(p);
    expect(skin.receptors, hasLength(4));
    expect(skin.flashes.single.y, 56);
    expect(p.hitSecond, p.second);
  });
}
