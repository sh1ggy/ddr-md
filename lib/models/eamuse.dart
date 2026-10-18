/// Name: e-amusement sync
/// Parent: EamusePage
/// Description: Reads the player's best score on DDR WORLD charts from the
/// e-amusement play data pages and saves them as [ScoreRecord]s from
/// [ScoreRecordSource.eamuse]. A sync reads the recent plays page first and,
/// when it can, only fetches the detail page of each chart played since the
/// last sync; it walks every music_data page only when the recent list may
/// have dropped plays ([planEamuseSync]). Signing in happens on Konami's own
/// page in a web view, so the app reuses that session's cookies and never
/// sees the password. Requests are sequential and throttled by
/// [EamuseSync.gap], and a sync stops at the first error.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks;
import 'package:ddr_md/models/db_models.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

const kEamuseHost = 'https://p.eagate.573.jp';
const kEamuseLoginUrl =
    '$kEamuseHost/gate/p/login.html?path=/game/ddr/ddrworld/playdata/index.html';
const kEamusePlayDataPath = '/game/ddr/ddrworld/playdata/';

Uri eamusePageUrl(Modes mode, int page, [String host = kEamuseHost]) => Uri.parse(
    '$host${kEamusePlayDataPath}music_data_${mode == Modes.singles ? 'single' : 'double'}.html'
    '?offset=$page&filter=0&filtertype=0&display=score');

Uri eamuseRecentUrl([String host = kEamuseHost]) =>
    Uri.parse('$host${kEamusePlayDataPath}music_recent.html');

Uri eamuseProfileUrl([String host = kEamuseHost]) =>
    Uri.parse('$host${kEamusePlayDataPath}index.html');

class EamuseSignedOut implements Exception {}

/// Konami answered with something other than a play data page: an error,
/// maintenance, or a block. The sync stops and does not retry.
class EamuseUnavailable implements Exception {
  final String reason;
  EamuseUnavailable(this.reason);
  @override
  String toString() => reason;
}

/// One play data page: the charts played on it and how many pages there are.
typedef EamusePage = ({List<ScoreRecord> records, int pages});

const _ranks = {
  'aaa': 'AAA', 'aa_p': 'AA+', 'aa': 'AA', 'aa_m': 'AA-', 'a_p': 'A+', //
  'a': 'A', 'a_m': 'A-', 'b_p': 'B+', 'b': 'B', 'b_m': 'B-', 'c_p': 'C+',
  'c': 'C', 'c_m': 'C-', 'd_p': 'D+', 'd': 'D', 'e': 'E',
};
const _lamps = {
  'cl_marv': ClearLamp.mfc,
  'cl_perf': ClearLamp.pfc,
  'cl_great': ClearLamp.gfc,
  'cl_good': ClearLamp.fc,
  'cl_li4clear': ClearLamp.life4,
  'cl_clear': ClearLamp.clear,
  'cl_asclear': ClearLamp.assisted,
  'cl_none': ClearLamp.failed,
};
const _difficulties = {'BEGINNER', 'BASIC', 'DIFFICULT', 'EXPERT', 'CHALLENGE'};

String _imageName(dom.Element chart, String selector) {
  final src = chart.querySelector('$selector img')?.attributes['src'] ?? '';
  return src.split('/').last.replaceFirst(RegExp(r'\.png$'), '');
}

String _flareRank(String imageName) {
  if (imageName == 'flare_ex') return 'EX';
  final level = int.tryParse(imageName.replaceFirst('flare_', ''));
  return level != null && level >= 1 && level <= 9
      ? kFlareRanks[level - 1]
      : '';
}

final _konamiIdPattern = RegExp(r'(?:index|img)=([0-9A-Za-z]{32})');

/// [element] is the page's content; when it's missing, says why.
dom.Element _content(dom.Document doc, dom.Element? element) {
  if (element != null) return element;
  if (doc.querySelector('.errinfo_btn#login, a[href*="login.html"]') != null) {
    throw EamuseSignedOut();
  }
  throw EamuseUnavailable('Not a play data page');
}

