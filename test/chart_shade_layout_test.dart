/// Name: Chart shade layout tests
/// Parent: ChartScroller
/// Description: Checks the preview menu on compact and wide phone viewports.
library;

import 'package:ddr_md/components/song/notes/chart_chrome.dart';
import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const chart = ChartSteps(notes: [
    StepNote(beat: 0, second: 0, col: 0, type: StepType.tap),
    StepNote(beat: 1, second: 0.5, col: 1, type: StepType.tap),
  ]);

  for (final size in [
    const Size(320, 568),
    const Size(375, 667),
    const Size(430, 932),
    const Size(812, 375),
  ]) {
    testWidgets('shade fits $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: const EdgeInsets.only(top: 24, bottom: 16),
          ),
          child: Scaffold(
            body: ChartScroller(
              steps: chart,
              mode: Modes.singles,
              songLength: 10,
              chartBpm: 120,
              headerBuilder: (context, patternsButton) =>
                  const SizedBox(height: 64),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(menuTabKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      final shade = tester.getRect(find.byType(SettingsShade));
      final transport = tester.getRect(find.byType(SpeedPane));
      final scroller = tester.getRect(find.byType(SingleChildScrollView));
      expect(shade.left, greaterThanOrEqualTo(0));
      expect(shade.right, lessThanOrEqualTo(size.width));
      expect(shade.bottom, lessThanOrEqualTo(transport.top));
      expect(scroller.right, lessThan(shade.right));
      expect(find.byType(RawScrollbar), findsOneWidget);
      expect(tester.widget<RawScrollbar>(find.byType(RawScrollbar))
          .thumbVisibility, isNot(true));

      final scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      if (scrollable.position.maxScrollExtent > 0) {
        await tester.drag(
            find.byType(SingleChildScrollView), const Offset(0, -300));
        await tester.pump();
        expect(scrollable.position.pixels, greaterThan(0));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
