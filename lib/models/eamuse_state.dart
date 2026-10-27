/// Name: EamuseSyncState
/// Parent: main
/// Description: App-wide owner of the e-amusement sync, so a sync started on
/// Home keeps running while the player moves around the app. Each sync reads
/// the recent plays page first and fetches only what [planEamuseSync] says it
/// needs, keeps every listed play in [DatabaseProvider.saveRecentPlays], and
/// refreshes the player's profile when anything was played. A walk of every
/// page that stops part way carries on from where it stopped next time. A tap
/// while a sync runs, within [EamuseSync.cooldown] of the last one starting,
/// or within [EamuseSync.backoff] of Konami refusing one, does nothing, and
/// only charts whose best changed are written.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/eamuse.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

enum EamuseStatus { idle, syncing, signedOut, failed }

class EamuseSyncState extends ChangeNotifier {
  EamuseStatus status = EamuseStatus.idle;
  // 0–1 while syncing.
  double progress = 0;
  // Synced charts on the device.
  int charts = 0;
  // Charts the last sync added or changed.
  int? changed;
  String error = '';
  // What the running or last sync checked, and why.
  String note = '';
  // Plays kept from the recent plays page.
  int recentPlays = 0;
  // Bumped when a sync ends, so views of what it saved reload.
  int revision = 0;
  EamuseSync? _sync;
  DateTime? _notBefore;
  Timer? _wake;

  DateTime? get syncedAt =>
      DateTime.tryParse(Settings.getString(Settings.eamuseSyncedAtKey));

  static bool get syncDoubles =>
      Settings.getInt(Settings.eamuseSkipDoublesKey) == 0;

  static List<Modes> get _styles =>
      [Modes.singles, if (syncDoubles) Modes.doubles];

  /// Turning doubles on after a sync reads its pages on the next one.
  static Future<void> setSyncDoubles(bool on) async {
    await Settings.setInt(Settings.eamuseSkipDoublesKey, on ? 0 : 1);
    final lastPlay = Settings.getString(Settings.eamuseLastPlayKey);
    if (on && _walk == null && lastPlay.isNotEmpty) {
      await _keepWalk((mode: Modes.doubles, page: 0), lastPlay);
    }
  }

  static ({EamuseWalk at, String since})? get _walk {
    final text = Settings.getString(Settings.eamuseWalkKey);
    if (text.isEmpty) return null;
    final json = jsonDecode(text);
    return (
      at: (mode: Modes.values.byName(json['mode']), page: json['page'] as int),
      since: json['since'] as String,
    );
  }

  static Future<void> _keepWalk(
          EamuseWalk? at, String since) =>
      Settings.setString(
          Settings.eamuseWalkKey,
          at == null
              ? ''
              : jsonEncode(
                  {'mode': at.mode.name, 'page': at.page, 'since': since}));

  /// Within the cooldown of the last sync, unless that sync kept no plays
  /// (one from before plays were kept), which leaves Home with nothing to show.
  bool get upToDate {
    final at = syncedAt;
    return at != null &&
        recentPlays > 0 &&
        DateTime.now().difference(at) < EamuseSync.cooldown;
  }

  /// Holding off after the last sync started or was refused, whatever its end.
  bool get waiting =>
      _notBefore != null && DateTime.now().isBefore(_notBefore!);

  void _holdOff(Duration wait) {
    _notBefore = DateTime.now().add(wait);
    _wake?.cancel();
    _wake = Timer(wait, notifyListeners);
  }

  EamuseSyncState() {
    ContentStore.revision.addListener(relink);
  }

  @override
  void dispose() {
    ContentStore.revision.removeListener(relink);
    _wake?.cancel();
    super.dispose();
  }

  /// Points saved scores and plays at the songs the current song list gives
  /// them, so charts synced before their song arrived, or matched by an older
  /// list, link up without another sync. At launch and after a content update.
  Future<void> relink() async {
    if (Songs.list.isEmpty) return;
    if (await DatabaseProvider.relinkEamuse(EamuseSongIndex(Songs.list).of) >
        0) {
      revision++;
      notifyListeners();
    }
  }

  Future<void> restore() async {
    await relink();
    charts = await DatabaseProvider.countScoreRecords(ScoreRecordSource.eamuse);
    recentPlays = await DatabaseProvider.countRecentPlays();
    notifyListeners();
  }