/// Parses one music_data page fetched for [mode].
EamusePage parseEamusePage(String source, Modes mode, DateTime syncedAt) {
  final doc = html.parse(source);
  final list = _content(doc, doc.getElementById('music_list'));
  final records = <ScoreRecord>[];
  for (final card in list.querySelectorAll('.music-card')) {
    final info = card.querySelector('.chart .music_info');
    final konamiId =
        _konamiIdPattern.firstMatch(info?.attributes['href'] ?? '')?.group(1);
    final title = info?.querySelector('.music-name')?.text.trim() ?? '';
    if (konamiId == null || title.isEmpty) continue;
    for (final chart in card.querySelectorAll('.playdata > .rank')) {
      final difficulty = chart.classes.map((c) => c.toUpperCase()).firstWhere(
            _difficulties.contains,
            orElse: () => '',
          );
      if (difficulty.isEmpty) continue; // No chart (DP has no Beginner).
      final score =
          int.tryParse(chart.querySelector('.data_score')?.text.trim() ?? '');
      final rank = _ranks[_imageName(chart, '.data_rank')
          .replaceFirst(RegExp(r'^rank_(s_)?'), '')];
      if (score == null || rank == null) continue; // Not played.
      records.add(ScoreRecord.eamuse(
        konamiId: konamiId,
        title: title,
        mode: mode,
        difficulty: difficulty,
        score: score,
        rank: rank,
        clearLamp: _lamps[_imageName(chart, '.data_clearkind')],
        flareRank: _flareRank(_imageName(chart, '.data_flarerank')),
        flareSkill: int.tryParse(
            chart.querySelector('.data_flareskill')?.text.trim() ?? ''),
        updatedAt: syncedAt,
      ));
    }
  }
  final pages = doc.querySelectorAll('#paging_box .page_num').length;
  return (records: records, pages: max(pages, 1));
}

/// One play on the recent plays page. [playedAt] is the page's own
/// "YYYY-MM-DD HH:MM:SS" in Japan time, which sorts as text. [score] is that
/// play's own, not the chart's best: the page lists every play, repeats and
/// plays below the best included.
typedef EamusePlay = ({
  String konamiId,
  String title,
  Modes mode,
  String difficulty,
  String playedAt,
  String detailPath,
  int? score,
});

/// The recent plays page, newest first.
List<EamusePlay> parseEamuseRecent(String source) {
  final doc = html.parse(source);
  final result = _content(doc, doc.getElementById('search_result'));
  return [
    for (final row in result.querySelectorAll('table tbody tr.data'))
      if (row.querySelector('.chart a.music_info') case final link?)
        if (_konamiIdPattern.firstMatch(link.attributes['href'] ?? '')
            case final id?)
          if (link
                  .querySelector('.diff')
                  ?.classes
                  .map((c) => c.toUpperCase())
                  .firstWhere(_difficulties.contains, orElse: () => '')
              case final difficulty? when difficulty.isNotEmpty)
            (
              konamiId: id.group(1)!,
              title: link.querySelector('.music-name')?.text.trim() ?? '',
              mode: link.querySelector('.diff .level')?.text.trim() == 'DOUBLE'
                  ? Modes.doubles
                  : Modes.singles,
              difficulty: difficulty,
              playedAt: link.querySelector('.date')?.text.trim() ?? '',
              detailPath: link.attributes['href']!,
              score: int.tryParse(
                  row.querySelector('td.score')?.text.trim() ?? ''),
            )
  ];
}

/// The play data index's player status. [lastPlay] is e-amusement's
/// Japan-time "YYYY-MM-DD HH:MM:SS"; any field the page leaves out is empty.
typedef EamuseProfile = ({
  String name,
  String code,
  int? plays,
  String lastPlay,
});

