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
  final loose = <RecentPlay>[];
  for (final p in plays) {
    // The latest session started before the play still running at it.
    final s = sessions
        .where((s) =>
            !s.startedAt.isAfter(p.playedAt) &&
            !p.playedAt.isAfter(until[s.id]!))
        .firstOrNull;
    s == null ? loose.add(p) : bySession[s.id]!.add(p);
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