  /// [renewed]: the session was just renewed, by signing in or by
  /// [_signInSilently], so a signed-out answer means it really has to be
  /// signed into again.
  Future<void> sync({bool renewed = false}) async {
    // The sync after a sign-in carries on the one that needed it.
    if (status == EamuseStatus.syncing || upToDate || (waiting && !renewed)) {
      return;
    }
    _holdOff(EamuseSync.cooldown);
    final stored = {
      for (final r
          in await DatabaseProvider.getScoreRecords(ScoreRecordSource.eamuse))
        r.id: _comparable(r)
    };
    var changedNow = 0;
    final sync = _sync = EamuseSync(
      cookies: [
        for (final c in await CookieManager.instance()
            .getCookies(url: WebUri(kEamuseHost)))
          '${c.name}=${c.value}'
      ].join('; '),
      onCookies: _keepCookies,
      songs: EamuseSongIndex(Songs.list),
      save: (records) async {
        final fresh = [
          for (final r in records)
            if (!mapEquals(stored[r.id], _comparable(r))) r
        ];
        changedNow += fresh.length;
        await DatabaseProvider.saveScoreRecords(fresh);
      },
    );
    status = EamuseStatus.syncing;
    progress = 0;
    error = '';
    note = '';
    notifyListeners();
    void onProgress(int done, int total) {
      progress = total == 0 ? 0 : done / total;
      notifyListeners();
    }

    try {
      final plays = await sync.recent();
      await DatabaseProvider.saveRecentPlays([
        for (final p in plays)
          if (p.playedAt.isNotEmpty)
            RecentPlay(
              konamiId: p.konamiId,
              title: p.title,
              song: sync.songs.of(p.konamiId, p.title),
              mode: p.mode,
              difficulty: p.difficulty,
              playedAt: eamuseTime(p.playedAt),
              score: p.score,
              failed: p.failed,
            )
      ]);
      // Charts synced before the newest play was recorded have none, but
      // every play before that sync is in them.
      final lastPlay = Settings.getString(Settings.eamuseLastPlayKey);
      final at = syncedAt;
      final since = stored.isEmpty
          ? null
          : lastPlay.isNotEmpty
              ? lastPlay
              : at == null
                  ? null
                  : eamuseTimeText(at);
      // Plays since an unfinished walk began may be on pages it already
      // read; if too many to list, it starts over.
      final walk = _walk;
      final missed = walk == null
          ? null
          : planEamuseSync(plays, walk.since, EamuseSync.recentSize);
      final resume = missed != null && missed is! EamuseFullSync;
      final plan = resume
          ? EamuseFullSync()
          : planEamuseSync(plays, since, EamuseSync.recentSize);
      final styles = _styles;
      List<EamusePlay> wanted(List<EamusePlay> charts) => [
            for (final p in charts)
              if (styles.contains(p.mode)) p
          ];
      note = switch (plan) {
        EamuseFullSync() when resume =>
          'Carrying on the last read of every chart from '
              '${walk!.at.mode.name} page ${walk.at.page + 1}',
        EamuseFullSync() when stored.isEmpty =>
          'First sync: reading every chart',
        EamuseFullSync() when since == null =>
          'Reading every chart again (signed out since the last sync)',
        EamuseFullSync() =>
          'Over ${EamuseSync.recentSize} plays since the last sync: '
              'rechecking every chart',
        EamuseRecentSync(:final charts) =>
          '${stored.length} charts already saved: checking only the '
              '${charts.length} played since',
        EamuseNothingNew() =>
          '${stored.length} charts already saved: nothing played since the '
              'last sync',
      };
      notifyListeners();
      if (plan is! EamuseNothingNew ||
          Settings.getString(Settings.rivalCodeSpeedKey).isEmpty) {
        await _syncProfile(sync);
      }
      switch (plan) {
        case EamuseFullSync():
          final walkSince = resume
              ? walk!.since
              : plays.isEmpty
                  ? eamuseTimeText(DateTime.now())
                  : plays.first.playedAt;
          await sync.run(onProgress,
              styles: styles,
              from: resume ? walk!.at : null,
              onPage: (next) => _keepWalk(next, walkSince));
          if (missed case EamuseRecentSync(:final charts)
              when resume && !sync.cancelled) {
            await sync.details(wanted(charts), onProgress);
          }
        case EamuseRecentSync(:final charts):
          await sync.details(wanted(charts), onProgress);
        case EamuseNothingNew():
          break;
      }
      if (!sync.cancelled) {
        await Settings.setString(
            Settings.eamuseSyncedAtKey, DateTime.now().toIso8601String());
        if (plays.isNotEmpty) {
          await Settings.setString(
              Settings.eamuseLastPlayKey, plays.first.playedAt);
        }
      }
      status = EamuseStatus.idle;
    } on EamuseSignedOut {
      status = EamuseStatus.signedOut;
    } on EamuseUnavailable catch (e) {
      status = EamuseStatus.failed;
      error = 'e-amusement unavailable ($e), try again in '
          '${EamuseSync.backoff.inMinutes} min';
      _holdOff(EamuseSync.backoff);
    } catch (e) {
      status = EamuseStatus.failed;
      error = 'Sync failed';
      debugPrint('e-amusement sync failed: $e');
    }
    sync.close();
    _sync = null;
    changed = changedNow;
    revision++;
    charts = await DatabaseProvider.countScoreRecords(ScoreRecordSource.eamuse);
    recentPlays = await DatabaseProvider.countRecentPlays();
    notifyListeners();
    if (status == EamuseStatus.signedOut && !renewed) {
      status = EamuseStatus.syncing;
      progress = 0;
      notifyListeners();
      final signedIn = await _signInSilently();
      status = signedIn ? EamuseStatus.idle : EamuseStatus.signedOut;
      notifyListeners();
      if (signedIn) await this.sync(renewed: true);
    }
  }

