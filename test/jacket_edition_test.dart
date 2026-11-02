import 'dart:async';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/components/songlist/generated_jacket.dart';
import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_motion.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_stamp.dart';
import 'package:ddr_md/components/song/jacket_edition/compact_jacket_edition.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/version_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EditionFacts facts(
        {Grade? grade = Grade.aaa,
        ClearLamp? lamp = ClearLamp.pfc,
        String? flare = 'EX',
        int? level = 16,
        int? tier,
        String difficulty = 'hard',
        PrecisionAward award = PrecisionAward.pfc}) =>
    EditionFacts(
        chart: (song: 'test', mode: 'singles', difficulty: difficulty),
        level: level,
        tier: tier,
        version: FlareGroup.gold,
        grade: grade,
        lamp: lamp,
        flare: flare,
        precision: (
          award: award,
          sourceRowId: 'test',
          perfects: award == PrecisionAward.sdp ? 9 : null
        ));
EditionOptions options(
        {bool motion = true, bool effects = true, bool stamps = false}) =>
    (
      borderId: 'gilded',
      effects: effects,
      motion: motion,
      modeStamp: stamps,
      gradeStamp: stamps,
      difficultyStamp: stamps,
      tierSuffix: stamps
    );
Widget host(Widget child, {bool reduced = false, bool ticker = true}) =>
    MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: TickerMode(
                enabled: ticker,
                child: Center(
                    child: SizedBox.square(dimension: 320, child: child)))));

class PaintCounter extends LeafRenderObjectWidget {
  const PaintCounter(this.painted, {super.key});
  final VoidCallback painted;
  @override
  RenderObject createRenderObject(BuildContext context) => CountPaint(painted);
}

class CountPaint extends RenderBox {
  CountPaint(this.painted);
  final VoidCallback painted;
  @override
  void performLayout() => size = constraints.biggest;
  @override
  void paint(PaintingContext context, Offset offset) {
    painted();
    context.canvas.drawRect(offset & size, Paint()..color = Colors.indigo);
  }
}

class MissingDifficultyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key.startsWith('assets/difficulty/')) {
      return Future.error(FlutterError('Optional artwork absent'));
    }
    return rootBundle.load(key);
  }
}

