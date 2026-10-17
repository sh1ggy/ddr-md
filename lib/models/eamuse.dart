/// Name: e-amusement sync
/// Parent: EamusePage
/// Description: Reads the player's best score on every chart from the DDR WORLD
/// e-amusement play data pages (music_data_single/double.html) and saves them
/// as [ScoreRecord]s from [ScoreRecordSource.eamuse]. Signing in happens on
/// Konami's own page in a web view, so the app reuses that session's cookies
/// and never sees the password. Requests are sequential and throttled by
/// [EamuseSync.gap], a sync stops at the first error, and a new full sync is
/// refused within [EamuseSync.cooldown] of the last one.
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

/// Parses one music_data page fetched for [mode].
EamusePage parseEamusePage(String source, Modes mode, DateTime syncedAt) {
  final doc = html.parse(source);
  final list = doc.getElementById('music_list');
  if (list == null) {
    if (doc.querySelector('.errinfo_btn#login, a[href*="login.html"]') !=
        null) {
      throw EamuseSignedOut();
    }
    throw EamuseUnavailable('Not a play data page');
  }
  final records = <ScoreRecord>[];
  for (final card in list.querySelectorAll('.music-card')) {
    final info = card.querySelector('.chart .music_info');
    final konamiId = RegExp(r'(?:index|img)=([0-9A-Za-z]{32})')
        .firstMatch(info?.attributes['href'] ?? '')
        ?.group(1);
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
      final flare = _imageName(chart, '.data_flarerank');
      final flareLevel = int.tryParse(flare.replaceFirst('flare_', ''));
      records.add(ScoreRecord.eamuse(
        konamiId: konamiId,
        title: title,
        mode: mode,
        difficulty: difficulty,
        score: score,
        rank: rank,
        clearLamp: _lamps[_imageName(chart, '.data_clearkind')],
        flareRank: flare == 'flare_ex'
            ? 'EX'
            : flareLevel != null && flareLevel >= 1 && flareLevel <= 9
                ? kFlareRanks[flareLevel - 1]
                : '',
        flareSkill: int.tryParse(
            chart.querySelector('.data_flareskill')?.text.trim() ?? ''),
        updatedAt: syncedAt,
      ));
    }
  }
  final pages = doc.querySelectorAll('#paging_box .page_num').length;
  return (records: records, pages: max(pages, 1));
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

typedef EamuseProgress = void Function(Modes mode, int page, int pages);

class EamuseSync {
  /// Least time between two requests to Konami; each wait adds up to a second
  /// of jitter on top.
  static const gap = Duration(seconds: 3);

  /// Least time between two full syncs.
  static const cooldown = Duration(minutes: 15);

  /// Upper bound on pages per style, in case the pager is misread.
  static const maxPages = 60;

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
    for (final mode in Modes.values) {
      var pages = 1;
      for (var page = 0; page < pages && !cancelled; page++) {
        onProgress(mode, page, pages);
        final parsed = parseEamusePage(
            await _get(eamusePageUrl(mode, page, host)), mode, syncedAt);
        pages = min(parsed.pages, maxPages);
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
