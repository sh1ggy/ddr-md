import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a new best collects the card; a better one earns only new layers', () {
    final at = DateTime.utc(2026, 10, 30);
    List<String> gains(ChartBest? before, ChartBest after) => [
          for (final g in cardGains(
              song: 'MAX 300',
              mode: Modes.singles,
              difficulty: 'EXPERT',
              before: before,
              after: after,
              playedAt: at,
              syncedAt: at))
            '${g.layer.name}:${g.from}>${g.to}'
        ];
    const aa =
        (score: 960000, grade: Grade.aaPlus, lamp: ClearLamp.fc, flare: 'V');
    expect(gains(null, aa), ['card:>']);
    // LIFE4 to FC keeps the silver frame; AA+ to AA stays unfoiled.
    expect(
        gains(
            (score: 950000, grade: Grade.aa, lamp: ClearLamp.life4, flare: 'V'),
            aa),
        isEmpty);
    expect(
        gains(
            aa,
            mergeBest(aa, (
              score: 995000,
              grade: Grade.aaa,
              lamp: ClearLamp.pfc,
              flare: 'IV'
            ))),
        ['finish:AA+>AAA', 'frame:fc>pfc']);
  });
}
