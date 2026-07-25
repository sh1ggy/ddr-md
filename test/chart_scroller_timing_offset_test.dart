/// Regression tests for ARCADE SYNC — the chart preview's cabinet timing
/// simulation — and its two TIMING offset dials.
///
/// The two dials deliberately use DIFFERENT units, matching how the cabinet and
/// its players express them: VISUAL is the -5.0..+5.0 dial (表示タイミング),
/// AUDIO is whole milliseconds (判定タイミング, where players work in ~±10-20ms).
/// Conflating them is the mistake these tests exist to prevent.
///
/// The VISUAL sign convention is the other load-bearing part: the cabinet's own
/// guidance is many FAST → PLUS, many SLOW → MINUS. It is pinned from both ends
/// here (unit conversion and the rendered consequence) because an earlier
/// revision had it inverted.
library;

import 'package:ddr_md/components/song/notes/chart_scroller.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

ChartSteps _steps() => const ChartSteps(notes: [
      StepNote(beat: 0, second: 0, col: 0, type: StepType.tap),
      StepNote(beat: 4, second: 2, col: 1, type: StepType.tap),
      StepNote(beat: 8, second: 4, col: 2, type: StepType.tap),
    ]);

/// [Settings] caches its SharedPreferences instance, so `setMockInitialValues`
/// after the first `init()` has no effect — tests needing a clean slate must
/// zero the keys themselves.
Future<void> _reset({bool arcadeSync = false}) async {
  await Settings.setInt(Settings.arcadeSyncOnKey, arcadeSync ? 1 : 0);
  await Settings.setInt(Settings.chartPreviewVisualOffsetKey, 0);
  await Settings.setInt(Settings.chartPreviewAudioOffsetMsKey, 0);
  // The bias stamp must be cleared too, and to a value no test song uses:
  // leaving a previous test's stamp behind makes the next song look like it
  // already owns these offsets, silently skipping the auto-seed.
  await Settings.setInt(Settings.chartPreviewOffsetForBiasKey, 999999);
}

/// The chart second the field is actually drawn around — the playhead plus any
/// applied VISUAL OFFSET.
/// The SYNC stat on the tempo badge (the "BPM | READ | SYNC" pill), or null when
/// the badge shows no sync segment.
({String label, Color? color})? _badgeSync(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.descendant(
          of: find.byKey(tempoBadgeKey), matching: find.byType(Text)))
      .toList();
  final i = texts.indexWhere((t) => t.data == 'SYNC');
  if (i == -1 || i + 1 >= texts.length) return null;
  final value = texts[i + 1];
  return (label: value.data!, color: value.style?.color);
}

/// The colour of the ARCADE SYNC summary label — the one place the FAST/SLOW
/// accent appears. The chips themselves are deliberately neutral.
Color? _summaryColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

/// The border colour of a TIMING chip, used to assert the chips stay uncoloured.
Color? _chipBorderColor(WidgetTester tester, Key chipKey) {
  final container = tester.widget<Container>(find
      .descendant(of: find.byKey(chipKey), matching: find.byType(Container))
      .first);
  final decoration = container.decoration as BoxDecoration;
  return decoration.border?.top.color;
}

/// Open the settings shade and tap one of its controls.
///
/// The shade is built even while closed (so `find.text` sees its labels) but is
/// slid fully off-screen inside an [IgnorePointer], so it must actually be
/// opened before a tap can land. Its body then scrolls within a 40%-height cap,
/// so the control may still need scrolling into view.
Future<void> _tapInShade(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(shadeTabKey));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(key),
    120,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pump(const Duration(milliseconds: 16));
}

/// A measured sync block with the given bias, standing in for the song page's
/// Sync card data.
Sync _sync(double biasMs) => Sync(
      biasMs: biasMs,
      confidence: 1,
      curveStartMs: -50,
      curveStepMs: 1,
      curve: const [],
    );

