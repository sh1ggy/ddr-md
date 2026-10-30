import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final height in [36.0, 48.0]) {
    testWidgets('plain-label pill tabs respond across their $height px segment',
        (tester) async {
      var selected = 0;
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: floorPopTheme(Brightness.dark),
        home: Scaffold(
          body: StatefulBuilder(
              builder: (context, update) => PillTabs<int>(
                    values: const [0, 1, 2],
                    tabs: const [
                      Text('Week'),
                      Text('Fortnight'),
                      Text('Month')
                    ],
                    selected: selected,
                    tabHeight: height,
                    onChanged: (value) => update(() {
                      selected = value;
                      taps++;
                    }),
                  )),
        ),
      ));
      for (final (index, label) in ['Week', 'Fortnight', 'Month'].indexed) {
        final target = find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first;
        final rect = tester.getRect(target);
        expect(rect.height, height);
        for (final point in [
          rect.topLeft + const Offset(3, 3),
          rect.topRight + const Offset(-3, 3),
          rect.bottomLeft + const Offset(3, -3),
          rect.bottomRight + const Offset(-3, -3),
        ]) {
          final previousTaps = taps;
          await tester.tapAt(point);
          await tester.pumpAndSettle();
          expect(selected, index);
          expect(taps, previousTaps + 1);
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
