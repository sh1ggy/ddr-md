/// Name: EamuseSyncState
/// Parent: main
/// Description: App-wide owner of the e-amusement sync, so a sync started on
/// Home keeps running while the player moves around the app. A tap while a
/// sync runs, or within [EamuseSync.cooldown] of the last finished one, does
/// nothing, and only charts whose best changed are written.
library;

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
  EamuseSync? _sync;

  DateTime? get syncedAt =>
      DateTime.tryParse(Settings.getString(Settings.eamuseSyncedAtKey));

  bool get upToDate {
    final at = syncedAt;
    return at != null && DateTime.now().difference(at) < EamuseSync.cooldown;
  }

  Future<void> restore() async {
    charts = await DatabaseProvider.countScoreRecords(ScoreRecordSource.eamuse);
    notifyListeners();
  }

  Future<void> sync() async {
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
    notifyListeners();
    // Doubles' page count is unknown until its first page; until then it's
    // taken to match singles'.
    var singlesPages = 1;
    try {
      await sync.run((mode, page, pages) {
        if (mode.index == 0) singlesPages = pages;
        final done = mode.index == 0 ? page : singlesPages + page;
        progress =
            done / (singlesPages + (mode.index == 0 ? singlesPages : pages));
        notifyListeners();
      });
      if (!sync.cancelled) {
        await Settings.setString(
            Settings.eamuseSyncedAtKey, DateTime.now().toIso8601String());
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
    charts = await DatabaseProvider.countScoreRecords(ScoreRecordSource.eamuse);
    notifyListeners();
  }

  void stop() => _sync?.cancelled = true;

  Future<void> signOut() async {
    await CookieManager.instance().deleteAllCookies();
    await Settings.setString(Settings.eamuseSyncedAtKey, '');
    status = EamuseStatus.signedOut;
    notifyListeners();
  }

  static Map<String, Object?> _comparable(ScoreRecord r) =>
      r.toMap()..remove('updatedAt');
}
