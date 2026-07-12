import 'package:ddr_md/components/song/song_chart.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpRadar(WidgetTester tester, Radar radar) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SongRadarChart(radar: radar))),
    );
    // Expand the ExpansionTile so the chart builds.
    await tester.tap(find.text('Groove Radar'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders with typical values within the 100 frame',
      (tester) async {
    await pumpRadar(
      tester,
      Radar(stream: 45, voltage: 60, air: 20, freeze: 55, chaos: 30),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders boss-song values exceeding 100 without errors',
      (tester) async {
    await pumpRadar(
      tester,
      Radar(stream: 226, voltage: 262, air: 100, freeze: 94, chaos: 312),
    );
    expect(tester.takeException(), isNull);
  });
}
