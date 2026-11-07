/// Name: Cheer notification tests
/// Parent: CheerNotifications
/// Description: Existing cheers stay silent; new arrivals toast once and
/// disappear without taking space in the session card.
library;

import 'package:ddr_md/components/circle/cheer_notifications.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session extends SessionState {
  @override
  bool get active => true;
  @override
  PlaySession get session => PlaySession(
      'test-session', const Venue(1, 'Arcade'), DateTime(2026), null);
}

class _Circle extends CircleState {
  @override
  Future<void> poll() async {}
  void arrived(List<({String? id, String name, Cheer cheer})> cheers) {
    yours = [
      (
        by: null,
        session: 'test-session',
        credit: 1,
        at: DateTime(2026),
        plays: const [],
        cheers: cheers,
        mine: null
      )
    ];
    feedRevision++;
    notifyListeners();
  }
}

void main() {
  testWidgets('only new cheers toast, once, then dismiss', (tester) async {
    SharedPreferences.setMockInitialValues({Settings.circleBroadcastKey: 1});
    await Settings.init();
    final circle = _Circle();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<CircleState>.value(value: circle),
          ChangeNotifierProvider<SessionState>(create: (_) => _Session()),
        ],
        child: MaterialApp(
            theme: floorPopTheme(Brightness.dark),
            builder: (context, child) => CheerNotifications(child: child!),
            home: const Scaffold(body: Text('Your session')))));

    circle.arrived([(id: 'mika', name: 'MIKA', cheer: Cheer.clean)]);
    await tester.pump();
    expect(find.text('MIKA'), findsNothing);
    circle.arrived([
      (id: 'mika', name: 'MIKA', cheer: Cheer.clean),
      (id: 'tofu', name: 'TOFU', cheer: Cheer.legend)
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.text('TOFU · Credit 1'), findsOneWidget);
    expect(find.textContaining('MIKA'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('TOFU'), findsNothing);
    circle.arrived([
      (id: 'mika', name: 'MIKA', cheer: Cheer.clean),
      (id: 'tofu', name: 'TOFU', cheer: Cheer.legend)
    ]);
    await tester.pump();
    expect(find.textContaining('TOFU'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