Widget _scroller({
  Key? key,
  bool assistTick = false,
  VoidCallback? onTick,
  Sync? sync,
}) =>
    ChartScroller(
      key: key,
      steps: _steps(),
      mode: Modes.singles,
      songLength: 6,
      chartBpm: 120,
      bpms: [Bpm(st: 0, ed: 10, val: 120)],
      stops: const [],
      sync: sync,
      assistTickOn: assistTick,
      onToggleAssistTick: onTick ?? () {},
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  group('VISUAL dial', () {
    test('one unit is one 60fps frame of arrow travel (~16.67ms)', () {
      expect(visualOffsetSeconds(1), closeTo(1 / 60, 1e-9));
      expect(visualOffsetSeconds(0), 0);
      // Full dial is about +/-83ms, the right order for a display-lag fix.
      expect(visualOffsetSeconds(5.0), closeTo(0.0833, 1e-4));
    });

    test('clamps to +/-5.0 and snaps to the 0.1 grid', () {
      expect(visualOffsetClamp(9.9), 5.0);
      expect(visualOffsetClamp(-9.9), -5.0);
      expect(visualOffsetClamp(1.24), closeTo(1.2, 1e-9));
      expect(visualOffsetClamp(1.26), closeTo(1.3, 1e-9));
    });

    test('reads as a signed one-decimal dial, like the cabinet', () {
      expect(visualOffsetLabel(0), '+0.0');
      expect(visualOffsetLabel(1.5), '+1.5');
      expect(visualOffsetLabel(-2.3), '-2.3');
    });
  });

  group('AUDIO dial', () {
    test('is milliseconds, NOT the visual dial unit', () {
      // Guards the two dials being conflated: 10 on the AUDIO dial is 10ms,
      // whereas 10 on the VISUAL dial would be 10 frames (167ms).
      expect(audioOffsetLabel(10), '+10ms');
      expect(audioOffsetLabel(-20), '-20ms');
      expect(audioOffsetLabel(0), '+0ms');
    });

    test('clamps to +/-50ms in whole milliseconds', () {
      expect(audioOffsetClampMs(999), 50);
      expect(audioOffsetClampMs(-999), -50);
      // Players work in integers; there is no sub-ms dial.
      expect(audioOffsetClampMs(10.4), 10);
      expect(audioOffsetClampMs(10.6), 11);
    });

    test('covers the range players actually report using', () {
      // ~10-20ms typical, more on badly-synced songs — all inside the dial.
      for (final ms in [10.0, -10.0, 20.0, -20.0]) {
        expect(audioOffsetClampMs(ms), ms,
            reason: '${ms}ms must be reachable without clamping');
      }
    });
  });

  group('ARCADE SYNC gate', () {
    testWidgets('the offset chips are hidden until ARCADE SYNC is on',
        (tester) async {
      await _reset();
      await tester.pumpWidget(_host(_scroller(key: const ValueKey('gate-off'))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byKey(arcadeSyncTileKey), findsOneWidget,
          reason: 'the master toggle must always be reachable');
      expect(find.byKey(visualOffsetChipKey), findsNothing);
      expect(find.byKey(audioOffsetChipKey), findsNothing);
    });

    testWidgets('turning ARCADE SYNC on reveals both chips', (tester) async {
      await _reset(arcadeSync: true);
      await tester.pumpWidget(_host(_scroller(key: const ValueKey('gate-on'))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byKey(visualOffsetChipKey), findsOneWidget);
      expect(find.byKey(audioOffsetChipKey), findsOneWidget);
    });

    testWidgets('engaging ARCADE SYNC switches the assist tick on',
        (tester) async {
      // An AUDIO OFFSET is inaudible without the tick, so the mode drives it —
      // otherwise turning the mode on would appear to do nothing.
      await _reset();
      var tickToggles = 0;
      await tester.pumpWidget(_host(_scroller(
        key: const ValueKey('tick-forced'),
        assistTick: false,
        onTick: () => tickToggles++,
      )));
      await tester.pump(const Duration(milliseconds: 16));

      await _tapInShade(tester, arcadeSyncTileKey);

      expect(tickToggles, 1,
          reason: 'engaging ARCADE SYNC must request the assist tick');
    });

    testWidgets('engaging it does NOT re-toggle an already-on tick',
        (tester) async {
      await _reset();
      var tickToggles = 0;
      await tester.pumpWidget(_host(_scroller(
        key: const ValueKey('tick-already-on'),
        assistTick: true,
        onTick: () => tickToggles++,
      )));
      await tester.pump(const Duration(milliseconds: 16));

      await _tapInShade(tester, arcadeSyncTileKey);

      expect(tickToggles, 0,
          reason: 'the tick was already on — toggling would switch it OFF');
    });

    test('a stored offset is IGNORED while the gate is off', () {
      // The gate isn't only about hiding controls: an offset saved in an earlier
      // session must not silently shift the field or the tick once ARCADE SYNC
      // is switched back off. This is the exact code path the live state uses.
      expect(
          debugGatedVisualOffsetSeconds(arcadeSyncOn: false, units: 5.0), 0);
      expect(debugGatedAudioOffsetSeconds(arcadeSyncOn: false, ms: 50), 0);
    });

    test('the same stored offset applies once the gate is on', () {
      expect(debugGatedVisualOffsetSeconds(arcadeSyncOn: true, units: 5.0),
          closeTo(5.0 / 60, 1e-9));
      expect(debugGatedAudioOffsetSeconds(arcadeSyncOn: true, ms: 50),
          closeTo(0.05, 1e-9));
    });

    testWidgets('the gate persists across previews', (tester) async {
      await _reset(arcadeSync: true);
      await tester.pumpWidget(_host(_scroller(key: const ValueKey('persist'))));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(visualOffsetChipKey), findsOneWidget);

      await Settings.setInt(Settings.arcadeSyncOnKey, 0);
      await tester.pumpWidget(_host(_scroller(key: const ValueKey('persist2'))));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(visualOffsetChipKey), findsNothing);
    });
  });

  group('auto-seeding on engage', () {
    testWidgets('engaging pre-dials the correction for the song\'s bias',
        (tester) async {
      // A +9.0ms FAST song is corrected by -9ms. That fits the fine AUDIO dial
      // entirely (one VISUAL unit is 16.67ms, which would overshoot), so the
      // whole correction lands there and the song opens already in sync.
      await _reset();
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('seed-on'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      await _tapInShade(tester, arcadeSyncTileKey);

      expect(Settings.getInt(Settings.chartPreviewAudioOffsetMsKey), -9);
      expect(Settings.getInt(Settings.chartPreviewVisualOffsetKey), 0);
      expect(find.text('on the beat'), findsOneWidget,
          reason: 'the mode should open already corrected');
    });

    testWidgets('the fine AUDIO dial carries the whole real-world range',
        (tester) async {
      // Measured biases top out near 50ms, inside AUDIO's ±50ms range, so the
      // exact 1ms dial does the work and the coarse VISUAL dial (which only
      // lands on ~1.67ms multiples) stays out of it. That is what keeps a
      // seeded song landing at 0.0-0.5ms rather than on a coarse-grid residue.
      await _reset();
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('seed-big'), sync: _sync(-40.0))));
      await tester.pump(const Duration(milliseconds: 16));

      await _tapInShade(tester, arcadeSyncTileKey);

      expect(Settings.getInt(Settings.chartPreviewAudioOffsetMsKey), 40);
      expect(Settings.getInt(Settings.chartPreviewVisualOffsetKey), 0);
      expect(find.text('on the beat'), findsOneWidget);
    });

    testWidgets('keeps offsets hand-dialled against THIS song', (tester) async {
      // Stamped with this song's bias, so they are recognised as its own tuning.
      await _reset();
      await Settings.setInt(Settings.chartPreviewAudioOffsetMsKey, -3);
      await Settings.setInt(Settings.chartPreviewOffsetForBiasKey, 900);
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('no-clobber'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      await _tapInShade(tester, arcadeSyncTileKey);

      expect(Settings.getInt(Settings.chartPreviewAudioOffsetMsKey), -3,
          reason: 'a user\'s own tuning for this song is theirs to keep');
    });

    testWidgets('re-seeds when the offsets belong to a DIFFERENT song',
        (tester) async {
      // The reported bug: sync a song needing +9ms, then open another (here
      // Battle Against a True Hero's real +1.5ms bias). The stale +9ms rode
      // along and the new song opened reading "FAST by 10.5ms" instead of
      // near zero. The stored bias no longer matches, so it must re-seed.
      await _reset(arcadeSync: true);
      await Settings.setInt(Settings.chartPreviewAudioOffsetMsKey, 9);
      await Settings.setInt(Settings.chartPreviewOffsetForBiasKey, -900);
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('carry-over'), sync: _sync(1.5))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(Settings.getInt(Settings.chartPreviewAudioOffsetMsKey), -2,
          reason: 'a +1.5ms song is corrected by -2ms, not left at +9ms');
      expect(find.text('FAST by 10.5ms'), findsNothing);
      expect(find.text('SLOW by 0.5ms'), findsOneWidget);
    });

    testWidgets('switching chart mid-preview re-seeds for the new sync',
        (tester) async {
      await _reset(arcadeSync: true);
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('switch'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));
      expect(Settings.getInt(Settings.chartPreviewAudioOffsetMsKey), -9);

      // Same widget identity, new sync — didUpdateWidget must notice.
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('switch'), sync: _sync(-4.0))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(Settings.getInt(Settings.chartPreviewAudioOffsetMsKey), 4);
    });

    testWidgets('a song with no sync data seeds nothing', (tester) async {
      await _reset();
      await tester.pumpWidget(
          _host(_scroller(key: const ValueKey('seed-none'))));
      await tester.pump(const Duration(milliseconds: 16));

      await _tapInShade(tester, arcadeSyncTileKey);

      expect(Settings.getInt(Settings.chartPreviewVisualOffsetKey), 0);
      expect(Settings.getInt(Settings.chartPreviewAudioOffsetMsKey), 0);
    });
  });

  group('persistence', () {
    testWidgets('VISUAL restores from tenths, AUDIO from whole ms',
        (tester) async {
      await _reset(arcadeSync: true);
      await Settings.setInt(Settings.chartPreviewVisualOffsetKey, 15);
      await Settings.setInt(Settings.chartPreviewAudioOffsetMsKey, -20);
      // Stamped for a 0-bias song (this scroller supplies no sync), marking
      // these as hand-tuned for it — otherwise they'd be re-seeded away.
      await Settings.setInt(Settings.chartPreviewOffsetForBiasKey, 0);
      await tester.pumpWidget(_host(_scroller(key: const ValueKey('restore'))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.text('+1.5'), findsOneWidget,
          reason: '15 tenths must restore as +1.5 on the VISUAL dial');
      expect(find.text('-20ms'), findsOneWidget,
          reason: '-20 must restore as -20ms on the AUDIO dial');
    });

    testWidgets('an unset offset defaults to neutral', (tester) async {
      await _reset(arcadeSync: true);
      await tester.pumpWidget(_host(_scroller(key: const ValueKey('unset'))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(Settings.getInt(Settings.chartPreviewVisualOffsetKey), 0);
      expect(Settings.getInt(Settings.chartPreviewAudioOffsetMsKey), 0);
      expect(find.text('+0.0'), findsOneWidget);
      expect(find.text('+0ms'), findsOneWidget);
    });
  });

  group('header summary — effective sync', () {
    testWidgets('an engaged song opens corrected, not at its raw bias',
        (tester) async {
      // With ARCADE SYNC on, opening a +9.0ms song auto-seeds the correction, so
      // the caption reports the CORRECTED figure. Reading "FAST by 9.0ms" here
      // would mean the correction never applied.
      await _reset(arcadeSync: true);
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('seed'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.text('on the beat'), findsOneWidget);
      expect(find.text('FAST by 9.0ms'), findsNothing);
    });

    testWidgets('while OFF it reads the song\'s raw bias', (tester) async {
      // Nothing is dialled while the mode is off, so the caption is the song's
      // own reading — and seeing it is often the reason to switch the mode on.
      await _reset();
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('off-sync'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.text('FAST by 9.0ms'), findsOneWidget);
    });

    testWidgets('a negative bias reads SLOW while off', (tester) async {
      await _reset();
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('seed-slow'), sync: _sync(-4.5))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.text('SLOW by 4.5ms'), findsOneWidget);
    });

    testWidgets('a hand-dialled offset adjusts FROM the song\'s bias',
        (tester) async {
      // Stamped as this song's own tuning, so it is kept rather than re-seeded:
      // +9.0ms song with -2ms dialled → +7.0ms effective.
      await _reset(arcadeSync: true);
      await Settings.setInt(Settings.chartPreviewAudioOffsetMsKey, -2);
      await Settings.setInt(Settings.chartPreviewOffsetForBiasKey, 900);
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('adjusted'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.text('FAST by 7.0ms'), findsOneWidget);
    });

    testWidgets('the VISUAL dial contributes in the same millisecond terms',
        (tester) async {
      // +9.0ms song, -1.0 visual unit (one 60fps frame = 16.67ms) overshoots
      // past zero into SLOW: 9.0 - 16.67 = -7.67ms.
      await _reset(arcadeSync: true);
      await Settings.setInt(Settings.chartPreviewVisualOffsetKey, -10);
      await Settings.setInt(Settings.chartPreviewOffsetForBiasKey, 900);
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('visual-adj'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.text('SLOW by 7.7ms'), findsOneWidget);
    });

    testWidgets('a song with no sync data says so', (tester) async {
      await _reset(arcadeSync: true);
      await tester.pumpWidget(_host(_scroller(key: const ValueKey('no-sync'))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.text('no sync data for this song'), findsOneWidget);
    });
  });

  group('FAST/SLOW accent', () {
    // _host uses the default (light) theme.
    const isDark = false;

    testWidgets('a FAST song colours the summary with the FAST hue',
        (tester) async {
      // Uses the app-wide sync palette so the preview and the song page's sync
      // card agree on what FAST and SLOW look like. Read with the mode off, so
      // the raw bias is what's on screen.
      await _reset();
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('accent-f'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(_summaryColor(tester, 'FAST by 9.0ms'), kFastColor(isDark));
    });

    testWidgets('a SLOW song colours the summary with the SLOW hue',
        (tester) async {
      await _reset();
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('accent-s'), sync: _sync(-9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(_summaryColor(tester, 'SLOW by 9.0ms'), kSlowColor(isDark));
    });

    testWidgets('correcting the bias drains the colour out', (tester) async {
      // The feedback that tells you when the song is dialled into sync — here
      // via the auto-seed on engage.
      await _reset(arcadeSync: true);
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('accent-zero'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      final color = _summaryColor(tester, 'on the beat');
      expect(color, isNot(kFastColor(isDark)));
      expect(color, isNot(kSlowColor(isDark)));
    });

    testWidgets('the chips themselves stay uncoloured', (tester) async {
      // The accent lives ONLY on the summary — two tinted chips side by side
      // read as competing blocks of colour.
      await _reset(arcadeSync: true);
      await Settings.setInt(Settings.chartPreviewVisualOffsetKey, 15);
      await Settings.setInt(Settings.chartPreviewAudioOffsetMsKey, -10);
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('no-tint'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      for (final key in [visualOffsetChipKey, audioOffsetChipKey]) {
        expect(_chipBorderColor(tester, key), isNot(kFastColor(isDark)));
        expect(_chipBorderColor(tester, key), isNot(kSlowColor(isDark)));
      }
    });
  });

  group('tempo badge SYNC stat', () {
    const isDark = false;

    testWidgets('shows a signed ms figure, colour-coded FAST', (tester) async {
      // The badge carries direction in the COLOUR, not the word — only the sign
      // and the number appear, to fit alongside BPM and READ over the field.
      await _reset();
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('badge-f'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      final badge = _badgeSync(tester);
      expect(badge?.label, '+9.0ms');
      expect(badge?.color, kFastColor(isDark));
    });

    testWidgets('colour-codes SLOW too', (tester) async {
      await _reset();
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('badge-s'), sync: _sync(-4.5))));
      await tester.pump(const Duration(milliseconds: 16));

      final badge = _badgeSync(tester);
      expect(badge?.label, '-4.5ms');
      expect(badge?.color, kSlowColor(isDark));
    });

    testWidgets('reads a plain uncoloured zero once corrected', (tester) async {
      await _reset(arcadeSync: true);
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('badge-zero'), sync: _sync(9.0))));
      await tester.pumpAndSettle();

      final badge = _badgeSync(tester);
      expect(badge?.label, '0.0ms');
      expect(badge?.color, isNot(kFastColor(isDark)));
      expect(badge?.color, isNot(kSlowColor(isDark)));
    });

    testWidgets('is hidden entirely when the song has no sync data',
        (tester) async {
      // An empty slot over the field would just be noise.
      await _reset();
      await tester.pumpWidget(
          _host(_scroller(key: const ValueKey('badge-none'))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(_badgeSync(tester), isNull);
    });

    testWidgets('always agrees with the ARCADE SYNC caption', (tester) async {
      // Both read the same effective figure, so they can't drift apart — the
      // badge just renders it tersely ("+9.0ms" vs "FAST by 9.0ms").
      await _reset();
      await tester.pumpWidget(_host(
          _scroller(key: const ValueKey('badge-agree'), sync: _sync(9.0))));
      await tester.pump(const Duration(milliseconds: 16));

      expect(_badgeSync(tester)?.label, '+9.0ms');
      expect(find.text('FAST by 9.0ms'), findsOneWidget);
      expect(_badgeSync(tester)?.color,
          _summaryColor(tester, 'FAST by 9.0ms'),
          reason: 'the badge and the caption must share one hue');
    });
  });

  group('rendered effect', () {
    testWidgets('renders without throwing at both dial extremes',
        (tester) async {
      for (final tenths in [50, -50]) {
        await _reset(arcadeSync: true);
        await Settings.setInt(Settings.chartPreviewVisualOffsetKey, tenths);
        await tester
            .pumpWidget(_host(_scroller(key: ValueKey('visual-$tenths'))));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull,
            reason: 'visual offset $tenths must not break the paint pass');
      }
    });

    test('PLUS advances the field reference — the FAST-bias correction', () {
      // The whole renderer keys off the painter's `second`, so this IS the
      // rendered effect: advancing the reference by dt is identical to pulling
      // every arrow dt closer to the receptor.
      final r = debugVisualOffsetEffect(3.0);
      expect(r.offsetSecond, greaterThan(r.neutralSecond),
          reason: 'PLUS is the cabinet correction for getting many FAST');
      expect(r.offsetSecond - r.neutralSecond, closeTo(3.0 / 60, 1e-9));
    });

    test('MINUS retards the field reference — the SLOW-bias correction', () {
      final r = debugVisualOffsetEffect(-3.0);
      expect(r.offsetSecond, lessThan(r.neutralSecond),
          reason: 'MINUS is the cabinet correction for getting many SLOW');
      expect(r.offsetSecond - r.neutralSecond, closeTo(-3.0 / 60, 1e-9));
    });

    test('changing the visual offset alone forces a repaint', () {
      // While PAUSED the playhead notifier never fires, so shouldRepaint is the
      // only thing that can report a dial change — without it, dragging VISUAL
      // would do nothing visible until playback resumed. Isolated to the offset:
      // the two painters share every other input by construction.
      expect(debugVisualOffsetEffect(3.0).repaints, isTrue);
    });

    test('a zero offset leaves the field bit-for-bit unchanged', () {
      final r = debugVisualOffsetEffect(0);
      expect(r.repaints, isFalse,
          reason: 'neutral must not invalidate the field');
      expect(r.offsetSecond, r.neutralSecond);
    });
  });
}
