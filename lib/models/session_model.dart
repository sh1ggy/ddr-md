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

  late final (double, double) _untruncated = untruncate(averageMs, variationMs);

  /// Where the player's steps were centred and how widely they spread,
  /// counting the ones too far off to land on a note: see [untruncate].
  double get trueAverageMs => _untruncated.$1;
  double get trueVariationMs => _untruncated.$2;

  /// The player's own correction on top of the song's offset. Same convention
  /// as the Sync card: timing that lands late (SLOW) is fixed by going
  /// negative, so the average comes off the sync that was used.
  double get personalMs => syncUsedMs - trueAverageMs - songOffsetMs;

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

/// A step further than this from every note doesn't touch one.
const kJudgeWindowMs = 160.0;

// Complementary error function, fractional error under 1.2e-7 everywhere,
// so tail probabilities stay accurate far out.
double _erfc(double x) {
  final z = x.abs();
  final t = 1 / (1 + 0.5 * z);
  var poly = 0.0;
  for (final c in const [
    0.17087277, -0.82215223, 1.48851587, -1.13520398, 0.27886807, //
    -0.18628806, 0.09678418, 0.37409196, 1.00002368, -1.26551223,
  ]) {
    poly = poly * t + c;
  }
  final r = t * exp(-z * z + poly);
  return x >= 0 ? r : 2 - r;
}

// Mean and standard deviation of a normal(mu, sigma) seen only inside the
// judgement window; null once almost none of it lands there.
(double, double)? _windowed(double mu, double sigma) {
  final a = (-kJudgeWindowMs - mu) / sigma;
  final b = (kJudgeWindowMs - mu) / sigma;
  // Φ(b) − Φ(a), from whichever tail keeps its precision.
  final mass = a > 0
      ? 0.5 * (_erfc(a / sqrt2) - _erfc(b / sqrt2))
      : 0.5 * (_erfc(-b / sqrt2) - _erfc(-a / sqrt2));
  if (mass < 1e-12) return null;
  final pa = exp(-a * a / 2) / sqrt(2 * pi);
  final pb = exp(-b * b / 2) / sqrt(2 * pi);
  final r = (pa - pb) / mass;
  final variance = sigma * sigma * (1 + (a * pa - b * pb) / mass - r * r);
  return (mu + sigma * r, sqrt(max(variance, 0)));
}

/// The result screen's timing average and variation only count steps that
/// landed on a note, cutting off the tail beyond [kJudgeWindowMs]. Far off
/// the beat that pulls both towards zero (a true 128 ms SLOW ± 45 reads
/// 110 ± 33), so this finds the normal spread whose in-window part shows
/// [averageMs] ± [variationMs]. Near the beat the cut-off tail is negligible
/// and they come back as is. Right at the window's edge a reading fits
/// spreads centred anywhere past it, so the centre stops at the edge; the
/// wide spread that comes with it leaves such a play little weight.
(double, double) untruncate(double averageMs, double variationMs) {
  final m = averageMs, s = max(variationMs, 1.0);
  if ((kJudgeWindowMs - m.abs()) / s > 6) return (averageMs, variationMs);
  if (m.abs() >= kJudgeWindowMs) return (averageMs, variationMs);
  // Newton on (mu, log sigma), starting from what was shown.
  var mu = m, ls = log(s);
  double? miss(double mu, double ls) {
    final w = _windowed(mu, exp(ls));
    if (w == null) return null;
    return (w.$1 - m) * (w.$1 - m) + (w.$2 - s) * (w.$2 - s);
  }

  var err = miss(mu, ls)!;
  for (var i = 0; i < 100 && err > 1e-12; i++) {
    final w = _windowed(mu, exp(ls))!;
    final f1 = w.$1 - m, f2 = w.$2 - s;
    const h = 1e-5;
    final wm = _windowed(mu + h, exp(ls)), wl = _windowed(mu, exp(ls + h));
    if (wm == null || wl == null) break;
    final j11 = (wm.$1 - w.$1) / h, j21 = (wm.$2 - w.$2) / h;
    final j12 = (wl.$1 - w.$1) / h, j22 = (wl.$2 - w.$2) / h;
    final det = j11 * j22 - j12 * j21;
    if (det.abs() < 1e-15) break;
    var dmu = (j22 * f1 - j12 * f2) / det;
    var dls = (j11 * f2 - j21 * f1) / det;
    // Halve the step until it improves; a shown spread wider than any
    // in-window normal can show has no exact match, so stop at the closest.
    var step = 1.0;
    double? next;
    while (step > 1e-6) {
      next = miss(mu - step * dmu, ls - step * dls);
      if (next != null && next < err) break;
      step /= 2;
    }
    if (next == null || next >= err) break;
    mu -= step * dmu;
    ls -= step * dls;
    err = next;
  }
  return (mu.clamp(-kJudgeWindowMs, kJudgeWindowMs), exp(ls));
}

/// Inverse-variance mean of the plays' corrections: a tight play counts for
/// more than a scattered one. Returns (mean, ± of the mean).
(double, double) weightedPersonal(List<TimingPlay> plays) {
  var sumW = 0.0, sum = 0.0;
  for (final p in plays) {
    final v = p.trueVariationMs < 1 ? 1.0 : p.trueVariationMs;
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

  /// Saves [credit], new or changed, into its session, numbering the
  /// session's credits in the order they started.
  Future<void> saveCredit(Credit credit) async {
    await DatabaseProvider.saveCredit(credit);
    await DatabaseProvider.renumberCredits(credit.sessionId);
    if (credit.sessionId == _session?.id) {
      _credit = (await DatabaseProvider.getCredits(_session!.id)).firstOrNull;
    }
    changed();
  }

  /// Deletes [credit] and its plays. The current credit falls back to the
  /// one before it; a session left with none is discarded.
  Future<void> deleteCredit(Credit credit) async {
    await DatabaseProvider.deleteCredit(credit.id);
    if (credit.id == _credit?.id) {
      _credit = (await DatabaseProvider.getCredits(_session!.id)).firstOrNull;
      if (_credit == null) return discard();
    }
    changed();
  }

  /// Ends the session and deletes it with everything logged in it.
  Future<void> discard() async {
    await DatabaseProvider.deleteSession(_session!.id);
    _session = null;
    _credit = null;
    Settings.setString(Settings.sessionIdKey, '');
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
