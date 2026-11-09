/// Name: Pad rating test
/// Parent: DatabaseProvider
/// Description: A v20 database gains synced pad ratings; rating a side of a
/// session again replaces its rating, flags and all.
library;

import 'dart:io';

import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart' show ClearLamp;
import 'package:ddr_md/models/pad_rating.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('a session side keeps one rating, synced', () async {
    final dir = await Directory.systemTemp.createTemp('pad-rating-');
    final path = '${dir.path}/pads.db';
    var db = await DatabaseProvider.open(path);
    await db.execute('DROP TABLE pad_ratings');
    await db.setVersion(20);
    await db.close();
    db = await DatabaseProvider.open(path);
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    await DatabaseProvider.withTestDatabase(db, () async {
      final venue = await DatabaseProvider.addVenue('Round1');
      final cab = (await DatabaseProvider.getCabinets(venue.id)).single;
      final session = await DatabaseProvider.startSession(venue);
      PadRating rate(ClearLamp lamp, Map<PadArrow, ArrowFlag> arrows) =>
          PadRating(
              sessionId: session.id,
              cabinet: cab,
              side: PadSide.p1,
              lamp: lamp,
              arrows: arrows);
      await DatabaseProvider.savePadRating(rate(ClearLamp.gfc, {}));
      await DatabaseProvider.savePadRating(rate(ClearLamp.clear, {
        PadArrow.up:
            const ArrowFlag(issues: {PadIssue.dropsSteps}, zone: PadZone.top)
      }));

      final r =
          (await DatabaseProvider.getSessionPadRatings(session.id)).single;
      expect(r.lamp, ClearLamp.clear);
      expect(r.flagSummary, 'Up drops steps · outer edge');
      expect(r.sessionAt, session.startedAt);
      expect(await db.query('sync_outbox', where: "t = 'pad_ratings'"),
          isNotEmpty);
    });
  });
}