  /// Keeps cookies Konami renews during a sync in the web view's store, which
  /// the next sync and sign-in read, with the expiry Konami gave them.
  static Future<void> _keepCookies(List<io.Cookie> cookies) async {
    for (final c in cookies) {
      final expires = c.expires ??
          (c.maxAge == null
              ? null
              : DateTime.now().add(Duration(seconds: c.maxAge!)));
      await CookieManager.instance().setCookie(
        url: WebUri(kEamuseHost),
        name: c.name,
        value: c.value,
        path: c.path ?? '/',
        domain: c.domain,
        isSecure: c.secure,
        isHttpOnly: c.httpOnly,
        expiresDate: expires?.millisecondsSinceEpoch,
      );
    }
  }

  /// e-amusement's login page hands off to KONAMI ID, which sends a browser
  /// still signed in to it straight back, so a lapsed e-amusement session
  /// is renewed in a hidden web view without the password while the KONAMI
  /// ID one lasts.
  static Future<bool> _signInSilently() async {
    final landed = Completer<bool>();
    final view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(kEamuseLoginUrl)),
      onLoadStop: (controller, url) {
        if (url != null &&
            url.host == Uri.parse(kEamuseHost).host &&
            url.path.startsWith(kEamusePlayDataPath) &&
            !landed.isCompleted) {
          landed.complete(true);
        }
      },
    );
    try {
      await view.run();
      return await landed.future
          .timeout(const Duration(seconds: 20), onTimeout: () => false);
    } catch (e) {
      debugPrint('e-amusement silent sign-in failed: $e');
      return false;
    } finally {
      await view.dispose();
    }
  }

  /// Best effort: a profile page that doesn't parse leaves the last one and
  /// doesn't stop the score sync.
  Future<void> _syncProfile(EamuseSync sync) async {
    try {
      final profile = await sync.profile();
      if (profile.code.isNotEmpty) {
        await Settings.setString(Settings.rivalCodeSpeedKey, profile.code);
      }
      if (profile.name.isNotEmpty) {
        await Settings.setString(Settings.eamuseNameKey, profile.name);
      }
      if (profile.plays != null) {
        await Settings.setInt(Settings.eamusePlayCountKey, profile.plays!);
      }
      if (profile.lastPlay.isNotEmpty) {
        await Settings.setString(
            Settings.eamuseProfileLastPlayKey, profile.lastPlay);
      }
    } on EamuseSignedOut {
      rethrow;
    } catch (e) {
      debugPrint('e-amusement profile not read: $e');
    }
  }

  void stop() => _sync?.cancelled = true;

  Future<void> signOut() async {
    await CookieManager.instance().deleteAllCookies();
    await Settings.setString(Settings.eamuseSyncedAtKey, '');
    // Another account may sign in next, so its first sync walks every page.
    await Settings.setString(Settings.eamuseLastPlayKey, '');
    await Settings.setString(Settings.eamuseWalkKey, '');
    status = EamuseStatus.signedOut;
    notifyListeners();
  }

  static Map<String, Object?> _comparable(ScoreRecord r) =>
      r.toMap()..remove('updatedAt');
}
