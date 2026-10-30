import 'dart:io';
import 'package:ddr_md/components/song/jacket_edition/edition_fixture_store.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_model.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_rules.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:ddr_md/models/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
      'seeded score database stays isolated, reopens idempotently, pages any combination',
      () async {
    final sentinel = await DatabaseProvider.open(inMemoryDatabasePath);
    final dir = await Directory.systemTemp.createTemp('edition_seeds');
    try {
      await DatabaseProvider.withTestDatabase(sentinel, () async {
        final file = '${dir.path}/fixtures.db';
        final store = await EditionFixtureStore.open(databasePath: file);
        final scores = await store.db.query('scores');
        expect(scores.length, lessThan(100));
        expect(store.space.count, greaterThan(1000000));
        expect(identical(await DatabaseProvider.db, sentinel), isTrue);
        expect(await sentinel.query('scores'), isEmpty);
        final first = await store.page(0);
        final last = await store.page(store.space.count - 1);
        expect(first.length, 12);
        expect(last.length, 1);
        expect(first.first.facts.grade, isNull);
        expect(last.single.facts.chart.mode, 'doubles');
        final count = (await store.db
                .rawQuery('SELECT COUNT(*) AS n FROM edition_combinations'))
            .single['n'];
        expect(count, store.space.count);
        final indexes = store.space.dimensions;
        expect(indexes.length, 7);
        final awards = store.space.results
            .where((r) => r.play != null)
            .map((r) => precisionForPlay(r.play!)?.award)
            .toSet();
        expect(
            awards,
            containsAll([
              null,
              PrecisionAward.pfc,
              PrecisionAward.sdp,
              PrecisionAward.mfc
            ]));
        final grades = store.space.ranges.map((r) => r.grade).toSet();
        expect(grades, containsAll([null, ...Grade.values]));
        for (final grade in Grade.values.where((g) => g != Grade.e)) {
          expect(store.space.ranges.any((r) => r.play?.score == grade.minScore),
              isTrue);
        }
        await store.close();
        final reopened = await EditionFixtureStore.open(databasePath: file);
        expect((await reopened.db.query('scores')).length, scores.length);
        expect((await reopened.page(reopened.space.count ~/ 2)).length, 12);
        await reopened.close();
      });
    } finally {
      await sentinel.close();
      await dir.delete(recursive: true);
    }
  });
  test('every seeded scoring/axis combination resolves using production rules',
      () async {
    final space = EditionFixtureSpace();
    final report = await space.validateAll();
    expect(report['validated'], space.count);
    const options = (
      borderId: 'gilded',
      effects: true,
      motion: false,
      modeStamp: true,
      gradeStamp: true,
      difficultyStamp: true,
      tierSuffix: true
    );
    expect(resolveEdition(space.factsAt(space.count - 1), options).finish,
        isA<EditionFinish>());
    // Kept concise so a device/test runner never truncates the result.
    // ignore: avoid_print
    print('Validated ${report['validated']} seeded combinations');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
