/// Name: VisitModel
/// Parent: SessionPage
/// Description: Sessions as the app shows them: each visit to the arcade, put
/// together from the sessions started in the app (venue, credits, timing) and
/// the e-amusement plays synced afterwards. A play belongs to the session
/// running when it was played; plays no session covers group into sets of
/// their own, waiting for a venue.
library;

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

/// [plays] (newest first) split into the [credits] they were played in,
/// newest credit first: each play goes to the last credit started before it.
/// Plays before every credit come last, under a null credit.
List<(Credit?, List<RecentPlay>)> groupByCredit(
    List<RecentPlay> plays, List<Credit> credits) {
  final ordered = [...credits]
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final byCredit = {for (final c in ordered) c.id: <RecentPlay>[]};
  final unmatched = <RecentPlay>[];
  for (final p in plays) {
    final c = ordered
        .where((c) => !c.startedAt.subtract(kCreditGrace).isAfter(p.playedAt))
        .firstOrNull;
    c == null ? unmatched.add(p) : byCredit[c.id]!.add(p);
  }
  return [
    for (final c in ordered) (c, byCredit[c.id]!),
    if (unmatched.isNotEmpty) (null, unmatched),
  ];
}
