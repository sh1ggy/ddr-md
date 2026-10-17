/// Name: SessionModel
/// Description: Play sessions at a venue, split into credits (one cabinet +
/// pad side each), the timing each play logged, and the sync the player
/// should use from them.
library;

import 'dart:math';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum PadSide { p1, p2 }

class Venue {
  final int id;
  final String name;

  const Venue(this.id, this.name);

  factory Venue.fromMap(Map<String, dynamic> m) =>
      Venue(m['id'] as int, m['name'] as String);
}

/// A cabinet at a venue. Most venues have one, named '' — it then goes by
/// the venue's name alone.
class Cabinet {
  final int id;
  final int venueId;
  final String venueName;
  final String name;

  const Cabinet(this.id, this.venueId, this.venueName, this.name);

  String get label => name.isEmpty ? venueName : '$venueName · $name';

  factory Cabinet.fromMap(Map<String, dynamic> m) => Cabinet(m['id'] as int,
      m['venueId'] as int, m['venueName'] as String, m['name'] as String);
}

/// One outing at a venue.
class PlaySession {
  final String id;
  final Venue venue;
  final DateTime startedAt;
  final DateTime? endedAt;

  const PlaySession(this.id, this.venue, this.startedAt, this.endedAt);

  factory PlaySession.fromMap(Map<String, dynamic> m) => PlaySession(
        m['id'] as String,
        Venue(m['venueId'] as int, m['venueName'] as String),
        DateTime.parse(m['startedAt'] as String),
        m['endedAt'] == null ? null : DateTime.parse(m['endedAt'] as String),
      );
}

/// One credit in a session: the cabinet and side it was played on.
class Credit {
  final String id;
  final String sessionId;
  final int number;
  final Cabinet cabinet;
  final PadSide side;
  final DateTime startedAt;

  Credit({
    String? id,
    required this.sessionId,
    required this.number,
    required this.cabinet,
    required this.side,
    required this.startedAt,
  }) : id = id ?? _uuid.v4();

  factory Credit.fromMap(Map<String, dynamic> m) => Credit(
        id: m['id'] as String,
        sessionId: m['sessionId'] as String,
        number: m['number'] as int,
        cabinet: Cabinet.fromMap(
            {...m, 'id': m['cabinetId'], 'name': m['cabinetName']}),
        side: PadSide.values.byName(m['side'] as String),
        startedAt: DateTime.parse(m['startedAt'] as String),
      );
}

/// One play's result-screen timing. [averageMs] is press − note, so FAST is
/// negative; [syncUsedMs] is the sync the player had set for that play.
class TimingPlay {
  final String id;
  final String playedAt;
  // The credit it was logged in; null for plays from before credits.
  final String? creditId;
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
    this.creditId,
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
        'creditId': creditId,
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
        creditId: m['creditId'],
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

/// The running session and its current credit, which plays are logged
/// against. Persisted so it survives the app being closed between songs.
class SessionState extends ChangeNotifier {
  PlaySession? _session;
  PlaySession? get session => _session;

  Credit? _credit;
  Credit? get credit => _credit;
  Cabinet? get cabinet => _credit?.cabinet;
  PadSide get side => _credit?.side ?? PadSide.p1;

  bool get active => _credit != null;

  // Bumped whenever a play, credit or override changes, so views re-query.
  int _revision = 0;
  int get revision => _revision;

  Future<void> restore() async {
    final id = Settings.getString(Settings.sessionIdKey);
    if (id.isEmpty) return;
    _session = await DatabaseProvider.getSession(id);
    final credits = await DatabaseProvider.getCredits(id);
    _credit = credits.firstOrNull;
    if (_session?.endedAt != null || _credit == null) {
      _session = null;
      _credit = null;
    }
    notifyListeners();
  }

  Future<void> start(Venue venue, Cabinet cabinet, PadSide side) async {
    _session = await DatabaseProvider.startSession(venue);
    Settings.setString(Settings.sessionIdKey, _session!.id);
    _credit = null;
    await newCredit(cabinet, side);
  }

  Future<void> newCredit(Cabinet cabinet, PadSide side) async {
    final credit = Credit(
      sessionId: _session!.id,
      number: (_credit?.number ?? 0) + 1,
      cabinet: cabinet,
      side: side,
      startedAt: DateTime.now(),
    );
    await DatabaseProvider.saveCredit(credit);
    _credit = credit;
    changed();
  }

  Future<void> end() async {
    await DatabaseProvider.endSession(_session!.id);
    _session = null;
    _credit = null;
    Settings.setString(Settings.sessionIdKey, '');
    changed();
  }

  void changed() {
    _revision++;
    notifyListeners();
  }
}
