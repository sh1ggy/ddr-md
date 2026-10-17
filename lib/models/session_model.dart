/// Name: SessionModel
/// Description: Play sessions on a named cabinet + pad side, the timing each
/// play logged, and the sync the player should use from them.
library;

import 'dart:math';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum PadSide { p1, p2 }

class Cabinet {
  final int id;
  final String name;

  const Cabinet(this.id, this.name);

  factory Cabinet.fromMap(Map<String, dynamic> m) =>
      Cabinet(m['id'] as int, m['name'] as String);
}

/// One play's result-screen timing. [averageMs] is press − note, so FAST is
/// negative; [syncUsedMs] is the sync the player had set for that play.
class TimingPlay {
  final String id;
  final String playedAt;
  final int cabinetId;
  final PadSide side;
  final String song;
  final Modes mode;
  final String difficulty;
  final double songOffsetMs;
  final double syncUsedMs;
  final double averageMs;
  final double variationMs;

  TimingPlay({
    String? id,
    required this.playedAt,
    required this.cabinetId,
    required this.side,
    required this.song,
    required this.mode,
    required this.difficulty,
    required this.songOffsetMs,
    required this.syncUsedMs,
    required this.averageMs,
    required this.variationMs,
  }) : id = id ?? _uuid.v4();

  /// The player's own correction on top of the song's offset. Same convention
  /// as the Sync card: timing that lands late (SLOW) is fixed by going
  /// negative, so the average comes off the sync that was used.
  double get personalMs => syncUsedMs - averageMs - songOffsetMs;

  Map<String, Object?> toMap() => {
        'id': id,
        'playedAt': playedAt,
        'cabinetId': cabinetId,
        'side': side.name,
        'song': song,
        'mode': mode.name,
        'difficulty': difficulty,
        'songOffsetMs': songOffsetMs,
        'syncUsedMs': syncUsedMs,
        'averageMs': averageMs,
        'variationMs': variationMs,
      };

  factory TimingPlay.fromMap(Map<String, dynamic> m) => TimingPlay(
        id: m['id'],
        playedAt: m['playedAt'],
        cabinetId: m['cabinetId'],
        side: PadSide.values.byName(m['side']),
        song: m['song'],
        mode: Modes.values.byName(m['mode']),
        difficulty: m['difficulty'],
        songOffsetMs: (m['songOffsetMs'] as num).toDouble(),
        syncUsedMs: (m['syncUsedMs'] as num).toDouble(),
        averageMs: (m['averageMs'] as num).toDouble(),
        variationMs: (m['variationMs'] as num).toDouble(),
      );
}

/// Where a [PlayerSync] came from, most specific first.
enum SyncSource { override, chart, song, cabinet, none }

class PlayerSync {
  final double ms;
  final SyncSource source;
  final int plays;
  // ± ms of the plays it was averaged from; null for an override or no plays.
  final double? spreadMs;

  const PlayerSync(this.ms, this.source, {this.plays = 0, this.spreadMs});
}

/// The song's recommended offset for [chart] — the Sync card's figure.
double songOffsetMs(SongInfo songInfo, Chart chart) =>
    -(songInfo.displaySyncFor(chart)?.biasMs ?? 0);

/// Inverse-variance mean of the plays' corrections: a tight play counts for
/// more than a scattered one. Returns (mean, ± of the mean).
(double, double) weightedPersonal(List<TimingPlay> plays) {
  var sumW = 0.0, sum = 0.0;
  for (final p in plays) {
    final v = p.variationMs < 1 ? 1.0 : p.variationMs;
    final w = 1 / (v * v);
    sumW += w;
    sum += w * p.personalMs;
  }
  return (sum / sumW, 1 / sqrt(sumW));
}

/// The sync to use on a chart: the override if set, else the song's offset
/// plus the player's correction from this chart's plays, then this song's,
/// then every play on the cabinet + side.
PlayerSync resolvePlayerSync({
  required double songOffset,
  required List<TimingPlay> plays,
  required String song,
  required Modes mode,
  required String difficulty,
  double? overrideMs,
}) {
  if (overrideMs != null) return PlayerSync(overrideMs, SyncSource.override);
  final chart = [
    for (final p in plays)
      if (p.song == song && p.mode == mode && p.difficulty == difficulty) p
  ];
  final sameSong = [
    for (final p in plays)
      if (p.song == song) p
  ];
  for (final (level, source) in [
    (chart, SyncSource.chart),
    (sameSong, SyncSource.song),
    (plays, SyncSource.cabinet),
  ]) {
    if (level.isEmpty) continue;
    final (mean, spread) = weightedPersonal(level);
    return PlayerSync(songOffset + mean, source,
        plays: level.length, spreadMs: spread);
  }
  return PlayerSync(songOffset, SyncSource.none);
}

/// The running session: which cabinet and side plays are logged against.
/// Persisted so it survives the app being closed between songs.
class SessionState extends ChangeNotifier {
  Cabinet? _cabinet;
  Cabinet? get cabinet => _cabinet;

  PadSide _side = PadSide.p1;
  PadSide get side => _side;

  DateTime? _startedAt;
  DateTime? get startedAt => _startedAt;

  bool get active => _cabinet != null;

  // Bumped whenever a play or override changes, so cards re-query.
  int _revision = 0;
  int get revision => _revision;

  Future<void> restore() async {
    final id = Settings.getInt(Settings.sessionCabinetKey);
    if (id == 0) return;
    final cabinets = await DatabaseProvider.getCabinets();
    _cabinet = cabinets.where((c) => c.id == id).firstOrNull;
    _side = PadSide.values[Settings.getInt(Settings.sessionSideKey)];
    _startedAt =
        DateTime.tryParse(Settings.getString(Settings.sessionStartKey));
    notifyListeners();
  }

  void start(Cabinet cabinet, PadSide side) {
    _cabinet = cabinet;
    _side = side;
    _startedAt = DateTime.now();
    Settings.setInt(Settings.sessionCabinetKey, cabinet.id);
    Settings.setInt(Settings.sessionSideKey, side.index);
    Settings.setString(Settings.sessionStartKey, _startedAt!.toIso8601String());
    notifyListeners();
  }

  void end() {
    _cabinet = null;
    _startedAt = null;
    Settings.setInt(Settings.sessionCabinetKey, 0);
    notifyListeners();
  }

  void changed() {
    _revision++;
    notifyListeners();
  }
}
