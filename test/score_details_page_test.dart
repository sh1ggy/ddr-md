import 'package:ddr_md/components/song/scores/score_card.dart';
import 'package:ddr_md/components/song/scores/score_details_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const score = Score(
    date: '2026-07-12T10:00:00.000',
    songTitle: 'Test Song',
    mode: Modes.singles,
    difficulty: 'EXPERT',
    username: 'PLAYER',
    score: 995000,
    marvelous: 99,
    perfect: 1,
    great: 0,
    good: 0,
    miss: 0,
    maxCombo: 100,
  );

  Future<void> pumpPage(WidgetTester tester, Score score) async {
    await tester.pumpWidget(
      MaterialApp(home: ScoreDetailsPage(score: score)),
    );
    await tester.pump();
  }

  testWidgets('view mode shows the score card and no-image placeholder',
      (tester) async {
    await pumpPage(tester, score);
    expect(find.byType(ScoreCard), findsOneWidget);
    expect(find.text('Test Song'), findsWidgets);
    expect(find.text('No image was saved with this score.'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);
  });

  testWidgets('edit mode prefills fields from the score', (tester) async {
    await pumpPage(tester, score);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();

    // The read-only card is replaced by editable fields with the row values.
    expect(find.byType(ScoreCard), findsNothing);
    expect(find.widgetWithText(TextField, 'EXPERT'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'PLAYER'), findsOneWidget);
    expect(find.widgetWithText(TextField, '995000'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('closing edit mode discards and returns to the card',
      (tester) async {
    await pumpPage(tester, score);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'PLAYER'), 'OTHER');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.byType(ScoreCard), findsOneWidget);
    expect(find.text('PLAYER'), findsOneWidget);
    expect(find.text('OTHER'), findsNothing);
  });
}
