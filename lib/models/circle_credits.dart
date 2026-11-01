/// Name: CircleCredits
/// Parent: main
/// Description: Shares a broadcast session's credits with the circle as
/// e-amusement syncs them: the session's synced plays split into credits the
/// way its page shows them, each sent with its songs, scores, fails and new
/// bests. A credit already sent with the same songs isn't sent again.
library;

import 'dart:convert';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/visit_model.dart';

// What was last sent for each "session:credit".
final _sent = <String, String>{};

Future<void> shareSessionCredits(CircleState circles, String sessionId) async {
  final visit = buildVisits(
    await DatabaseProvider.getRecentPlays(),
    await DatabaseProvider.getSessions(),
    await DatabaseProvider.getLastCredits(),
    activeId: sessionId,
  ).where((v) => v.session?.id == sessionId).firstOrNull;
  if (visit == null || visit.plays.isEmpty) return;
  for (final m in Modes.values) {
    await ChartBests.ensure(m);
  }
  // Oldest credit first, so they number from 1 as played.
  final credits =
      groupByCredit(visit.plays, await DatabaseProvider.getCredits(sessionId))
          .reversed
          .toList();
  for (final (i, (_, plays)) in credits.indexed) {
    final shared = [
      for (final p in plays.reversed)
        (
          // The song list's name where matched, so friends see its jacket.
          song: p.song ?? p.title,
          mode: p.mode.name,
          difficulty: p.difficulty,
          score: p.score,
          failed: p.failed,
          best: p.score != null &&
              p.song != null &&
              p.score! >=
                  (ChartBests.bestsOf(p.mode)[p.song]?[p.difficulty]?.score ??
                      1 << 30),
        )
    ];
    final key = '$sessionId:${i + 1}';
    final body = jsonEncode([for (final p in shared) p.toString()]);
    if (_sent[key] == body) continue;
    await circles.shareCredit(sessionId, i + 1, shared);
    _sent[key] = body;
  }
}
