/// Name: VisitModel
/// Parent: SessionPage
/// Description: Sessions as the app shows them: each visit to the arcade, put
/// together from the sessions started in the app (venue, credits, timing) and
/// the e-amusement plays synced afterwards. A play belongs to the session
/// running when it was played; plays no session covers group into sets of
/// their own, waiting for a venue.
library;

import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/session_model.dart';

/// The longest gap between two plays of one set.
const kSetBreak = Duration(hours: 1);

/// How long before a session's start (or its earliest play) a play still
/// joins it: a credit played just before tapping Start belongs to the visit.
const kStartGrace = Duration(minutes: 10);

/// [plays] (newest first) split wherever two plays are more than [gap] apart.
List<List<RecentPlay>> groupPlaySets(List<RecentPlay> plays,
    [Duration gap = kSetBreak]) {
  final sets = <List<RecentPlay>>[];
  for (final p in plays) {
    if (sets.isEmpty || sets.last.last.playedAt.difference(p.playedAt) > gap) {
      sets.add([p]);
    } else {
      sets.last.add(p);
    }
  }
  return sets;
}

class Visit {
  Visit(
      {required this.session,
      required this.plays,
      required this.start,
      required this.end});

  /// The session started in the app, or null for a set no session covers.
  final PlaySession? session;

  /// Its synced plays, newest first.
  final List<RecentPlay> plays;

  final DateTime start;
  final DateTime end;

  /// Its id in routes: the session's, or the set's first play time.
  String get key => session?.id ?? 'set-${start.millisecondsSinceEpoch}';
}

