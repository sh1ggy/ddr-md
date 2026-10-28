/// Name: BestRings
/// Parent: DifficultyListPage
/// Description: The listed charts' bests as three nested rings, in the
/// cabinet's order from the outside in: grade, lamp, flare. Each fills
/// clockwise from the top, best tier first, in the stats page's colours;
/// played charts without one follow in grey, and the rest is the unplayed.
/// Tapped, the rings lift out of the list and grow into a card that counts
/// every tier.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/song/scores/art_badge.dart';
import 'package:ddr_md/components/song/scores/score_card.dart'
    show clearLampIcon;
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/db_models.dart' show ClearLamp;
import 'package:ddr_md/theme.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// [rainbow] sweeps along the arc in place of its colour. [art] is the tier's
// badge, null for the played charts without one.
typedef _Tier = ({int count, Color color, List<Color>? rainbow, String? art});

// What the charts without a tier are called in the card, ring by ring.
const _kNoneLabels = ['NO GRADE', 'NO LAMP', 'NO FLARE'];

const _kNone = Color(0xFF757575);

// A ring's stroke as a share of the rings' size, and the step from one ring
// to the next in strokes: thin enough to leave the middle room for its label.
const _kStroke = 11.0, _kStep = 1.25;

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

// Grade, lamp and flare, outside in.
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

class BestRings extends StatefulWidget {
  const BestRings(this.bests, {super.key, this.size = 30, this.onStats});

  /// One per listed chart, null where it hasn't been played.
  final List<ChartBest?> bests;
  final double size;

  /// Opens the full stats, from the expanded card.
  final VoidCallback? onStats;

  @override
  State<BestRings> createState() => _BestRingsState();
}

class _BestRingsState extends State<BestRings> {
  // Whether the rings are out in the expanded card, leaving their spot empty.
  bool _out = false;

  Future<void> _expand() async {
    final box = context.findRenderObject() as RenderBox;
    final from = box.localToGlobal(Offset.zero) & box.size;
    HapticFeedback.lightImpact();
    setState(() => _out = true);
    // The root navigator, so the card covers the whole screen and [from]
    // lines up with it.
    final route = PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: FloorPop.beat + FloorPop.eighth,
      reverseTransitionDuration: FloorPop.beat,
      pageBuilder: (_, animation, __) =>
          _ExpandedRings(widget.bests, from, animation, widget.onStats),
    );
    Navigator.of(context, rootNavigator: true).push(route);
    // Back in their spot only once they've flown home.
    await route.completed;
    if (mounted) setState(() => _out = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bests.isEmpty) return const SizedBox.shrink();
    final rings = _rings(widget.bests);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _expand,
      child: Opacity(
        opacity: _out ? 0 : 1,
        child: TweenAnimationBuilder<double>(
          // Sweeps in afresh whenever the filter lands on a different mix.
          key: ValueKey(Object.hashAll([
            for (final ring in rings)
              for (final t in ring) Object.hash(t.count, t.color),
          ])),
          tween: Tween(begin: 0, end: 1),
          duration: FloorPop.beat * 2,
          curve: FloorPop.settle,
          builder: (context, t, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _RingsPainter(rings, widget.bests.length, [t, t, t],
                Theme.of(context).colorScheme.surfaceContainerHighest),
          ),
        ),
      ),
    );
  }
}

/// The rings flying from [from] to the top of a card, each spinning into
/// place a little after the one outside it, while the card's counts rise in
/// below.
class _ExpandedRings extends StatefulWidget {
  const _ExpandedRings(this.bests, this.from, this.animation, this.onStats);

  final List<ChartBest?> bests;
  final Rect from;
  final Animation<double> animation;
  final VoidCallback? onStats;

  @override
  State<_ExpandedRings> createState() => _ExpandedRingsState();
}

class _ExpandedRingsState extends State<_ExpandedRings> {
  final _slot = GlobalKey();
  // Where the rings land, once the card has laid out.
  Rect? _to;

  late final _flight = CurvedAnimation(
      parent: widget.animation,
      curve: FloorPop.settle,
      reverseCurve: Curves.easeInCubic);

  void _measure() {
    final box = _slot.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final to = box.localToGlobal(Offset.zero) & box.size;
    if (to != _to) setState(() => _to = to);
  }

  @override
  void dispose() {
    _flight.dispose();
    super.dispose();
  }

