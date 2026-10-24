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

/// The longest wait between two songs of one credit.
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
  final used = <String>{};
  for (final (p, t, _, _) in pairs) {
    if (matched.containsKey(p) || used.contains(t.id)) continue;
    matched[p] = t;
    used.add(t.id);
  }
  for (final t in timing) {
    if (used.contains(t.id)) continue;
    matched[RecentPlay(
      konamiId: 'timing:${t.id}',
      title: t.song,
      song: t.song,
      mode: t.mode,
      difficulty: chart(t.difficulty),
      playedAt: DateTime.parse(t.playedAt),
      score: null,
    )] = t;
  }
  return (
    matched.keys.toSet().union(plays.toSet()).toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt)),
    matched
  );
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
/// newest first. A play whose [timing] was logged in a credit goes to it;
/// any other goes to the last credit started before it, up to
/// [kSongsPerCredit] songs and no more than [kCreditBreak] after its last;
/// the rest are split into credits that weren't
/// logged (a null credit), at most [kSongsPerCredit] songs each and broken
/// wherever songs are more than [kCreditBreak] apart.
List<(Credit?, List<RecentPlay>)> groupByCredit(
    List<RecentPlay> plays, List<Credit> credits,
    [Map<RecentPlay, TimingPlay> timing = const {}]) {
  final ordered = [...credits]
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final byCredit = {for (final c in ordered) c.id: <RecentPlay>[]};
  final rest = <RecentPlay>[];
  final pinned = {
    for (final MapEntry(key: p, value: t) in timing.entries)
      if (byCredit.containsKey(t.creditId)) p: t.creditId!,
  };
  for (final p in plays.reversed) {
    if (pinned[p] case final id?) byCredit[id]!.add(p);
  }
  for (final p in plays.reversed) {
    if (pinned.containsKey(p)) continue;
    final c = ordered
        .where((c) => !c.startedAt.subtract(kCreditGrace).isAfter(p.playedAt))
        .firstOrNull;
    final before = c == null
        ? null
        : byCredit[c.id]!
            .where((e) => !e.playedAt.isAfter(p.playedAt))
            .map((e) => e.playedAt)
            .fold<DateTime?>(null, (a, t) => a == null || t.isAfter(a) ? t : a);
    if (c != null &&
        byCredit[c.id]!.length < kSongsPerCredit &&
        (before == null || p.playedAt.difference(before) <= kCreditBreak)) {
      byCredit[c.id]!.add(p);
    } else {
      rest.add(p);
    }
  }
  // Oldest first so far; unlogged credits fill from their first song.
  final unlogged = <List<RecentPlay>>[];
  for (final p in rest) {
    final last = unlogged.lastOrNull;
    if (last == null ||
        last.length == kSongsPerCredit ||
        p.playedAt.difference(last.last.playedAt) > kCreditBreak) {
      unlogged.add([p]);
    } else {
      last.add(p);
    }
  }
  for (final list in byCredit.values) {
    list.sort((a, b) => a.playedAt.compareTo(b.playedAt));
  }
  DateTime at((Credit?, List<RecentPlay>) g) =>
      g.$2.lastOrNull?.playedAt ?? g.$1!.startedAt;
  return [
    for (final c in ordered) (c, byCredit[c.id]!.reversed.toList()),
    for (final g in unlogged) (null, g.reversed.toList()),
  ]..sort((a, b) => at(b).compareTo(at(a)));
}