/// Reads the status section's label/value pairs: dancer name, DDR-CODE (the
/// rival code), total plays and last play. Per-style entries further down
/// repeat some labels; the first of each wins.
EamuseProfile parseEamuseProfile(String source) {
  final doc = html.parse(source);
  final status = _content(doc, doc.querySelector('.status-section'));
  final fields = <String, String>{};
  for (final item in status.querySelectorAll('.status-item')) {
    final label = item.querySelector('.status-label')?.text.trim();
    final value = item.querySelector('.status-data')?.text.trim();
    if (label != null && label.isNotEmpty && value != null) {
      fields.putIfAbsent(label, () => value);
    }
  }
  return (
    name: fields['DANCER NAME'] ?? '',
    code: (fields['DDR-CODE'] ?? '').replaceAll(RegExp(r'\D'), ''),
    plays: int.tryParse((fields['総プレー回数'] ?? '').replaceAll(RegExp(r'\D'), '')),
    lastPlay: RegExp(r'\d{4}-\d\d-\d\d \d\d:\d\d:\d\d')
            .firstMatch(fields['最終プレー日時'] ?? '')
            ?.group(0) ??
        '',
  );
}

/// An 8-digit rival code as the cabinet shows it, 1234-5678.
String formatRivalCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

/// A chart's music_detail page: its best for [play]'s chart, or null when
/// the page says it has no play data.
ScoreRecord? parseEamuseDetail(
    String source, EamusePlay play, DateTime syncedAt) {
  final doc = html.parse(source);
  final detail = _content(doc, doc.querySelector('.music-detail'));
  final data = detail.querySelector('.play-data');
  if (detail.querySelector('.no-play') != null || data == null) return null;
  int? value(String selector) =>
      int.tryParse(data.querySelector('$selector .value')?.text.trim() ?? '');
  final score = value('.best-score');
  final rank = _ranks[
      _imageName(data, '.clearrank').replaceFirst(RegExp(r'^rank_(s_)?'), '')];
  if (score == null || rank == null) return null;
  final lastPlay = RegExp(r'\d{4}-\d\d-\d\d \d\d:\d\d:\d\d')
      .firstMatch(data.querySelector('.lastplay')?.text ?? '')
      ?.group(0);
  return ScoreRecord.eamuse(
    konamiId: play.konamiId,
    title: detail.querySelector('.music-text .music-name')?.text.trim() ??
        play.title,
    mode: play.mode,
    difficulty: play.difficulty,
    score: score,
    rank: rank,
    clearLamp: _lamps[_imageName(data, '.clearkind')],
    flareRank: _flareRank(_imageName(data, '.flarerank')),
    flareSkill: value('.flareskill'),
    maxCombo: value('.maxcombo'),
    playedAt: lastPlay == null ? null : eamuseTime(lastPlay),
    updatedAt: syncedAt,
  );
}

/// e-amusement's Japan-time "YYYY-MM-DD HH:MM:SS" as a UTC instant.
DateTime eamuseTime(String text) =>
    DateTime.parse('${text.replaceFirst(' ', 'T')}+09:00');

/// What a sync has to fetch after reading the recent plays page.
sealed class EamusePlan {}

/// Walk every music_data page: the first sync, or plays may be missing.
class EamuseFullSync extends EamusePlan {}

/// Fetch only these charts' detail pages, one play each (the newest).
class EamuseRecentSync extends EamusePlan {
  final List<EamusePlay> charts;
  EamuseRecentSync(this.charts);
}

/// Nothing played since the last sync.
class EamuseNothingNew extends EamusePlan {}

/// Decides from the recent plays page ([plays], newest first, as many as the
/// page holds) and the newest play the last finished sync saw ([lastPlay]).
/// When every listed play is new and the list is full, older plays may have
/// fallen off the end since the last sync, so only a full walk is sure to
/// catch them.
EamusePlan planEamuseSync(
    List<EamusePlay> plays, String? lastPlay, int pageSize) {
  if (lastPlay == null || lastPlay.isEmpty) return EamuseFullSync();
  final fresh = [
    for (final p in plays)
      if (p.playedAt.compareTo(lastPlay) > 0) p
  ];
  if (fresh.isEmpty) return EamuseNothingNew();
  if (fresh.length == plays.length && plays.length >= pageSize) {
    return EamuseFullSync();
  }
  final seen = <String>{};
  return EamuseRecentSync([
    for (final p in fresh)
      if (seen.add('${p.konamiId}:${p.mode.name}:${p.difficulty}')) p
  ]);
}

/// Normalises a title for matching e-amusement's names to the song list:
/// full-width ASCII to half-width, case and runs of whitespace ignored.
String eamuseTitleKey(String title) =>
    String.fromCharCodes(title.runes.map((c) =>
            c >= 0xFF01 && c <= 0xFF5E ? c - 0xFEE0 : (c == 0x3000 ? 32 : c)))
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

