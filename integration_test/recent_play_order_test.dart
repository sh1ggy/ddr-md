/// Name: Recent play order integration test
/// Parent: integration_test
/// Description: Checks migration, scrape order, and credit reconciliation
/// against seeded sessions with inaccurate manual credit counts in native SQLite.
/// Run with --dart-define=DB_NAME=test-credit-order.db on macOS.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/visit_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'seeded credits consolidate after migration and overlapping syncs',
      (tester) async {
    const name = String.fromEnvironment('DB_NAME');
    // This test creates and deletes its database; never use the app's own.
    expect(name, 'test-credit-order.db');
    final path = join(await getDatabasesPath(), name);
    await deleteDatabase(path);
    final at = DateTime.utc(2026, 10, 1, 18);
    RecentPlay play(String id, {int score = 900000, int minutesAgo = 0}) =>
        RecentPlay(
            konamiId: id,
            title: id,
            song: id,
            mode: Modes.singles,
            difficulty: 'EXPERT',
            playedAt: at.subtract(Duration(minutes: minutesAgo)),
            score: score);
    final legacy = await DatabaseProvider.getDatabaseInstance();
    await legacy.execute('ALTER TABLE recent_plays DROP COLUMN syncOrder');
    await legacy.setVersion(15);
    for (final id in ['a', 'b', 'c']) {
      await legacy.insert('recent_plays', play(id).toMap());
    }
    await legacy.close();

    final db = (await DatabaseProvider.init())!;
    expect(await db.getVersion(), 16);
    Future<List<String>> ids({int? limit}) async => [
          for (final p in await DatabaseProvider.getRecentPlays(limit: limit))
            p.konamiId
        ];
    expect(await ids(), ['a', 'b', 'c']);
    await DatabaseProvider.saveRecentPlays([
      play('new'),
      play('a'),
      play('b', score: 950000),
      play('c'),
      play('older', minutesAgo: 1),
    ]);
    expect(await ids(), ['new', 'a', 'b', 'c', 'older']);
    // Only the newest part of the tied timestamp is on the next page.
    // It must stay ahead of the rows no longer listed there.
    await DatabaseProvider.saveRecentPlays([play('newest'), play('new')]);
    await DatabaseProvider.saveRecentPlays([play('newest'), play('new')]);
    expect(await ids(), ['newest', 'new', 'a', 'b', 'c', 'older']);
    expect(await ids(limit: 2), ['newest', 'new']);
    expect(await DatabaseProvider.countRecentPlays(), 6);
    expect((await DatabaseProvider.getRecentPlays())[3].score, 950000);

    await db.delete('recent_plays');
    final venue = await DatabaseProvider.addVenue('Seeded credit validation');
    final cabinet = (await DatabaseProvider.getCabinets(venue.id)).single;
    var fixture = 0;
    Future<void> checkCredits(String label, int songs, List<int> starts,
        {required List<int> sizes,
        List<int>? minutesAgo,
        List<int>? timingCredits,
        bool tied = false,
        bool unmatched = false}) async {
      final end = at.subtract(Duration(days: ++fixture));
      final synced = [
        for (var i = 0; i < songs; i++)
          RecentPlay(
              konamiId: '$label-$i',
              title: '$label-$i',
              song: '$label-$i',
              mode: Modes.singles,
              difficulty: 'EXPERT',
              playedAt: end.subtract(
                  Duration(minutes: minutesAgo?[i] ?? (tied ? 0 : i * 3))),
              score: 900000 + i),
      ];
      final session = await DatabaseProvider.addPastSession(
          venue,
          synced.last.playedAt.subtract(const Duration(minutes: 2)),
          end.add(const Duration(minutes: 2)));
      final credits = [
        for (final (i, minutesAgo) in starts.indexed)
          Credit(
              id: '$label-credit-$i',
              sessionId: session.id,
              number: i + 1,
              cabinet: cabinet,
              side: PadSide.p1,
              startedAt: end.subtract(Duration(minutes: minutesAgo))),
      ];
      for (final c in credits) {
        await DatabaseProvider.saveCredit(c);
      }
      final logged = [
        for (final (i, p) in synced.indexed)
          TimingPlay(
              id: '$label-timing-$i',
              creditId: credits[timingCredits?[i] ?? i % credits.length].id,
              playedAt:
                  p.playedAt.add(const Duration(seconds: 30)).toIso8601String(),
              cabinetId: cabinet.id,
              side: PadSide.p1,
              song: p.song!,
              mode: p.mode,
              difficulty: 'hard',
              songOffsetMs: 0,
              syncUsedMs: 0,
              averageMs: i.toDouble(),
              variationMs: 10),
        if (unmatched)
          TimingPlay(
              id: '$label-unmatched',
              creditId: credits.first.id,
              playedAt:
                  end.subtract(const Duration(minutes: 17)).toIso8601String(),
              cabinetId: cabinet.id,
              side: PadSide.p1,
              song: 'manual-only-song',
              mode: Modes.singles,
              difficulty: 'hard',
              songOffsetMs: 0,
              syncUsedMs: 0,
              averageMs: -5,
              variationMs: 10),
      ];
      for (final p in logged) {
        await DatabaseProvider.saveTimingPlay(p);
      }
      await DatabaseProvider.saveRecentPlays(synced);
      // Repeat an overlapping sync before loading through Home's queries.
      await DatabaseProvider.saveRecentPlays(synced.take(4).toList());
      final visits = buildVisits(
          await DatabaseProvider.getRecentPlays(),
          await DatabaseProvider.getSessions(),
          await DatabaseProvider.getLastCredits());
      final visit = visits.singleWhere((v) => v.session?.id == session.id);
      final storedCredits = await DatabaseProvider.getCredits(session.id);
      final storedTiming = await DatabaseProvider.getSessionPlays(session.id);
      final (played, matched) = reconcileTiming(visit.plays, storedTiming);
      final groups = groupByCredit(played, storedCredits, matched);
      final syncedGroups = [
        for (final (_, ps) in groups)
          if (ps.any((p) => !p.konamiId.startsWith('timing:')))
            ps.where((p) => !p.konamiId.startsWith('timing:')).toList(),
      ];
      final expected = <List<String>>[];
      var start = 0;
      for (final size in sizes) {
        expected.add(synced
            .sublist(start, start + size)
            .map((p) => p.konamiId)
            .toList());
        start += size;
      }
      expect(start, songs, reason: label);
      expect(
          syncedGroups.map((g) => g.map((p) => p.konamiId).toList()), expected,
          reason: label);
      expect(groups.map((g) => g.$2.length),
          everyElement(inInclusiveRange(1, kSongsPerCredit)),
          reason: label);
      expect(syncedGroups.map((g) => g.length),
          everyElement(inInclusiveRange(3, 4)),
          reason: label);
      expect(storedCredits, hasLength(starts.length), reason: label);
      expect(storedTiming, hasLength(logged.length), reason: label);
      expect(matched, hasLength(logged.length), reason: label);
      expect(played, hasLength(logged.length), reason: label);
      for (final (i, p) in visit.plays.indexed) {
        expect(matched[p]?.averageMs, i.toDouble(), reason: label);
      }
      debugPrint('Seed $label: $songs synced songs, ${starts.length} manual '
          'credits -> ${syncedGroups.map((g) => g.length).toList()} synced '
          'groups; ${matched.length}/${logged.length} timings retained');
    }

    await checkCredits('original-overflow', 6, [17], sizes: [3, 3]);
    await checkCredits('extra-manual-starts', 8, [23, 19, 16, 13, 2, 0],
        sizes: [4, 4]);
    await checkCredits('missed-manual-starts', 12, [35], sizes: [4, 4, 4]);
    await checkCredits('tied-timestamps', 8, [2, 1], sizes: [4, 4], tied: true);
    await checkCredits('unmatched-manual-entry', 8, [23],
        sizes: [4, 4], unmatched: true);
    await checkCredits('nine-songs', 9, [26], sizes: [3, 3, 3]);
    await checkCredits('three-then-four', 7, [26, 20, 19, 0],
        sizes: [4, 3], minutesAgo: [0, 3, 6, 9, 18, 21, 24]);
    await checkCredits('four-then-three', 7, [29],
        sizes: [3, 4], minutesAgo: [0, 3, 6, 18, 21, 24, 27]);
    await checkCredits('four-triples', 12, [62],
        sizes: [3, 3, 3, 3],
        minutesAgo: [0, 3, 6, 18, 21, 24, 36, 39, 42, 54, 57, 60]);
    await checkCredits('manual-start-support', 7, [23, 13],
        sizes: [4, 3],
        minutesAgo: [0, 3, 6, 11, 15, 18, 21],
        timingCredits: List.filled(7, 0));
    await checkCredits('manual-timing-support', 7, [24, 23],
        sizes: [4, 3],
        minutesAgo: [0, 3, 6, 11, 15, 18, 21],
        timingCredits: [1, 1, 1, 1, 0, 0, 0]);
    await checkCredits('manual-without-longer-gap', 7, [20, 11],
        sizes: [3, 4], timingCredits: [1, 1, 1, 1, 0, 0, 0]);
    await checkCredits('stronger-synced-gap', 7, [26, 16],
        sizes: [3, 4],
        minutesAgo: [0, 3, 6, 14, 18, 21, 24],
        timingCredits: [1, 1, 1, 1, 0, 0, 0]);
    await checkCredits('duplicate-manual-taps', 7, [26, ...List.filled(20, 16)],
        sizes: [3, 4],
        minutesAgo: [0, 3, 6, 14, 18, 21, 24],
        timingCredits: List.filled(7, 0));
    await checkCredits('supported-modest-gaps', 12, [38, 28, 18, 8],
        sizes: [3, 3, 3, 3],
        minutesAgo: [0, 3, 6, 10, 13, 16, 20, 23, 26, 30, 33, 36],
        timingCredits: [3, 3, 3, 2, 2, 2, 1, 1, 1, 0, 0, 0]);
    await db.close();

    // A fresh install also gets the ordering column.
    await deleteDatabase(path);
    final fresh = await DatabaseProvider.getDatabaseInstance();
    final columns = await fresh.rawQuery('PRAGMA table_info(recent_plays)');
    expect(columns.any((c) => c['name'] == 'syncOrder'), isTrue);
    await fresh.close();
    await deleteDatabase(path);
  });
}
