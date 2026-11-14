/// Name: BestStrip
/// Parent: DifficultyListPage
/// Description: The listed charts' bests as one strip under the level grid,
/// by clear lamp, grade or flare: each tier a band in the stats page's
/// colours, best first, played charts without one in grey, then the
/// unplayed. The grid's spare cell shows which measure in its art and
/// switches it; the choice sticks. Tapped, the strip opens a ladder of that
/// measure's tiers, with ways on to the full stats and the binder.
library;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/song/scores/art_badge.dart';
import 'package:ddr_md/components/song/scores/score_card.dart'
    show clearLampIcon;
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/db_models.dart' show ClearLamp;
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// [rainbow] sweeps along the band in place of its colour. [art] is the
// tier's badge, null for the played charts without one.
typedef _Tier = ({int count, Color color, List<Color>? rainbow, String? art});

// What the charts without a tier are called, measure by measure.
const _kNoneLabels = ['NO GRADE', 'NO LAMP', 'NO FLARE'];

const _kNone = Color(0xFF757575);

List<_Tier> _tiers<T>(List<ChartBest?> bests, List<T> tiers,
    T? Function(ChartBest) of, Color Function(T) color,
    {required String? Function(T) art, List<Color>? Function(T)? rainbow}) {
  final counts = <T, int>{};
  var none = 0;
  for (final b in bests) {
    if (b == null) continue;
    if (of(b) case final tier?) {
      counts[tier] = (counts[tier] ?? 0) + 1;
    } else {
      none++;
    }
  }
  return [
    for (final t in tiers)
      if (counts[t] case final n?)
        (count: n, color: color(t), rainbow: rainbow?.call(t), art: art(t)),
    if (none > 0) (count: none, color: _kNone, rainbow: null, art: null),
  ];
}

// Grade, lamp and flare, in the cabinet's order.
List<List<_Tier>> _rings(List<ChartBest?> bests) => [
      _tiers(bests, Grade.values, (b) => b.grade, gradeColor, art: gradeIcon),
      // A failed lamp has no art, so it counts with the charts without one.
      _tiers(
          bests,
          ClearLamp.values.reversed
              .where((l) => l != ClearLamp.failed)
              .toList(),
          (b) => b.lamp == ClearLamp.failed ? null : b.lamp,
          (l) => kLampColors[l]!,
          art: clearLampIcon),
      _tiers(bests, kFlareRanks.reversed.toList(), (b) => b.flare, flareColor,
          art: flareRankIcon,
          rainbow: (r) => r == 'EX' ? kFlareExColors : null),
    ];

enum BestMeasure {
  lamp(1),
  grade(0),
  flare(2);

  const BestMeasure(this.ring);

  // Its place in [_rings].
  final int ring;

  // Its best tier's art, standing in where nothing listed has one yet.
  String get topArt => switch (this) {
        lamp => clearLampIcon(ClearLamp.mfc)!,
        grade => gradeIcon(Grade.aaa),
        flare => flareRankIcon('EX'),
      };
}

/// The measure the strip shows, kept between visits.
final ValueNotifier<BestMeasure> bestMeasure = ValueNotifier(
    BestMeasure.values[Settings.getInt(Settings.bestMeasureKey) % 3])
  ..addListener(() =>
      Settings.setInt(Settings.bestMeasureKey, bestMeasure.value.index));

// [m]'s art for the listed charts: the best tier held, else its top tier
// dimmed.
Widget _measureArt(List<ChartBest?> bests, BestMeasure m) {
  final held = _rings(bests)[m.ring].firstOrNull?.art;
  return Opacity(
    key: ValueKey((m, held)),
    opacity: held == null ? 0.35 : 1,
    child: Image.asset(held ?? m.topArt, fit: BoxFit.contain),
  );
}

/// The level grid's spare cell: which measure the strip shows, in its art.
/// Tapped, it moves on to the next.
class BestMeasureSwitch extends StatelessWidget {
  const BestMeasureSwitch(this.bests, {super.key});

