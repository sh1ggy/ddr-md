/// Name: EamuseSyncState
/// Parent: main
/// Description: App-wide owner of the e-amusement sync, so a sync started on
/// Home keeps running while the player moves around the app. Each sync reads
/// the recent plays page first and fetches only what [planEamuseSync] says it
/// needs, keeps every listed play in [DatabaseProvider.saveRecentPlays], and
/// refreshes the player's profile when anything was played. A tap while a sync runs, or within [EamuseSync.cooldown] of the last
/// finished one, does nothing, and only charts whose best changed are
/// written.
library;

import 'dart:async';
import 'dart:io' as io;

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

  DateTime? get syncedAt =>
      DateTime.tryParse(Settings.getString(Settings.eamuseSyncedAtKey));

  /// Within the cooldown of the last sync, unless that sync kept no plays
  /// (one from before plays were kept), which leaves Home with nothing to show.
  bool get upToDate {
    final at = syncedAt;
    return at != null &&
        recentPlays > 0 &&
        DateTime.now().difference(at) < EamuseSync.cooldown;
  }

  Future<void> restore() async {
    charts = await DatabaseProvider.countScoreRecords(ScoreRecordSource.eamuse);
    recentPlays = await DatabaseProvider.countRecentPlays();
    notifyListeners();
  }

  /// Another device's scores or profile arrived through cloud sync: views of
  /// what a sync saved reload, as after one of ours.
  Future<void> reloadSaved() async {
    revision++;
    await restore();
  }

  /// [renewed]: the session was just renewed by [_signInSilently], so a
  /// second signed-out answer means it really has to be signed into again.
  Future<void> sync({bool renewed = false}) async {
    if (status == EamuseStatus.syncing || upToDate) return;
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
      titleIndex: eamuseTitleIndex(Songs.list),
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
              song: sync.titleIndex[eamuseTitleKey(p.title)],
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
      final plan = planEamuseSync(plays, since, EamuseSync.recentSize);
      note = switch (plan) {
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
          await sync.run(onProgress);
        case EamuseRecentSync(:final charts):
          await sync.details(charts, onProgress);
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
      error = 'e-amusement unavailable ($e)';
    } catch (e) {
      status = EamuseStatus.failed;
      error = 'Sync failed';
      debugPrint('e-amusement sync failed: $e');
    }
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
    status = EamuseStatus.signedOut;
    notifyListeners();
  }

  static Map<String, Object?> _comparable(ScoreRecord r) =>
      r.toMap()..remove('updatedAt');
}