  // [child] rising in over the [i]th stretch of the card's entrance.
  Widget _rise(int i, Widget child) {
    final start = 0.3 + i * 0.1;
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(
            Interval(start, math.min(start + 0.4, 1))
                .transform(widget.animation.value));
        return Opacity(
          opacity: t,
          child: Transform.translate(
              offset: Offset(0, 16 * (1 - t)), child: child),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final pop = FloorPop.of(context);
    final rings = _rings(widget.bests);
    final total = widget.bests.length;
    final played = widget.bests.where((b) => b != null).length;
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.padding.vertical - 48;
    final size = math.min(
        math.min(media.size.width - 120, 220.0), availableHeight * 0.28);
    // The card's ground, so the unplayed reads against it.
    final track = pop.stage;

    // Every kind in one three-column grid of tiles, badge on the left and
    // count on the right, so the columns line up from section to section.
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
                    color: pop.haze)),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, box) =>
                  Wrap(spacing: gap, runSpacing: gap, children: [
                for (final t in tiers)
                  ArtTile(t.art,
                      aspect: aspect,
                      ink: 12,
                      width: (box.maxWidth - 2 * gap) / 3,
                      height: 30,
                      label: Text(none,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: pop.haze)),
                      trailing: Text('${t.count}',
                          style: FloorPop.readout(14).copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))),
              ]),
            ),
          ],
        );

    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Material(
        color: pop.riser,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: SizedBox.square(key: _slot, dimension: size)),
              const SizedBox(height: 10),
              Text('$played of $total charts played',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: pop.haze)),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 18),
                      for (final (i, (title, aspect)) in const [
                        ('GRADE', kGradeAspect),
                        ('CLEAR LAMP', kLampAspect),
                        ('FLARE', kFlareAspect),
                      ].indexed)
                        if (rings[i].isNotEmpty) ...[
                          _rise(
                              i,
                              section(
                                  title, _kNoneLabels[i], rings[i], aspect)),
                          const SizedBox(height: 14),
                        ],
                      if (widget.onStats != null)
                        _rise(
                            3,
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onStats!();
                                },
                                child: const Text('All stats'),
                              ),
                            )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Transparent Material, so the rings' label has a text style to inherit.
    return Material(
        type: MaterialType.transparency,
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FadeTransition(
                    opacity: CurvedAnimation(
                        parent: widget.animation,
                        curve: const Interval(0.15, 0.6)),
                    child: card),
              ),
            ),
          ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: widget.animation,
              builder: (context, _) {
                final v = widget.animation.value;
                final rect =
                    Rect.lerp(widget.from, _to ?? widget.from, _flight.value)!;
                // On the way in each ring fills afresh, a little after the one
                // outside it; on the way out they stay full, to land as the
                // rings in the list.
                final fills = [
                  for (var i = 0; i < rings.length; i++)
                    widget.animation.status == AnimationStatus.reverse
                        ? 1.0
                        : FloorPop.settle.transform(
                            Interval(0.15 + i * 0.1, 0.8 + i * 0.1)
                                .transform(v)),
                ];
                final label = const Interval(0.5, 1).transform(v);
                return Stack(children: [
                  Positioned.fromRect(
                    rect: rect,
                    child: CustomPaint(
                      painter: _RingsPainter(rings, total, fills, track),
                      // The share played, in the innermost ring's hole. The
                      // last percent counts down what's left instead, and
                      // every chart played earns a tick.
                      child: Center(
                        child: Opacity(
                          opacity: label,
                          child: SizedBox.square(
                            dimension: rect.shortestSide * 0.28,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: played == total
                                  ? const Icon(Icons.check_rounded,
                                      size: 28, color: FloorPop.volt)
                                  : Text(
                                      played * 100 ~/ total >= 99
                                          ? '${total - played} left'
                                          : '${played * 100 ~/ total}%',
                                      style: FloorPop.readout(20)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ]));
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.rings, this.total, this.fills, this.track);

  final List<List<_Tier>> rings;
  final int total;
  // How much of each ring is drawn, 0 to 1.
  final List<double> fills;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide / _kStroke;
    final half = stroke / 2;
    final center = size.center(Offset.zero);
    // Angles from here on run clockwise from the top.
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-math.pi / 2);
    for (var i = 0; i < rings.length; i++) {
      final radius = size.shortestSide / 2 - stroke * (0.5 + i * _kStep);
      final outer = Rect.fromCircle(center: Offset.zero, radius: radius + half);
      final inner = Rect.fromCircle(center: Offset.zero, radius: radius - half);
      canvas.drawCircle(
          Offset.zero,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..color = track);
      final drawn = <(double, double, _Tier)>[];
      var start = 0.0;
      for (final tier in rings[i]) {
        // Just short of a whole turn, which an arc would draw as nothing.
        final sweep = math.min(
            tier.count / total * 2 * math.pi * fills[i], 2 * math.pi - 1e-3);
        if (sweep <= 0) continue;
        drawn.add((start, sweep, tier));
        start += sweep;
      }
      final cap = half / radius;
      // The ends round out past the ring, but flatten as the gap between
      // them closes, so a complete ring closes into a plain loop: there's no
      // going past every chart.
      final depth = math.min(half, (2 * math.pi - start) * radius / 2);
      // A half oval [depth] deep past [angle], ahead of it or ([dir] -1)
      // behind it.
      Path endAt(double angle, double dir) {
        final n = Offset(math.cos(angle), math.sin(angle));
        final t = Offset(-n.dy, n.dx) * dir;
        return Path()
          ..addPolygon([
            for (var j = 0; j <= 16; j++)
              n * radius +
                  n * (half * math.cos(j * math.pi / 16)) +
                  t * (depth * math.sin(j * math.pi / 16)),
          ], true);
      }

      for (final (k, (start, sweep, tier)) in drawn.indexed) {
        final end = start + sweep;
        // Each tier a band of its own, cut straight where it meets the
        // next; only the ring's first and last ends are rounded, and only
        // past the band, so a short tier keeps its colour to itself.
        var band = Path()
          ..arcTo(outer, start, sweep, true)
          ..arcTo(inner, end, -sweep, false)
          ..close();
        if (depth > 0.5) {
          if (k == drawn.length - 1) {
            band = Path.combine(PathOperation.union, band, endAt(end, 1));
          }
          if (k == 0) {
            band = Path.combine(PathOperation.union, band, endAt(start, -1));
          }
        }
        // From the start of the round end, so a rainbow runs over both ends
        // rather than wrapping at the top.
        canvas.drawPath(
            band,
            Paint()
              ..color = tier.color
              ..shader = tier.rainbow == null
                  ? null
                  : SweepGradient(
                          colors: tier.rainbow!,
                          endAngle: sweep + 2 * cap,
                          transform: GradientRotation(start - cap))
                      .createShader(outer));
      }
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.rings != rings ||
      old.total != total ||
      old.track != track ||
      !listEquals(old.fills, fills);
}
