/// Name: ArtBadge
/// Parent: ChartBestBadges, ScoreBadges, RecentPlays, BestRings,
/// ScoreOverviewPage
/// Description: Grade, lamp and flare art as badges: a tag tinted and
/// underlined in its tier's colour, pressed in where there's nothing to show.
/// High tiers catch a light that sweeps across them every few seconds, and
/// the best of each kind (AAA, MFC, flare EX) has a holo foil drifting under
/// its art. As a tile, the badge takes in a count beside its art.
library;

import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks;
import 'package:ddr_md/models/db_models.dart' show ClearLamp;
import 'package:flutter/material.dart';

/// Widest drawn part of each kind of art: grades are about 1.6:1, flare
/// badges at most 1.3:1, and the plain CLEAR lamp the widest lamp at 4:1.
const kGradeAspect = 1.65, kLampAspect = 4.05, kFlareAspect = 1.3;

// Each art's tier colour (null for a rainbow), whether it shines (AAA, MFC
// and PFC, flare EX and IX) and whether it's foiled (AAA, MFC, flare EX).
final _tiers = <String, (Color?, bool, bool)>{
  for (final g in Grade.values)
    gradeIcon(g): (gradeColor(g), g == Grade.aaa, g == Grade.aaa),
  fullComboIcon(FullComboTier.mfc)!: (null, true, true),
  fullComboIcon(FullComboTier.pfc)!: (kLampColors[ClearLamp.pfc], true, false),
  fullComboIcon(FullComboTier.gfc)!: (kLampColors[ClearLamp.gfc], false, false),
  fullComboIcon(FullComboTier.fc)!: (kLampColors[ClearLamp.fc], false, false),
  clearIcon: (kLampColors[ClearLamp.clear], false, false),
  life4Icon: (kLampColors[ClearLamp.life4], false, false),
  for (final r in kFlareRanks)
    flareRankIcon(r): (
      r == 'EX' ? null : flareColor(r),
      r == 'EX' || r == 'IX',
      r == 'EX'
    ),
};

/// [art] as a badge [aspect] times [ink] wide, the art's visible part (not
/// its image's margin) drawn [ink] tall so every kind reads at one size.
class ArtBadge extends StatelessWidget {
  const ArtBadge(this.art,
      {super.key,
      required this.aspect,
      required this.ink,
      required this.height,
      this.color});

  final String? art;
  final double aspect;
  final double ink;
  final double height;
  // Tint for art outside the tiers above (a fail, no flare).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tier = _tiers[art];
    return CardBadge(
      width: ink * aspect + 8,
      height: height,
      color: tier == null ? color : tier.$1 ?? kFlareExColors.first,
      rainbow: tier != null && tier.$1 == null,
      shine: tier?.$2 ?? false,
      foil: tier?.$3 ?? false,
      child: art == null ? null : _image(art!, ink),
    );
  }

  static Widget _image(String art, double ink) => OverflowBox(
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Image.asset(art, height: ink / _drawnHeight(art)));

  // How much of an art's height is drawn, the rest being transparent margin.
  static double _drawnHeight(String art) => art.contains('/rank_')
      ? 0.74
      : art == clearIcon || art == life4Icon
          ? 0.67
          : 1;
}

/// A badge: raised and tinted [color] when it holds something, pressed in
/// when it's empty, so a missing grade, flare or lamp still keeps its place.
/// [art] with a [trailing] count beside it, the whole tile one badge [width]
/// wide: tinted, shining and foiled as [ArtBadge] would be. [label] stands in
/// where there's no art.
class ArtTile extends StatelessWidget {
  const ArtTile(this.art,
      {super.key,
      required this.aspect,
      required this.ink,
      required this.width,
      required this.height,
      required this.trailing,
      this.label,
      this.color});

  final String? art;
  final double aspect;
  final double ink;
  final double width;
  final double height;
  final Widget trailing;
  final Widget? label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tier = _tiers[art];
    return CardBadge(
      width: width,
      height: height,
      color: tier == null ? color : tier.$1 ?? kFlareExColors.first,
      rainbow: tier != null && tier.$1 == null,
      shine: tier?.$2 ?? false,
      foil: tier?.$3 ?? false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(children: [
          if (art != null)
            SizedBox(
                width: ink * aspect,
                height: ink,
                child: ArtBadge._image(art!, ink))
          else if (label != null)
            Flexible(
                flex: 2, child: FittedBox(fit: BoxFit.scaleDown, child: label)),
          const SizedBox(width: 4),
          // Narrows on a phone too slim for a lamp and four digits.
          Expanded(
            child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: trailing),
          ),
        ]),
      ),
    );
  }
}

class CardBadge extends StatefulWidget {
  const CardBadge(
      {super.key,
      this.child,
      required this.width,
      required this.height,
      this.color,
      this.rainbow = false,
      this.shine = false,
      this.foil = false});

  final Widget? child;
  final double width;
  final double height;
  // Tints the badge and underlines it; none leaves it plain.
  final Color? color;
  // Underlined in [kFlareExColors] instead of [color], and foiled in them
  // rather than gold.
  final bool rainbow;
  final bool shine;
  final bool foil;

