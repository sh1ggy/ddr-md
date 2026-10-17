import 'dart:io';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/eamuse.dart';
import 'package:flutter_test/flutter_test.dart';

const _img = '/game/ddr/ddrworld/images/playdata';

String _chart(String difficulty, String score, String rank, String lamp,
        String skill, String flare) =>
    '''
<div class="rank $difficulty"><div class="data">
  <div class="data_score">$score</div>
  <div class="data_rank"><img src="$_img/$rank.png"></div>
  <div class="data_clearkind"><img src="$_img/$lamp.png"></div>
  <div class="data_flareskill">$skill</div>
  <div class="data_flarerank"><img src="$_img/$flare.png"></div>
</div></div>''';

String _page(int pages, String charts) => '''
<html><body><div id="music_list"><div class="music-card">
  <div class="chart"><a class="music_info" href="/game/ddr/ddrworld/playdata/music_detail.html?index=dD6DOI1lDI8o90iO006Dl96D1doDdQ69&style=0">
    <div class="music-name"> ＭＡＸ　300 </div></a></div>
  <div class="playdata">$charts</div>
</div></div>
<div id="paging_box">${'<div class="page_num"><a>1</a></div>' * pages}</div>
</body></html>''';

void main() {
  test('parses played charts and skips the rest', () {
    final page = parseEamusePage(
        _page(
            3,
            '<div class="rank"><div class="data"></div></div>'
            '${_chart('BASIC', '', 'rank_s_nodisp', 'cl_nodisp', '', 'flare_nodisp')}'
            '${_chart('EXPERT', '982840', 'rank_s_aa_p', 'cl_good', '492', 'flare_1')}'
            '${_chart('CHALLENGE', '1000000', 'rank_aaa', 'cl_marv', '---', 'flare_ex')}'),
        Modes.doubles,
        DateTime(2026));
    expect(page.pages, 3);
    expect([
      for (final r in page.records)
        (
          r.id,
          r.difficulty,
          r.score,
          r.rank,
          r.clearLamp,
          r.flareRank,
          r.flareSkill
        )
    ], [
      (
        'eamuse:dD6DOI1lDI8o90iO006Dl96D1doDdQ69:doubles:EXPERT',
        'EXPERT',
        982840,
        'AA+',
        ClearLamp.fc,
        'I',
        492
      ),
      (
        'eamuse:dD6DOI1lDI8o90iO006Dl96D1doDdQ69:doubles:CHALLENGE',
        'CHALLENGE',
        1000000,
        'AAA',
        ClearLamp.mfc,
        'EX',
        null
      ),
    ]);
    expect(eamuseTitleKey(page.records.first.title), 'max 300');
    expect(
        () => parseEamusePage(
            '<a class="errinfo_btn" id="login" href="/login.html">',
            Modes.singles,
            DateTime(2026)),
        throwsA(isA<EamuseSignedOut>()));
  });

  test('requests are spaced by the gap and a refusal stops the sync', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final times = <DateTime>[];
    server.listen((request) {
      times.add(DateTime.now());
      final double = request.uri.path.contains('double');
      request.response
        ..statusCode = double ? 503 : 200
        ..write(_page(
            2,
            _chart('BASIC', '900000', 'rank_s_aa', 'cl_clear', '100',
                'flare_none')))
        ..close();
    });
    final saved = <ScoreRecord>[];
    final sync = EamuseSync(
      cookies: '',
      titleIndex: {'max 300': 'MAX 300'},
      save: (records) async => saved.addAll(records),
      host: 'http://${server.address.host}:${server.port}',
    );
    await expectLater(
        sync.run((_, __, ___) {}), throwsA(isA<EamuseUnavailable>()));
    await server.close();
    // Two singles pages, then the first doubles page answers 503.
    expect(times, hasLength(3));
    for (var i = 1; i < times.length; i++) {
      expect(times[i].difference(times[i - 1]),
          greaterThanOrEqualTo(EamuseSync.gap));
    }
    expect(saved.map((r) => r.song), everyElement('MAX 300'));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
