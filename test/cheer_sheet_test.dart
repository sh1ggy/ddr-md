/// Name: Cheer sheet tests
/// Parent: CheerSheet
/// Description: Compact cheer picking remains usable after a failed send,
/// and the success animation dismisses the sheet only after confirmation.
library;

import 'package:ddr_md/components/circle/cheer_sheet.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Circle extends CircleState {
  bool succeeds = false;
  Cheer? picked;
  @override
  Future<bool> cheerFor(CircleCredit credit, Cheer? cheer) async {
    picked = cheer;
    return succeeds;
  }
}

void main() {
  testWidgets('compact sheet retries failures and celebrates a confirmed cheer',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final circle = _Circle();
    final CircleCredit credit = (
      by: (
        id: 'friend',
        name: 'MIKA',
        ddrCode: '12345678',
        friend: true,
        live: null
      ),
      session: 'session',
      credit: 1,
      at: DateTime.now(),
      plays: const [],
      cheers: const [],
      mine: null,
    );
    await tester.pumpWidget(ChangeNotifierProvider<CircleState>.value(
      value: circle,
      child: MaterialApp(
          theme: floorPopTheme(Brightness.dark),
          home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => showCheerSheet(context, credit),
                      child: const Text('Cheer'),
                    )),
          )),
    ));
    await tester.tap(find.text('Cheer'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('LEGEND'));
    await tester.pumpAndSettle();
    expect(circle.picked, Cheer.legend);
    expect(find.text("Your cheer didn't send. Tap a stamp to try again."),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    circle.succeeds = true;
    await tester.ensureVisible(find.text('LEGEND'));
    await tester.tap(find.text('LEGEND'));
    await tester.pumpAndSettle();
    expect(find.text('Cheer MIKA'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
