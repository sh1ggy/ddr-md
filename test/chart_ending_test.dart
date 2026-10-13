/// Name: Chart ending regression tests
/// Parent: ChartScroller
/// Description: Plays real chart endings beyond short song metadata.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final available = File('assets/songlist.json').existsSync();
  final songs = available
      ? jsonDecode(File('assets/songlist.json').readAsStringSync()) as List
      : const [];
  for (final (name, mode, difficulty) in [
    ('Trill auf G', Modes.singles, 'hard'),
    ('Jetcoaster Windy', Modes.singles, 'hard'),
    ('Adularia', Modes.singles, 'hard'),
    ('Vajra', Modes.singles, 'challenge'),
    ('Vajra', Modes.doubles, 'hard'),
    ('PARANOiA', Modes.singles, 'hard'),
  ]) {
    testWidgets('$name ${mode.name} $difficulty finishes its last note',
        (tester) async {
      await tester.runAsync(() => SpriteNoteskin.tryLoad());
      final song = songs.firstWhere((s) => s['name'] == name);
      final data =
          jsonDecode(File('assets/steps/$name.json').readAsStringSync());
      final steps = ChartSteps.fromJson(
          data['charts'][mode == Modes.singles ? 'sp' : 'dp'][difficulty]);
      final tail = steps.notes
          .fold(0.0, (double end, n) => math.max(end, n.endSecond ?? n.second));
      final length = (song['song_length'] as num).toDouble();
      expect(tail, greaterThan(length));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ChartScroller(
        steps: steps,
        mode: mode,
        songLength: length,
        chartBpm: 180,
        initialSecond: length - 0.5,
      ))));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      ChartPainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<ChartPainter>()
          .single;
      await tester.tapAt(const Offset(400, 250));
      await tester.pump(const Duration(milliseconds: 350));
      expect(painter().playing, isTrue);
      for (var i = 0; i < ((tail - length + 10) * 20).ceil(); i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(painter().playhead.value, closeTo(tail + 1, 0.001));
      expect(painter().playing, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, skip: !available || !File('assets/steps/$name.json').existsSync());
  }
}
