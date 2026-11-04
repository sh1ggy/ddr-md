/// Name: Cheer note layout tests
/// Parent: CheerNote
/// Description: Switching between presets never moves any avatar, including
/// nearby notes when the row wraps on a narrow screen.
library;

import 'package:ddr_md/components/circle/cheer_stamp.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 450.0]) {
    testWidgets('avatars stay evenly spaced at $width', (tester) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<Offset>? baseline;
      for (final cheer in Cheer.values) {
        await tester.pumpWidget(MaterialApp(
          theme: floorPopTheme(Brightness.dark),
          home: Scaffold(
              body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    CheerNote(cheer, name: 'SHIGGY'),
                    const CheerNote(Cheer.clean, name: 'M'),
                    const CheerNote(Cheer.legend, name: 'LONGNAME'),
                  ]))),
        ));
        final heads = find.byType(CircleAvatar);
        final centers = [
          for (var i = 0; i < 3; i++) tester.getCenter(heads.at(i))
        ];
        baseline ??= centers;
        expect(centers, baseline, reason: '${cheer.label} moved a chathead');
        expect(centers[1].dx - centers[0].dx, 128);
        if (width == 450) expect(centers[2].dx - centers[1].dx, 128);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