  @override
  State<CardBadge> createState() => _CardBadgeState();
}

class _CardBadgeState extends State<CardBadge>
    with SingleTickerProviderStateMixin {
  // Whole shines (3.2 s) and foil drifts (4 s) both fit, so one clock runs
  // both.
  static const _period = Duration(seconds: 16);
  late final _clock = AnimationController(vsync: this, duration: _period);

  void _syncClock() {
    final animate = (widget.shine || widget.foil) &&
        widget.child != null &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_clock.isAnimating) {
      // Phased by the wall clock, so every badge on screen moves together.
      _clock.value = DateTime.now().millisecondsSinceEpoch %
          _period.inMilliseconds /
          _period.inMilliseconds;
      _clock.repeat();
    }
    if (!animate) _clock.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  @override
  void didUpdateWidget(CardBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClock();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (widget.child == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0x73000000), Color(0x33000000)]
                : const [Color(0x1F000000), Color(0x0A000000)],
          ),
        ),
      );
    }
    final base = dark ? const Color(0x47000000) : const Color(0xBFFFFFFF);
    var color = widget.color;
    // A white tier (flare VIII) would vanish on the light theme's badge.
    if (color != null && !dark && color.computeLuminance() > 0.7) {
      color = Color.lerp(color, Colors.black, 0.3);
    }
    final radius = color == null
        ? BorderRadius.circular(6)
        : const BorderRadius.vertical(
            top: Radius.circular(6), bottom: Radius.circular(3));
    final badge = ClipRRect(
      borderRadius: radius,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: color == null
              ? base
              : Color.alphaBlend(
                  color.withValues(alpha: widget.rainbow ? 0.1 : 0.2), base),
          border: Border.all(
              color: dark ? const Color(0x1FFFFFFF) : const Color(0x14000000),
              width: 0.5),
        ),
        // Painted straight from the clock, so a frame repaints the badge
        // without rebuilding it. The foil stays, still, when motion is off.
        child: CustomPaint(
          painter: widget.foil ? _Foil(_clock, rainbow: widget.rainbow) : null,
          foregroundPainter:
              _clock.isAnimating && widget.shine ? _Shine(_clock) : null,
          child: Stack(fit: StackFit.expand, children: [
            Center(child: widget.child),
            if (color != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.rainbow ? null : color,
                    gradient: widget.rainbow
                        ? const LinearGradient(colors: kFlareExColors)
                        : null,
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
    // Its own layer while it moves, so the card around it doesn't repaint.
    return _clock.isAnimating ? RepaintBoundary(child: badge) : badge;
  }
}

double _seconds(Animation<double> clock) =>
    clock.value * _CardBadgeState._period.inMilliseconds / 1000;

/// Holo foil under a badge's art: bands of colour, slanted, drifting across
/// once every 4 s.
class _Foil extends CustomPainter {
  _Foil(this.clock, {required this.rainbow}) : super(repaint: clock);

  final Animation<double> clock;
  final bool rainbow;

  static final _rainbow = [
    for (final c in [...kFlareExColors, kFlareExColors.first])
      c.withValues(alpha: 0.3)
  ];
  static final _gold = [
    for (final c in const [
      Color(0xFF8A6512),
      Color(0xFFFFE98A),
      Color(0xFFC99A1E),
      Color(0xFFFFF6CF),
      Color(0xFFA8780F),
      Color(0xFF8A6512),
    ])
      c.withValues(alpha: 0.4)
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final drift = _seconds(clock) / 4 % 1;
    // Plain alpha over the badge rather than a blend mode, which would need
    // an offscreen pass every frame.
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: rainbow ? _rainbow : _gold,
            tileMode: TileMode.repeated,
            transform: _Drift(drift),
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(_Foil old) => old.rainbow != rainbow;
}

/// A light sweeping across a badge: rests, then crosses in under a second,
/// every 3.2 s.
class _Shine extends CustomPainter {
  _Shine(this.clock) : super(repaint: clock);

  final Animation<double> clock;

  static final _light = [
    Colors.white.withValues(alpha: 0),
    Colors.white.withValues(alpha: 0.4),
    Colors.white.withValues(alpha: 0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = (_seconds(clock) / 3.2 % 1 - 0.55) / 0.3;
    if (t <= 0 || t >= 1) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: const Alignment(-1, -0.4),
            end: const Alignment(1, 0.4),
            colors: _light,
            stops: const [0.35, 0.5, 0.65],
            transform: _Slide(Curves.easeInOut.transform(t) * 2.4 - 1.2),
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(_Shine old) => false;
}

// Slants a gradient's bands and shifts them across by [fraction] of one
// repeat, the badge's width, so a whole drift lands back where it started.
class _Drift extends GradientTransform {
  const _Drift(this.fraction);

  final double fraction;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * fraction, 0, 0)
        ..multiply(Matrix4.skewX(-0.5));
}

// Shifts a gradient sideways by [fraction] of the badge's width.
class _Slide extends GradientTransform {
  const _Slide(this.fraction);

  final double fraction;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * fraction, 0, 0);
}