  final List<ChartBest?> bests;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return ValueListenableBuilder(
      valueListenable: bestMeasure,
      builder: (context, m, _) => Semantics(
        button: true,
        label: 'Bests by ${m.name}',
        child: Material(
          color: pop.stage,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              HapticFeedback.selectionClick();
              bestMeasure.value =
                  BestMeasure.values[(m.index + 1) % BestMeasure.values.length];
            },
            child: SizedBox(
              height: 34,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: AnimatedSwitcher(
                    duration: FloorPop.eighth, child: _measureArt(bests, m)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip itself, with the played count beside it.
class BestStrip extends StatelessWidget {
  const BestStrip(this.bests, {super.key, this.onStats, this.onBinder});

  /// One per listed chart, null where it hasn't been played.
  final List<ChartBest?> bests;

  /// Opens the full stats, from the ladder.
  final VoidCallback? onStats;

  /// Opens the binder, from the ladder.
  final VoidCallback? onBinder;

  void _open(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _Ladder(bests, onStats, onBinder),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (bests.isEmpty) return const SizedBox.shrink();
    final pop = FloorPop.of(context);
    final played = bests.where((b) => b != null).length;
    return ValueListenableBuilder(
      valueListenable: bestMeasure,
      builder: (context, m, _) {
        final tiers = _rings(bests)[m.ring];
        return Semantics(
          button: true,
          label: '$played of ${bests.length} charts played',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
              child: Row(children: [
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    // Sweeps in afresh whenever the filter or measure lands on
                    // a different mix.
                    key: ValueKey(Object.hashAll([
                      m,
                      for (final t in tiers) Object.hash(t.count, t.color),
                    ])),
                    tween: Tween(begin: 0, end: 1),
                    duration: FloorPop.beat * 2,
                    curve: FloorPop.settle,
                    builder: (context, t, _) => CustomPaint(
                      size: const Size.fromHeight(6),
                      painter: _BandsPainter(tiers, bests.length, pop.stage,
                          fill: t),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text.rich(
                    TextSpan(text: '$played', children: [
                      TextSpan(
                          text: '/${bests.length}',
                          style: TextStyle(color: pop.haze)),
                    ]),
                    style: FloorPop.readout(13)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// One measure's tiers, best first, each a bar that carries on from the
/// tiers above it, so a row reads as "this tier or better". The tabs switch
/// the measure for the strip too.
class _Ladder extends StatelessWidget {
  const _Ladder(this.bests, this.onStats, this.onBinder);

  final List<ChartBest?> bests;
  final VoidCallback? onStats, onBinder;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final text = Theme.of(context).colorScheme.onSurface;
    final total = bests.length;
    final played = bests.where((b) => b != null).length;
    return ValueListenableBuilder(
      valueListenable: bestMeasure,
      builder: (context, m, _) {
        final tiers = _rings(bests)[m.ring];
        var above = 0;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.rich(
                    TextSpan(text: '$played', children: [
                      TextSpan(
                          text: '/$total',
                          style: FloorPop.readout(20, color: pop.haze)),
                    ]),
                    style: FloorPop.readout(40)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                      value: played / total,
                      minHeight: 6,
                      color: FloorPop.volt,
                      backgroundColor: pop.riser),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: pop.riser,
                      borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    for (final tab in BestMeasure.values)
                      Expanded(
                        child: Semantics(
                          selected: tab == m,
                          label: tab.name,
                          child: Material(
                            color: tab == m ? FloorPop.volt : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => bestMeasure.value = tab,
                              child: SizedBox(
                                height: 40,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  child: _measureArt(bests, tab),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(children: [
                      for (final t in tiers)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            SizedBox(
                              width: 72,
                              height: 24,
                              child: t.art != null
                                  ? Image.asset(t.art!,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.centerLeft)
                                  : Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(_kNoneLabels[m.ring],
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                              color: pop.haze))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: CustomPaint(
                                size: const Size.fromHeight(12),
                                painter: _BandsPainter(
                                    [t], total, pop.riser,
                                    lead: (above += t.count) - t.count),
                              ),
                            ),
                            SizedBox(
                              width: 36,
                              child: Text('${t.count}',
                                  textAlign: TextAlign.right,
                                  style: FloorPop.readout(15)),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ),
                if (onStats != null || onBinder != null) ...[
                  const SizedBox(height: 20),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (onStats != null)
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: pop.riser,
                              foregroundColor: text,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14))),
                          onPressed: () {
                            Navigator.of(context).pop();
                            onStats!();
                          },
                          child: const Text('All stats'),
                        ),
                      ),
                    if (onStats != null && onBinder != null)
                      const SizedBox(width: 10),
                    if (onBinder != null)
                      Expanded(
                        child: VoltButton(
                          height: 48,
                          radius: 14,
                          onPressed: () {
                            Navigator.of(context).pop();
                            onBinder!();
                          },
                          child: const Text('Open binder'),
                        ),
                      ),
                  ]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// [tiers] as bands left to right, out of [total] charts on a [track]:
/// [lead] charts' worth of the first band's colour, faint, before them, and
/// only [fill] of the way drawn, for an entrance.
class _BandsPainter extends CustomPainter {
  _BandsPainter(this.tiers, this.total, this.track,
      {this.lead = 0, this.fill = 1});

  final List<_Tier> tiers;
  final int total, lead;
  final Color track;
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final whole = Offset.zero & size;
    canvas.clipRRect(
        RRect.fromRectAndRadius(whole, Radius.circular(size.height / 2)));
    canvas.drawRect(whole, Paint()..color = track);
    final unit = size.width / total * fill;
    var x = 0.0;
    if (lead > 0 && tiers.isNotEmpty) {
      x = lead * unit;
      canvas.drawRect(Rect.fromLTWH(0, 0, x, size.height),
          Paint()..color = tiers.first.color.withValues(alpha: 0.3));
    }
    for (final t in tiers) {
      final band = Rect.fromLTWH(x, 0, t.count * unit, size.height);
      canvas.drawRect(
          band,
          Paint()
            ..color = t.color
            ..shader = t.rainbow == null
                ? null
                : LinearGradient(colors: t.rainbow!).createShader(band));
      x = band.right;
    }
  }

  @override
  bool shouldRepaint(_BandsPainter old) =>
      old.tiers != tiers ||
      old.total != total ||
      old.lead != lead ||
      old.track != track ||
      old.fill != fill;
}

/// The tiers counted out: grade, clear lamp and flare, each a grid of
/// [columns] tiles across, badge on the left and count on the right, so
/// the columns line up from section to section. [rise] wraps the [i]th
/// section, for an entrance.
class BestTiers extends StatelessWidget {
  const BestTiers(this.bests,
      {super.key, this.columns = 3, this.rise, this.labelColor});
  final List<ChartBest?> bests;
  final int columns;
  final Widget Function(int i, Widget section)? rise;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final rings = _rings(bests);
    const gap = 6.0;
    Widget section(
            String title, String none, List<_Tier> tiers, double aspect) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: labelColor ?? pop.haze)),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, box) =>
                  Wrap(spacing: gap, runSpacing: gap, children: [
                for (final t in tiers)
                  ArtTile(t.art,
                      aspect: aspect,
                      ink: 12,
                      width: (box.maxWidth - (columns - 1) * gap) / columns,
                      height: 30,
                      label: Text(none,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: labelColor ?? pop.haze)),
                      trailing: Text('${t.count}',
                          style: FloorPop.readout(14).copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
              ]),
            ),
          ],
        );
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (title, aspect)) in const [
            ('GRADE', kGradeAspect),
            ('CLEAR LAMP', kLampAspect),
            ('FLARE', kFlareAspect),
          ].indexed)
            if (rings[i].isNotEmpty) ...[
              if (rings.take(i).any((r) => r.isNotEmpty))
                const SizedBox(height: 14),
              (rise ?? (_, s) => s)(
                  i, section(title, _kNoneLabels[i], rings[i], aspect)),
            ],
        ]);
  }
}
