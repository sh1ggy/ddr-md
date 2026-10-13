/// Name: Shock dancer rendering
/// Parent: Parity shock planner / dancers
/// Description: Exercises both renderers during each shock support method.
library;

import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ddr_md/components/song/notes/dancing_feet.dart';
import 'package:ddr_md/components/song/notes/pad_dancer.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/parity_shocks.dart';
import 'package:ddr_md/models/steps_model.dart';

void main() {
  for (final method in ShockMethod.values) {
    testWidgets('both dancers render ${method.name} support', (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final playhead = ValueNotifier(1.3);
      addTearDown(playhead.dispose);
      final stances = [
        ParityStance(
            second: 1,
            leftHeel: method == ShockMethod.heelToe ? 2 : 0,
            leftToe: method == ShockMethod.heelToe ? 2 : 0,
            rightHeel: 3,
            rightToe: 3,
            stepped: {method == ShockMethod.heelToe ? 2 : 0}),
        const ParityStance(
            second: 1.6,
            leftHeel: 0,
            leftToe: 0,
            rightHeel: 3,
            rightToe: 3,
            stepped: {3})
      ];
      final notes = [
        StepNote(
            beat: 2,
            second: 1,
            col: method == ShockMethod.heelToe ? 2 : 0,
            type: StepType.tap),
        for (var c = 0; c < 4; c++)
          StepNote(beat: 2.6, second: 1.3, col: c, type: StepType.mine),
        const StepNote(beat: 3.2, second: 1.6, col: 3, type: StepType.tap)
      ];
      final plan = ShockEvasion(
          second: 1.3,
          start: 1.08,
          end: 1.52,
          method: method,
          support: ParityFoot.left,
          padX: 0,
          up: true,
          transfer: false,
          feasible: true);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          home: RepaintBoundary(
              key: key,
              child: Scaffold(
                  body: Row(children: [
                Expanded(
                    child: CustomPaint(
                        painter: PadDancerPainter(
                            stances: stances,
                            notes: notes,
                            shockPlans: [plan],
                            playhead: playhead,
                            columnCount: 4,
                            form: DancerForm.minimal),
                        child: const SizedBox.expand())),
                Expanded(
                    child: DancingFeet(
                        stances: stances,
                        playhead: playhead,
                        columnCount: 4,
                        shocks: const [1.3],
                        shockPlans: [plan],
                        form: DancerForm.minimal))
              ])))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (Platform.environment['DDR_SHOCK_SCREENSHOTS'] == '1') {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/ddr-shock-${method.name}.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      for (final t in [1.05, 1.15, 1.25, 1.35, 1.45, 1.55, 1.65]) {
        playhead.value = t;
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
