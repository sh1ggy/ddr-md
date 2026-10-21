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

  test(
      'requests are spaced by the gap, keep renewed cookies, and stop at a refusal',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final times = <DateTime>[];
    final sent = <String?>[];
    server.listen((request) {
      times.add(DateTime.now());
      sent.add(request.headers.value(HttpHeaders.cookieHeader));
      final double = request.uri.path.contains('double');
      if (times.length == 1) {
        request.response.cookies.add(Cookie('M573SSID', 'renewed'));
      }
      request.response
        ..statusCode = double ? 503 : 200
        ..write(_page(
            2,
            _chart('BASIC', '900000', 'rank_s_aa', 'cl_clear', '100',
                'flare_none')))
        ..close();
    });
    final saved = <ScoreRecord>[];
    final kept = <String>[];
    final sync = EamuseSync(
      cookies: 'M573SSID=old; visid=v',
      onCookies: (cookies) async => kept.addAll(cookies.map((c) => c.value)),
      titleIndex: {'max 300': 'MAX 300'},
      save: (records) async => saved.addAll(records),
      host: 'http://${server.address.host}:${server.port}',
    );
    await expectLater(sync.run((_, __) {}), throwsA(isA<EamuseUnavailable>()));
    await server.close();
    // Two singles pages, then the first doubles page answers 503.
    expect(times, hasLength(3));
    for (var i = 1; i < times.length; i++) {
      expect(times[i].difference(times[i - 1]),
          greaterThanOrEqualTo(EamuseSync.gap));
    }
    expect(saved.map((r) => r.song), everyElement('MAX 300'));
    expect(sent, [
      'M573SSID=old; visid=v',
      ...List.filled(2, 'M573SSID=renewed; visid=v')
    ]);
    expect(kept, ['renewed']);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('recent plays decide what a sync fetches', () {
    String row(String id, String date, String diff, String style,
            [String rank = '']) =>
        '''
<tr class="data"><td class="chart">
  <a href="/game/ddr/ddrworld/playdata/music_detail.html?index=$id&style=0&difficulty=3" class="music_info cboxelement">
  <div><div class="date">$date</div><div class="music-name">MAX 300</div>
  <div class="diff-style-container"><div class="diff $diff">$diff<div class="level">$style</div></div></div></div></a></td>
  <td class="score">970860</td><td class="rank">$rank</td></tr>''';
    const a = 'dD6DOI1lDI8o90iO006Dl96D1doDdQ69';
    final plays = parseEamuseRecent('''
<div id="search_result"><table><tbody>
${row(a, '2026-10-16 16:57:59', 'EXPERT', 'SINGLE')}
${row(a, '2026-10-16 16:55:06', 'EXPERT', 'SINGLE', '<img src="/img/rank_s_e.png">')}
${row(a, '2026-10-16 16:38:39', 'CHALLENGE', 'DOUBLE')}
</tbody></table></div>''');
    expect([
      for (final p in plays) (p.mode, p.difficulty, p.playedAt, p.score)
    ], [
      (Modes.singles, 'EXPERT', '2026-10-16 16:57:59', 970860),
      (Modes.singles, 'EXPERT', '2026-10-16 16:55:06', 970860),
      (Modes.doubles, 'CHALLENGE', '2026-10-16 16:38:39', 970860),
    ]);
    expect([for (final p in plays) p.failed], [false, true, false]);

    expect(planEamuseSync(plays, null, 3), isA<EamuseFullSync>());
    expect(planEamuseSync(plays, '2026-10-16 16:57:59', 3),
        isA<EamuseNothingNew>());
    // Two plays of one chart since the last sync: one detail page.
    final recentOnly = planEamuseSync(plays, '2026-10-16 16:40:00', 3);
    expect((recentOnly as EamuseRecentSync).charts.map((p) => p.playedAt),
        ['2026-10-16 16:57:59']);
    // Every listed play is new and the list is full: some may be missing.
    expect(
        planEamuseSync(plays, '2026-10-16 16:00:00', 3), isA<EamuseFullSync>());

    final best = parseEamuseDetail('''
<div class="music-detail"><div class="music-text"><div class="music-name">MAX 300</div></div>
<div class="play-data">
  <div class="clearkind"><div class="value"><img src="$_img/cl_li4clear.png"></div></div>
  <div class="clearrank"><div class="value"><img src="$_img/rank_aa_p.png"></div></div>
  <div class="flarerank"><div class="value"><img src="$_img/flare_4.png"></div></div>
  <div class="maxcombo"><div class="value">387</div></div>
  <div class="best-score"><div class="value">974750</div></div>
  <div class="flareskill"><div class="value">768</div></div>
  <div class="lastplay"><div class="sub-header">LAST PLAY : 2026-10-16 16:57:59</div></div>
</div></div>''', plays.first, DateTime(2026))!;
    expect((
      best.id,
      best.score,
      best.rank,
      best.clearLamp,
      best.flareRank,
      best.maxCombo,
      best.playedAt
    ), (
      'eamuse:$a:singles:EXPERT',
      974750,
      'AA+',
      ClearLamp.life4,
      'IV',
      387,
      DateTime.utc(2026, 10, 16, 7, 57, 59)
    ));
  });

  test('profile gives the rival code and last play', () {
    String item(String label, String data) =>
        '<div class="status-item"><div class="status-label">$label</div>'
        '<div class="status-data">$data</div></div>';
    final profile = parseEamuseProfile('''
<div class="status-section"><div class="section-data">
  <div class="status-item wide"><a class="wrapper"><div class="status-label">DANCER NAME</div>
    <div class="status-data name">SHIGGY</div></a></div>
  ${item('DDR-CODE', '12345678')}${item('総プレー回数', '1380回')}
  ${item('最終プレー日時', '2026-10-17 15:59:32')}
  ${item('<img alt="SINGLE">', '<div class="total-flare-skill-value">54321</div>')}
</div></div>''');
    expect(profile, (
      name: 'SHIGGY',
      code: '12345678',
      plays: 1380,
      lastPlay: '2026-10-17 15:59:32',
    ));
  });
}