void main() {
  test('only AAA is foiled, as on its badge', () {
    for (final grade in Grade.values) {
      expect(finishFor(grade),
          grade == Grade.aaa ? EditionFinish.prism : EditionFinish.print);
    }
  });
  test('tier, not level, picks the cut; unknowns stay neutral', () {
    expect(resolveEdition(facts(level: 19)).cut, EditionCut.neutral);
    expect(
        resolveEdition(const EditionFacts(
                chart: (song: '?', mode: 'singles', difficulty: 'hard'),
                level: 17,
                tier: 9))
            .cut,
        EditionCut.fine);
    const noData =
        EditionFacts(chart: (song: '?', mode: 'doubles', difficulty: '?'));
    final recipe = resolveEdition(noData);
    expect(recipe.cut, EditionCut.neutral);
    expect(recipe.motif, EditionMotif.neutral);
    expect(flareGroup('future version'), isNull);
    expect(
        resolveEdition(facts(), (
          borderId: 'removed',
          effects: true,
          motion: true,
          modeStamp: true,
          gradeStamp: true,
          difficultyStamp: true,
          tierSuffix: true
        )).border,
        EditionBorder.gilded);
  });
  test('EX keeps PFC gold, SDP platinum, MFC takes precedence', () {
    expect(resolveEdition(facts()).frame, EditionFrame.gold);
    expect(resolveEdition(facts(award: PrecisionAward.sdp)).frame,
        EditionFrame.platinum);
    final mfc =
        resolveEdition(facts(lamp: ClearLamp.mfc, award: PrecisionAward.sdp));
    expect(mfc.frame, EditionFrame.rainbow);
    expect(mfc.ex, isTrue);
  });
  test('resolution matrix is bounded, comparable and stamp independent', () {
    for (final g in [null, ...Grade.values]) {
      for (final lamp in [null, ...ClearLamp.values]) {
        for (var level = 1; level <= 20; level++) {
          for (final flare in [null, 'I', 'IX', 'EX']) {
            final f = facts(grade: g, lamp: lamp, level: level, flare: flare);
            final a = resolveEdition(f, options(stamps: true));
            final b = resolveEdition(f, options());
            expect(a.finish, b.finish);
            expect(a.cut, b.cut);
            expect(a.frame, b.frame);
            expect(b, resolveEdition(f, options()));
          }
        }
      }
    }
  });
  testWidgets('compact material stays static under idle and pointer movement',
      (tester) async {
    var paints = 0;
    await tester.pumpWidget(host(SizedBox.square(
        dimension: 96,
        child: CompactJacketEdition(
            facts: facts(),
            options: options(stamps: true),
            child: PaintCounter(() => paints++)))));
    await tester.pumpAndSettle();
    final initial = paints;
    final compact = find.byType(CompactJacketEdition);
    expect(find.descendant(of: compact, matching: find.byType(MouseRegion)),
        findsNothing);
    // Its stickers hold a still light.
    expect(
        tester
            .widgetList<EditionStamp>(find.descendant(
                of: compact, matching: find.byType(EditionStamp)))
            .map((s) => s.motion),
        everyElement(isNull));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: tester.getCenter(compact));
    await pointer.moveBy(const Offset(20, 10));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(paints, initial);
    expect(tester.binding.transientCallbackCount, 0);
    await pointer.removePointer();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('a light sweep and pointer burst never repaint the image',
      (tester) async {
    var paints = 0;
    await tester.pumpWidget(host(JacketEdition(
        facts: facts(),
        options: options(),
        child: PaintCounter(() => paints++))));
    await tester.pump(const Duration(milliseconds: 50));
    final initial = paints;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(JacketEdition)));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(1, 1));
    }
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    expect(paints, initial);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets(
      'visibility and motion controls stop ticking; unearned cards can still tilt',
      (tester) async {
    Widget viewer(EditionFacts f, {bool motion = true, Offset? frozen}) =>
        JacketEdition(
            key: const ValueKey('viewer'),
            facts: f,
            options: options(motion: motion),
            frozenLight: frozen,
            child: const ColoredBox(color: Colors.indigo));
    await tester.pumpWidget(host(viewer(facts())));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(host(viewer(facts()), reduced: true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host(viewer(facts()), ticker: false));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host(viewer(facts(), motion: false)));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester
        .pumpWidget(host(viewer(facts(), frozen: const Offset(.2, .8))));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host(viewer(facts())));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(host(viewer(facts(
        grade: null, lamp: null, flare: null, award: PrecisionAward.unknown))));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('route covering, dismissal and app lifecycle stop animation',
      (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester
        .pumpWidget(MaterialApp(navigatorKey: nav, home: const SizedBox()));
    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
            body: SizedBox.square(
                dimension: 320,
                child: JacketEdition(
                    facts: facts(),
                    options: options(),
                    child: const ColoredBox(color: Colors.indigo))))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    nav.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets('frozen premium render matrix', (tester) async {
    final widgets = <Widget>[];
    for (final award in [
      PrecisionAward.pfc,
      PrecisionAward.sdp,
      PrecisionAward.mfc
    ]) {
      for (final ex in [false, true]) {
        for (var tier = 0; tier < 10; tier++) {
          widgets.add(SizedBox.square(
              dimension: 64,
              child: JacketEdition(
                  facts:
                      facts(award: award, flare: ex ? 'EX' : null, tier: tier),
                  options: options(motion: false),
                  frozenLight: const Offset(.35, .3),
                  child: const ColoredBox(color: Colors.indigo))));
        }
      }
    }
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RepaintBoundary(
                key: const ValueKey('matrix'),
                child: Wrap(children: widgets)))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLater(find.byKey(const ValueKey('matrix')),
        matchesGoldenFile('goldens/jacket_editions.png'));
  });
  testWidgets('small layout, missing jacket and optional lettering fall back',
      (tester) async {
    await tester.pumpWidget(host(DefaultAssetBundle(
        bundle: MissingDifficultyBundle(),
        child: SizedBox.square(
            dimension: 48,
            child: JacketEdition(
                facts: facts(),
                options: options(motion: false, stamps: true),
                child: const SongArtwork(
                    songName: '__missing_edition_artwork__',
                    fullResolution: true))))));
    await tester.pumpAndSettle();
    expect(find.byType(GeneratedJacket), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'native grade and mode assets share a combined difficulty/tier mark',
      (tester) async {
    await tester.pumpWidget(host(JacketEdition(
        facts: const EditionFacts(
            chart: (song: 'test', mode: 'doubles', difficulty: 'challenge'),
            grade: Grade.aaa,
            level: 17,
            tier: 8,
            lamp: ClearLamp.pfc,
            flare: 'EX'),
        options: options(motion: false, stamps: true),
        child: const ColoredBox(color: Colors.indigo))));
    await tester.pumpAndSettle();
    final names = tester
        .widgetList<Image>(find.byType(Image))
        .map((w) => w.image)
        .whereType<AssetImage>()
        .map((a) => a.assetName);
    final stamps = tester
        .widgetList<EditionStamp>(find.byType(EditionStamp))
        .map((w) => w.asset);
    expect(stamps, contains('assets/icons/rank_aaa.png'));
    expect(names, contains('assets/icons/style_double.png'));
    expect(stamps, contains('assets/icons/flare_ex.png'));
    expect(find.text('.'), findsNothing);
    expect(names, contains('assets/difficulty/level_challenge_8.png'));
    final label = tester.widget<DifficultyLabel>(find.byType(DifficultyLabel));
    expect(label.difficulty, 'CHALLENGE');
    expect(label.level, 17);
    expect(label.levelSuffix, 8);
    expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('edition-achievement-stamp')))
            .dy,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey('edition-chart-stamp')))
            .dy));
    expect(find.textContaining('TIER'), findsNothing);
  });
  testWidgets(
      'full-card stickers scale with the card, compact stickers stay small',
      (tester) async {
    for (final side in [300.0, 600.0]) {
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: SizedBox.square(
                  dimension: side,
                  child: JacketEdition(
                      facts: facts(),
                      options: options(motion: false, stamps: true),
                      child: const ColoredBox(color: Colors.indigo))))));
      await tester.pumpAndSettle();
      for (final stamp
          in tester.widgetList<EditionStamp>(find.byType(EditionStamp))) {
        expect(stamp.height, closeTo(side * .105, .001));
      }
    }
    await tester.pumpWidget(host(CompactJacketEdition(
        facts: facts(),
        options: options(motion: false, stamps: true),
        child: const ColoredBox(color: Colors.indigo))));
    await tester.pumpAndSettle();
    for (final stamp
        in tester.widgetList<EditionStamp>(find.byType(EditionStamp))) {
      expect(stamp.height, 22);
    }
  });
  testWidgets('drag and hover leave the card flat', (tester) async {
    Widget viewer() => JacketEdition(
        facts: facts(),
        options: options(),
        child: const ColoredBox(color: Colors.indigo));
    await tester.pumpWidget(host(viewer()));
    await tester.pump(const Duration(milliseconds: 40));
    Transform transform() =>
        tester.widget<Transform>(find.byKey(const ValueKey('edition-tilt')));
    expect(transform().transform.entry(0, 2), 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
        tester.getTopLeft(find.byType(JacketEdition)) + const Offset(290, 40));
    // The tilt eases in over a few frames.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(transform().transform.entry(0, 2), 0);
    await tester.drag(find.byType(JacketEdition), const Offset(80, 40));
    await tester.pump(const Duration(milliseconds: 40));
    expect(transform().transform.entry(0, 2), 0);
    await tester.pumpWidget(host(viewer(), reduced: true));
    await tester.pump();
    expect(transform().transform.entry(0, 2), 0);
    await mouse.removePointer();
  });
  testWidgets('gyro coalesces samples, bounds tilt and stops when disabled',
      (tester) async {
    final events = StreamController<GyroscopeEvent>.broadcast(sync: true);
    final motion = EditionMotion(const TestVSync(), gyroscope: events.stream);
    var notifications = 0;
    motion.addListener(() => notifications++);
    motion.configure(true);
    final start = DateTime(2026);
    events.add(GyroscopeEvent(1, 1, 0, start));
    for (var i = 1; i <= 100; i++) {
      events.add(
          GyroscopeEvent(1, 1, 0, start.add(Duration(milliseconds: i * 10))));
    }
    expect(notifications, 0);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(motion.tilt.dx, greaterThan(.5));
    expect(motion.tilt.dx, lessThanOrEqualTo(1));
    expect(motion.tilt.dy, greaterThan(.5));
    // Returning the phone to its starting angle also returns the card,
    // even after exceeding the displayed tilt limit.
    for (var i = 1; i <= 100; i++) {
      events.add(GyroscopeEvent(
          -1, -1, 0, start.add(Duration(milliseconds: 1000 + i * 10))));
    }
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(motion.tilt.distance, lessThan(.001));
    motion.configure(false);
    expect(events.hasListener, isFalse);
    expect(motion.tilt, Offset.zero);
    motion.configure(true);
    events.add(GyroscopeEvent(0, 0, 0, start));
    await tester.pump(const Duration(milliseconds: 40));
    expect(motion.tilt, Offset.zero);
    events.addError(StateError('sensor unavailable'));
    await tester.pump(const Duration(milliseconds: 40));
    expect(motion.tilt, Offset.zero);
    motion.dispose();
    await events.close();
  });
}
