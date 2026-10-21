import 'package:ddr_md/components/session/set_summary_card.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a set is averaged against its charts, blended with the level model',
      () {
    final t = DateTime.utc(2026, 10, 1, 18);
    RecentPlay play(String id, int hoursAgo, int score) => RecentPlay(
        konamiId: id,
        title: id,
        song: id,
        mode: Modes.singles,
        difficulty: 'EXPERT',
        playedAt: t.subtract(Duration(hours: hoursAgo)),
        score: score);
    ScoreRecord best(String id, int score) => ScoreRecord(
        id: 'eamuse:$id:singles:EXPERT',
        source: ScoreRecordSource.eamuse,
        song: id,
        konamiId: id,
        title: id,
        mode: Modes.singles,
        difficulty: 'EXPERT',
        score: score,
        rank: '',
        flareRank: '',
        updatedAt: t);
    final s = summarizeLatestSet(
      [
        // Today's set, newest first.
        play('a', 0, 960000),
        play('new', 0, 900000),
        // An earlier visit, 20,000 under its chart's best.
        play('a', 48, 940000),
      ],
      [best('a', 960000), best('b', 950000), best('c', 940000)],
      (_, __, ___) => 15,
    )!;

    // Level 15 bests average 950,000, less 20,000: a model of 930,000.
    // 'new' takes it outright; 'a' blends its one play of 940,000 with the
    // model counted twice, 933,333.
    expect(s.points.length, 2);
    expect(s.average, 930000);
    expect(s.usual, closeTo((930000 + 933333) / 2, 1));
    expect(s.bests, 1);
  });
}
