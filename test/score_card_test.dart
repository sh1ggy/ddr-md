import 'package:ddr_md/components/song/scores/score_card.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, Score score) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ScoreCard(score: score))),
    );
  }

  // Asset names of every Image widget currently in the tree.
  Iterable<String> imageAssets(WidgetTester tester) =>
      tester.widgetList<Image>(find.byType(Image)).map(
          (img) => (img.image as AssetImage).assetName);

  const date = '2026-07-12T10:00:00.000';

  testWidgets('renders grade, full-combo and flare icons', (tester) async {
    await pumpCard(
      tester,
      const Score(
        date: date,
        songTitle: 'Test',
        mode: Modes.singles,
        flare: 'IX',
        score: 995000,
        marvelous: 99,
        perfect: 1,
        great: 0,
        good: 0,
        miss: 0,
      ),
    );
    expect(
      imageAssets(tester),
      containsAll([
        'assets/icons/rank_aaa.png', // 995,000 -> AAA
        'assets/icons/cl_perf.png', // Marv/Perfect only -> PFC
        'assets/icons/flare_9.png',
      ]),
    );
    expect(find.textContaining('Flare'), findsNothing);
  });

  testWidgets('grades without art fall back to the label', (tester) async {
    await pumpCard(
      tester,
      const Score(
        date: date,
        songTitle: 'Test',
        mode: Modes.singles,
        score: 720000, // B: no icon art
        marvelous: 10,
        perfect: 10,
        great: 10,
        good: 10,
        miss: 10,
      ),
    );
    expect(find.text('B'), findsOneWidget);
    expect(imageAssets(tester), isEmpty); // no FC (misses), no flare
  });

  testWidgets('no full-combo lamp when a judgment count is missing',
      (tester) async {
    await pumpCard(
      tester,
      const Score(
        date: date,
        songTitle: 'Test',
        mode: Modes.singles,
        score: 990000,
        marvelous: 100,
        // perfect..miss missing: a hidden miss could break the combo.
      ),
    );
    expect(imageAssets(tester), ['assets/icons/rank_aaa.png']);
  });

  testWidgets('unparseable flare keeps the text fallback', (tester) async {
    await pumpCard(
      tester,
      const Score(
        date: date,
        songTitle: 'Test',
        mode: Modes.singles,
        flare: 'XYZ',
      ),
    );
    expect(find.text('Flare XYZ'), findsOneWidget);
  });

  testWidgets('camera cue shown only when a proof image was saved',
      (tester) async {
    await pumpCard(
      tester,
      const Score(
        date: date,
        songTitle: 'Test',
        mode: Modes.singles,
        imagePath: 'scores/proof.png',
      ),
    );
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);

    await pumpCard(
      tester,
      const Score(date: date, songTitle: 'Test', mode: Modes.singles),
    );
    expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
  });

  testWidgets('tapping the card fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScoreCard(
            score: const Score(
                date: date, songTitle: 'Test', mode: Modes.singles),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ScoreCard));
    expect(tapped, isTrue);
  });
}
