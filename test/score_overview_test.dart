import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/score_overview.dart';
import 'package:flutter_test/flutter_test.dart';

SongInfo _song(String name, String version) => SongInfo(
      ssc: false,
      version: version,
      name: name,
      title: name,
      titletranslit: name,
      artist: '',
      artisttranslit: '',
      songLength: 100,
      perChart: false,
      singles: Difficulty(hard: 15, challenge: 17),
      doubles: Difficulty(),
      radarSingles: const {},
      radarDoubles: const {},
      singlesNotecounts: Difficulty(),
      doublesNotecounts: Difficulty(),
      charts: const [],
    );

ScoreRecord _record(String song, String difficulty, int flare,
        [ClearLamp? lamp]) =>
    ScoreRecord(
      source: ScoreRecordSource.eamuse,
      song: song,
      title: song,
      mode: Modes.singles,
      difficulty: difficulty,
      clearLamp: lamp,
      flareSkill: flare,
      updatedAt: DateTime(2026),
    );

void main() {
  test('flare skill takes each group\'s best 30 and charts group by level', () {
    final songs = [
      for (var i = 0; i < 40; i++) _song('c$i', 'X3'),
      _song('w', 'A20'),
      _song('g', 'WORLD'),
    ];
    final records = [
      for (var i = 0; i < 40; i++) _record('c$i', 'EXPERT', 100 + i),
      _record('w', 'CHALLENGE', 500, ClearLamp.pfc),
      _record('g', 'EXPERT', 700, ClearLamp.mfc),
    ];

    final skill = flareSkill(records, songs, Modes.singles);
    expect(skill.groups[FlareGroup.classic]!.length, 30);
    expect(skill.groupTotal(FlareGroup.classic),
        [for (var i = 10; i < 40; i++) 100 + i].reduce((a, b) => a + b));
    expect(skill.total, skill.groupTotal(FlareGroup.classic) + 1200);

    final levels = chartsByLevel(records, songs, Modes.singles);
    expect(levels[15]!.charts, 42);
    expect(levels[15]!.played.length, 41);
    expect(levels[17]!.played.single.clearLamp, ClearLamp.pfc);
    expect(meanAndSd([90, 100, 110])!.mean, 100);
  });
}