/// Every visit, newest first, from [plays] and [sessions] (both newest
/// first). Plays reach e-amusement a little after their credit, so a session
/// keeps plays until a set break past its end. One never ended stops at its
/// last credit ([lastCredits]) unless it's the [activeId] still running.
List<Visit> buildVisits(
  List<RecentPlay> plays,
  List<PlaySession> sessions,
  Map<String, DateTime> lastCredits, {
  String? activeId,
  DateTime? now,
}) {
  final until = {
    for (final s in sessions)
      s.id: (s.endedAt ??
              (s.id == activeId
                  ? now ?? DateTime.now()
                  : lastCredits[s.id] ?? s.startedAt))
          .add(kSetBreak),
  };
  final bySession = {for (final s in sessions) s.id: <RecentPlay>[]};
  // Each session's earliest moment so far; plays come newest first, so a
  // run of plays just before the start chains back into it.
  final from = {for (final s in sessions) s.id: s.startedAt};
  final loose = <RecentPlay>[];
  for (final p in plays) {
    // The latest session started before the play still running at it, else
    // one starting within the grace after it.
    final s = sessions
            .where((s) =>
                !s.startedAt.isAfter(p.playedAt) &&
                !p.playedAt.isAfter(until[s.id]!))
            .firstOrNull ??
        sessions
            .where((s) =>
                p.playedAt.isBefore(from[s.id]!) &&
                !p.playedAt.isBefore(from[s.id]!.subtract(kStartGrace)))
            .lastOrNull;
    if (s == null) {
      loose.add(p);
    } else {
      bySession[s.id]!.add(p);
      if (p.playedAt.isBefore(from[s.id]!)) from[s.id] = p.playedAt;
    }
  }

  DateTime earliest(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  DateTime latest(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  return [
    for (final s in sessions)
      Visit(
        session: s,
        plays: bySession[s.id]!,
        start: bySession[s.id]!.isEmpty
            ? s.startedAt
            : earliest(s.startedAt, bySession[s.id]!.last.playedAt),
        end: latest(s.endedAt ?? lastCredits[s.id] ?? s.startedAt,
            bySession[s.id]!.firstOrNull?.playedAt ?? s.startedAt),
      ),
    for (final set in groupPlaySets(loose))
      Visit(
          session: null,
          plays: set,
          start: set.last.playedAt,
          end: set.first.playedAt),
  ]..sort((a, b) => b.start.compareTo(a.start));
}

/// Slack for a play logged a little before its credit's start (clocks of the
/// app and e-amusement disagree by a moment).
const kCreditGrace = Duration(minutes: 2);

/// The most songs one credit plays.
const kSongsPerCredit = 4;

/// The fewest songs in a complete credit.
const kMinSongsPerCredit = 3;

/// The pause that balances the cost of inferring another credit. Gaps are
/// evidence for boundaries, never a reason to create a one-song credit.
const kCreditBreak = Duration(minutes: 10);

/// How far apart a logged timing and its synced play can be.
const kTimingMatch = Duration(minutes: 10);

/// [plays] (newest first) with the [timing] logged for them: each timing
/// play goes to the same song's play nearest in time within [kTimingMatch],
/// each used once, the same chart first. Timing is logged against the
/// difficulty picked on the song page, which may not be the chart played,
/// so the synced play's chart wins. One with no synced play joins the plays
/// as a stand-in without a score, so it still shows where it was played.
(List<RecentPlay>, Map<RecentPlay, TimingPlay>) reconcileTiming(
    List<RecentPlay> plays, List<TimingPlay> timing) {
  // Timing names charts as the step files do ('hard'), e-amusement as the
  // cabinet does ('EXPERT').
  String chart(String difficulty) =>
      (kInGameDifficultyNames[difficulty] ?? difficulty).toUpperCase();
  final pairs = [
    for (final t in timing)
      for (final p in plays)
        if (p.song == t.song && p.mode == t.mode)
          (
            p,
            t,
            DateTime.parse(t.playedAt).difference(p.playedAt).abs(),
            chart(p.difficulty) == chart(t.difficulty) ? 0 : 1,
          )
  ]
    ..removeWhere((e) => e.$3 > kTimingMatch)
    ..sort((a, b) => a.$4 != b.$4 ? a.$4 - b.$4 : a.$3.compareTo(b.$3));
  final matched = <RecentPlay, TimingPlay>{};
  final combined = [...plays];
  final used = <String>{};
  for (final (p, t, _, _) in pairs) {
    if (matched.containsKey(p) || used.contains(t.id)) continue;
    matched[p] = t;
    used.add(t.id);
  }
  for (final t in timing) {
    if (used.contains(t.id)) continue;
    final standIn = RecentPlay(
      konamiId: 'timing:${t.id}',
      title: t.song,
      song: t.song,
      mode: t.mode,
      difficulty: chart(t.difficulty),
      playedAt: DateTime.parse(t.playedAt),
      score: null,
    );
    matched[standIn] = t;
    // Insert manual-only plays without re-sorting the synced list. In
    // particular, equal timestamps must keep Konami's scraped order.
    final i = combined.indexWhere((p) => p.playedAt.isBefore(standIn.playedAt));
    combined.insert(i < 0 ? combined.length : i, standIn);
  }
  return (combined, matched);
}

/// The timing plays [matched] to a synced play on another chart, each with
/// that chart's difficulty as timing names it ('hard'), to store instead.
List<(TimingPlay, String)> timingFixes(Map<RecentPlay, TimingPlay> matched) => [
      for (final MapEntry(key: p, value: t) in matched.entries)
        for (final MapEntry(key: key, value: name)
            in kInGameDifficultyNames.entries)
          if (name == p.difficulty && key != t.difficulty) (t, key)
    ];

/// [plays] (newest first) split into the [credits] they were played in,
/// newest first. The synced timeline defines groups of three or four
/// songs, preferring boundaries at longer pauses. Nearby manual starts and
/// timing-credit changes corroborate a larger gap; counters alone cannot
/// force a boundary. Logged credits supply cabinet and side where their
/// times fit; surplus empty
/// manual credits are omitted once synced plays are available.
List<(Credit?, List<RecentPlay>)> groupByCredit(
    List<RecentPlay> plays, List<Credit> credits,
    [Map<RecentPlay, TimingPlay> timing = const {}]) {
  bool manual(RecentPlay p) => p.konamiId == 'timing:${timing[p]?.id}';
  final synced = plays.where((p) => !manual(p)).toList();
  if (synced.isEmpty) return _groupManualCredits(plays, credits, timing);

  final ordered = [...credits]
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final groups = _inferCreditGroups(synced, credits: credits, timing: timing);

  final used = <String>{};
  final result = <(Credit?, List<RecentPlay>)>[];
  for (final ps in groups) {
    final c = ordered
        .where((c) =>
            !c.startedAt.subtract(kCreditGrace).isAfter(ps.first.playedAt))
        .firstOrNull;
    final credit =
        ps.length >= kMinSongsPerCredit && c != null && used.add(c.id)
            ? c
            : null;
    result.insert(0, (credit, ps.reversed.toList()));
  }

  // Three synced songs already form a complete credit. An unmatched manual
  // entry cannot invent a fourth song or shift the remaining boundaries.
  final loose = plays.where(manual).toList();
  for (final (c, ps) in _groupManualCredits(loose, credits, timing)) {
    if (ps.isEmpty) continue;
    final credit = c != null && used.add(c.id) ? c : null;
    final i = result
        .indexWhere((g) => g.$2.first.playedAt.isBefore(ps.first.playedAt));
    result.insert(i < 0 ? result.length : i, (credit, ps));
  }
  return result;
}

/// Partitions the scraped order into complete three/four-song credits,
/// oldest first. Minimise missing edge data first, then time spent inside
/// credits plus [kCreditBreak] per credit. A manual start during a larger
/// gap, or matched timings changing credits across it, strengthens that
/// boundary by at most two minutes; repeated taps never stack. Equal
/// evidence favours four songs in the older group.
/// If the recorded count cannot form complete credits (1, 2 or 5 songs),
/// retain the incomplete edge separately instead of inventing more plays.
List<List<RecentPlay>> _inferCreditGroups(List<RecentPlay> plays,
    {List<Credit> credits = const [],
    Map<RecentPlay, TimingPlay> timing = const {}}) {
  final chronological = plays.reversed.toList();
  final n = chronological.length;
  final gaps = [
    for (var i = 1; i < n; i++)
      chronological[i]
          .playedAt
          .difference(chronological[i - 1].playedAt)
          .inMilliseconds,
  ];
  final sortedGaps = [...gaps]..sort();
  final typicalGap = sortedGaps.isEmpty
      ? 0
      : (sortedGaps[sortedGaps.length ~/ 2] +
              sortedGaps[(sortedGaps.length - 1) ~/ 2]) ~/
          2;
  final knownCredits = {for (final c in credits) c.id};
  final support = List<int>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    final gap = gaps[i - 1];
    final extra = gap - typicalGap;
    // A human hint can corroborate a noticeably longer re-entry pause,
    // not turn an ordinary between-song interval into a credit boundary.
    if (extra < const Duration(seconds: 30).inMilliseconds ||
        gap * 4 < typicalGap * 5) {
      continue;
    }
    final before = chronological[i - 1].playedAt;
    final after = chronological[i].playedAt;
    final startInGap = credits.any(
        (c) => !c.startedAt.isBefore(before) && !c.startedAt.isAfter(after));
    String? creditNear(int start, int step) {
      for (var j = start, distance = 0;
          j >= 0 && j < n && distance < kSongsPerCredit;
          j += step, distance++) {
        final id = timing[chronological[j]]?.creditId;
        if (knownCredits.contains(id)) return id;
      }
      return null;
    }

    final left = creditNear(i - 1, -1), right = creditNear(i, 1);
    final timingChanged = left != null && right != null && left != right;
    if (startInGap || timingChanged) {
      final weight = extra * 2;
      const maximumSupport = Duration(minutes: 2);
      support[i] = weight < maximumSupport.inMilliseconds
          ? weight
          : maximumSupport.inMilliseconds;
    }
  }
  final costs = List<(int, int)?>.filled(n + 1, null);
  final lengths = List<int>.filled(n + 1, 0);
  costs[n] = (0, 0);
  for (var start = n - 1; start >= 0; start--) {
    for (var length = kSongsPerCredit; length >= 1; length--) {
      final end = start + length;
      if (end > n || costs[end] == null) continue;
      final partial = length < kMinSongsPerCredit;
      if (partial && start != 0 && end != n) continue;
      var span = 0;
      for (var i = start + 1; i < end; i++) {
        span += chronological[i]
            .playedAt
            .difference(chronological[i - 1].playedAt)
            .inMilliseconds;
      }
      final next = costs[end]!;
      final candidate = (
        next.$1 + (partial ? length : 0),
        next.$2 + span + kCreditBreak.inMilliseconds - support[start],
      );
      final best = costs[start];
      if (best == null ||
          candidate.$1 < best.$1 ||
          (candidate.$1 == best.$1 && candidate.$2 < best.$2)) {
        costs[start] = candidate;
        lengths[start] = length;
      }
    }
  }
  return [
    for (var i = 0; i < n; i += lengths[i])
      chronological.sublist(i, i + lengths[i]),
  ];
}

/// Before syncing, retain the manual timings as provisional plays. Their
/// credit counters still cannot create completed one/two-song credits.
List<(Credit?, List<RecentPlay>)> _groupManualCredits(List<RecentPlay> plays,
    List<Credit> credits, Map<RecentPlay, TimingPlay> timing) {
  final ordered = [...credits]
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final byId = {for (final c in ordered) c.id: c};
  final used = <String>{};
  final groups = <(Credit?, List<RecentPlay>)>[];
  for (final ps
      in _inferCreditGroups(plays, credits: credits, timing: timing)) {
    final p = ps.first;
    final t = timing[p];
    final c = byId[t?.creditId] ??
        ordered
            .where(
                (c) => !c.startedAt.subtract(kCreditGrace).isAfter(p.playedAt))
            .firstOrNull;
    final credit =
        ps.length >= kMinSongsPerCredit && c != null && used.add(c.id)
            ? c
            : null;
    groups.add((credit, ps));
  }
  final result = [
    for (final (c, ps) in groups.reversed) (c, ps.reversed.toList()),
  ];
  // Keep empty logged credits visible without sorting the plays again.
  for (final c in ordered.where((c) => !used.contains(c.id))) {
    final i = result.indexWhere((g) =>
        (g.$2.firstOrNull?.playedAt ?? g.$1!.startedAt).isBefore(c.startedAt));
    result.insert(i < 0 ? result.length : i, (c, <RecentPlay>[]));
  }
  return result;
}