/// Song `name` for each title key, from both the title and its
/// transliteration.
Map<String, String> eamuseTitleIndex(Iterable<SongInfo> songs) => {
      for (final s in songs) ...{
        eamuseTitleKey(s.titletranslit): s.name,
        eamuseTitleKey(s.title): s.name,
      }
    };

typedef EamuseProgress = void Function(int done, int total);

class EamuseSync {
  /// Least time between two requests to Konami; each wait adds up to a second
  /// of jitter on top.
  static const gap = Duration(seconds: 3);

  /// Least time between two syncs. Most only read the recent plays page.
  static const cooldown = Duration(minutes: 1);

  /// Upper bound on pages per style, in case the pager is misread.
  static const maxPages = 60;

  /// Plays the recent plays page lists.
  static const recentSize = 50;

  final String cookies;
  final Map<String, String> titleIndex;
  final Future<void> Function(List<ScoreRecord>) save;
  final String host;
  bool cancelled = false;
  DateTime? _lastRequest;
  final _random = Random();

  EamuseSync({
    required this.cookies,
    required this.titleIndex,
    required this.save,
    this.host = kEamuseHost,
  });

  Future<List<EamusePlay>> recent() async =>
      parseEamuseRecent(await _get(eamuseRecentUrl(host)));

  Future<EamuseProfile> profile() async =>
      parseEamuseProfile(await _get(eamuseProfileUrl(host)));

  /// Fetches and saves each of [plays]' charts from its detail page.
  Future<({int charts, int unmatched})> details(
      List<EamusePlay> plays, EamuseProgress onProgress) async {
    final syncedAt = DateTime.now();
    var charts = 0, unmatched = 0;
    for (var i = 0; i < plays.length && !cancelled; i++) {
      onProgress(i, plays.length);
      final record = parseEamuseDetail(
          await _get(Uri.parse('$host${plays[i].detailPath}')),
          plays[i],
          syncedAt);
      if (record == null) continue;
      final matched = record.withSong(titleIndex[eamuseTitleKey(record.title)]);
      await save([matched]);
      charts++;
      if (matched.song == null) unmatched++;
    }
    return (charts: charts, unmatched: unmatched);
  }

  Future<String> _get(Uri url) async {
    if (_lastRequest != null) {
      final wait = gap +
          Duration(milliseconds: _random.nextInt(1000)) -
          DateTime.now().difference(_lastRequest!);
      if (wait > Duration.zero) await Future.delayed(wait);
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(url);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.cookieHeader, cookies);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      // A redirect from a play data page goes to the login page.
      if (response.isRedirect) throw EamuseSignedOut();
      if (response.statusCode != 200) {
        throw EamuseUnavailable('Konami answered ${response.statusCode}');
      }
      return body;
    } finally {
      _lastRequest = DateTime.now();
      client.close();
    }
  }

  /// Syncs both styles, saving each page as it arrives. Returns how many
  /// charts were saved and how many of them matched no song.
  Future<({int charts, int unmatched})> run(EamuseProgress onProgress) async {
    final syncedAt = DateTime.now();
    var charts = 0, unmatched = 0;
    // Doubles' page count is unknown until its first page; until then it's
    // taken to match singles'.
    var singlesPages = 1;
    for (final mode in Modes.values) {
      var pages = 1;
      for (var page = 0; page < pages && !cancelled; page++) {
        final before = mode == Modes.singles ? 0 : singlesPages;
        onProgress(before + page,
            singlesPages + (mode == Modes.singles ? singlesPages : pages));
        final parsed = parseEamusePage(
            await _get(eamusePageUrl(mode, page, host)), mode, syncedAt);
        pages = min(parsed.pages, maxPages);
        if (mode == Modes.singles) singlesPages = pages;
        final records = [
          for (final r in parsed.records)
            r.withSong(titleIndex[eamuseTitleKey(r.title)])
        ];
        await save(records);
        charts += records.length;
        unmatched += records.where((r) => r.song == null).length;
      }
    }
    return (charts: charts, unmatched: unmatched);
  }
}
