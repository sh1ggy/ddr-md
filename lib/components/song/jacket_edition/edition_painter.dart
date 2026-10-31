/// Name: EditionPainter
/// Parent: JacketEdition
/// Description: Two owned static display lists and one bounded light pass.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:ddr_md/grades.dart' show kFlareCardColors, kFlareExColors;
import 'package:flutter/material.dart';
import 'edition_model.dart';
import 'edition_catalog.dart';
import 'edition_motion.dart';

/// Per-viewer resources. No raster masks, retained textures, blur, saveLayer,
/// or global combination cache. Recreated only on a recipe/size change.
class EditionGeometry {
  EditionGeometry(this.recipe, this.size, {this.compact = false}) {
    final side = size.shortestSide;
    width = side * editionFrameWidths[recipe.frame]!;
    outer = at(0);
    inner = at(width);
    innerRect = (Offset.zero & size).deflate(width);
    ring = Path.combine(PathOperation.difference, outer, inner);
    glints = List.unmodifiable(List.generate(
        compact ? 0 : editionGlintCount,
        (i) => Offset(size.width * (.12 + (i * .173) % .77),
            size.height * (.15 + (i * .293) % .70))));
    final random = math.Random(recipe.flareIndex + 1);
    sparks = List.unmodifiable(List.generate(
        recipe.flareIndex < 0
            ? 0
            : compact
                ? editionCompactSparks
                : recipe.ex
                    ? editionMaxSparks
                    : editionSparksPerRank * (recipe.flareIndex % 3 + 2),
        (_) => (
              along: random.nextDouble(),
              phase: random.nextDouble(),
              speed: 1.6 + random.nextDouble() * 1.6,
              size: .009 + random.nextDouble() * .009,
              out: (random.nextDouble() - .3) * .05,
            )));
    final back = ui.PictureRecorder();
    _recordFrame(Canvas(back));
    frame = back.endRecording();
    final front = ui.PictureRecorder();
    _recordMotif(Canvas(front));
    motif = front.endRecording();
  }
  final EditionRecipe recipe;
  final Size size;
  final bool compact;
  late final double width;
  late final Path outer, inner, ring;
  late final Rect innerRect;

  /// The card's outline [inset] in from its edge (out, when negative), its
  /// corners the difficulty's.
  Path at(double inset) {
    final side = size.shortestSide;
    final r = (Offset.zero & size).deflate(inset);
    final shape = editionCorners[recipe.difficultyShape];
    // A rounded corner's radius shrinks by the inset; a cut's legs by less,
    // so the cut stays parallel.
    double leg(bool round, double at) =>
        math.max(0, side * at - inset * (round ? 1 : 2 - math.sqrt2));
    final corners = [
      for (var i = 0; i < 4; i++)
        shape.alternate && i.isOdd
            ? (round: true, leg: leg(true, .015))
            : (round: shape.round, leg: leg(shape.round, shape.size)),
    ];
    final path = Path()..moveTo(r.left + corners[0].leg, r.top);
    void turn(int i, Offset to) => corners[i].round
        ? path.arcToPoint(to, radius: Radius.circular(corners[i].leg))
        : path.lineTo(to.dx, to.dy);
    path.lineTo(r.right - corners[1].leg, r.top);
    turn(1, Offset(r.right, r.top + corners[1].leg));
    path.lineTo(r.right, r.bottom - corners[2].leg);
    turn(2, Offset(r.right - corners[2].leg, r.bottom));
    path.lineTo(r.left + corners[3].leg, r.bottom);
    turn(3, Offset(r.left, r.bottom - corners[3].leg));
    path.lineTo(r.left, r.top + corners[0].leg);
    turn(0, Offset(r.left + corners[0].leg, r.top));
    return path..close();
  }

  late final ui.Picture frame, motif;
  late final List<Offset> glints;
  late final List<EditionSpark> sparks;

  void _recordFrame(Canvas canvas) {
    final palette = editionFramePalettes[recipe.frame]!;
    final rect = Offset.zero & size;
    canvas.drawPath(
        outer,
        Paint()
          ..shader = (recipe.frame == EditionFrame.rainbow
                  ? const SweepGradient(colors: editionRainbowFrame)
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                          palette[0],
                          palette[1],
                          palette[2],
                          palette[1],
                          palette[0]
                        ],
                      stops: const [
                          0,
                          .22,
                          .5,
                          .76,
                          1
                        ]))
              .createShader(rect));
    final line = Paint()..style = PaintingStyle.stroke;
    // Raised bevel remains visible with motion disabled, especially PFC.
    for (final (inset, alpha) in [
      (width * .17, .75),
      (width * .38, .25),
      (width * .78, .65)
    ]) {
      canvas.drawPath(
          at(inset),
          line
            ..strokeWidth = math.max(.5, width * .065)
            ..color = palette[1].withValues(alpha: alpha));
    }
    final side = size.shortestSide;
    final engraving = Paint()
      ..color = palette[0].withValues(alpha: .65)
      ..strokeWidth = math.max(.5, side / 1100);
    final step = side / (recipe.border == EditionBorder.engraved ? 44 : 28);
    for (var x = side * .09;
        !compact && x < size.width - side * .09;
        x += step) {
      final length = width * (recipe.border == EditionBorder.bevel ? .22 : .42);
      canvas.drawLine(
          Offset(x, width * .32), Offset(x + length, width * .68), engraving);
      canvas.drawLine(Offset(x, size.height - width * .32),
          Offset(x - length, size.height - width * .68), engraving);
    }
    final tier = recipe.tier;
    if (tier != null && !compact) {
      // The tier as gems set in the frame's foot, lit up to it.
      final gem = side * editionGemSize, gap = side * editionGemGap;
      for (var i = 0; i < 10; i++) {
        // Centred on the frame's foot, overlapping the art when it's thin.
        final c = Offset(
            size.width / 2 + (i - 4.5) * gap, size.height - width / 2);
        final stone = Path()
          ..moveTo(c.dx, c.dy - gem * .6)
          ..lineTo(c.dx + gem / 2, c.dy)
          ..lineTo(c.dx, c.dy + gem * .6)
          ..lineTo(c.dx - gem / 2, c.dy)
          ..close();
        canvas.drawPath(
            stone,
            Paint()
              ..shader = i <= tier
                  ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: editionGem)
                      .createShader(stone.getBounds())
                  : null
              ..color = Color.lerp(palette[0], Colors.black, .4)!);
        canvas.drawPath(
            stone,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(.5, gem * .08)
              ..color = palette[1].withValues(alpha: i <= tier ? .9 : .4));
      }
    }
    final pearl = recipe.frame == EditionFrame.platinum;
    if (pearl || recipe.ex) {
      // Thin inlay preserves the metal substrate under EX.
      canvas.drawPath(
          at(width * (pearl ? .52 : .12)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width * .15
            ..shader = SweepGradient(
                    colors: pearl
                        ? [
                            for (final c in editionPearl)
                              c.withValues(alpha: .9)
                          ]
                        : editionSpectrum)
                .createShader(rect));
    }
  }

  void _recordMotif(Canvas canvas) {
    canvas.save();
    canvas.clipPath(inner);
    final side = size.shortestSide;
    final finish = recipe.finish;
    final textured = finish.index >= EditionFinish.texturedHolo.index;
    final pearl = recipe.frame == EditionFrame.platinum;
    final premium = pearl || recipe.frame == EditionFrame.rainbow;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.45, side / 1100);
    if (recipe.failed) {
      canvas.drawRect(innerRect, Paint()..color = const Color(0x22000000));
    }
    if (finish != EditionFinish.print || premium) {
      final cut = editionCuts[recipe.cut]!;
      final count = math.min(
          compact ? editionCompactMotifLines : editionMaxMotifLines, cut.lines);
      paint.color = (pearl ? const Color(0xFFFFF4E2) : Colors.white).withValues(
          alpha: premium
              ? .13
              : textured
                  ? .075
                  : .025);
      final shape = recipe.motif;
      final angle = cut.angle +
          (shape == EditionMotif.classic
              ? .4
              : shape == EditionMotif.gold
                  ? -.4
                  : 0);
      canvas.save();
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(angle);
      for (var i = -count ~/ 2; i <= count ~/ 2; i++) {
        final x = i * side * 1.5 / count;
        if (shape == EditionMotif.white) {
          canvas.drawCircle(Offset.zero, x.abs() + side * .08, paint);
        } else {
          canvas.drawLine(Offset(x, -side), Offset(x, side), paint);
          if (cut.cross && (textured || shape == EditionMotif.gold)) {
            canvas.drawLine(Offset(-side, x), Offset(side, x), paint);
          }
        }
      }
      canvas.restore();
    }
    if (premium || finish == EditionFinish.prism) {
      paint.color = pearl ? const Color(0x66FFF4E2) : const Color(0x44FFFFFF);
      for (var i = 0; i < (compact ? editionCompactGlints : 28); i++) {
        final p = Offset(size.width * (.08 + (i * .61803) % .84),
            size.height * (.08 + (i * .38197) % .84));
        final d = side * (recipe.frame == EditionFrame.rainbow ? .005 : .003);
        canvas.drawLine(p - Offset(d, 0), p + Offset(d, 0), paint);
        canvas.drawLine(p - Offset(0, d), p + Offset(0, d), paint);
      }
    }
    // Complete static finish. This stays when motion is disabled.
    final strength = compact ? editionCompactFinishStrength : 1.0;
    final alpha = editionFinishAlpha[finish.index] * recipe.strength * strength;
    if (alpha > 0 || pearl) {
      canvas.drawRect(
          innerRect,
          Paint()
            ..shader = LinearGradient(
                    colors: pearl
                        ? [
                            for (final color in editionPearl)
                              color.withValues(alpha: color.a * strength)
                          ]
                        : [
                            Colors.transparent,
                            Colors.white.withValues(alpha: alpha),
                            Colors.transparent
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)
                .createShader(innerRect));
    }
    canvas.restore();
  }

  void dispose() {
    frame.dispose();
    motif.dispose();
  }
}

/// Clips to [path], a card outline.
class EditionClipper extends CustomClipper<Path> {
  const EditionClipper(this.path);
  final Path path;
  @override
  Path getClip(Size size) => path;
  @override
  bool shouldReclip(EditionClipper old) => old.path != path;
}

class EditionStaticPainter extends CustomPainter {
  EditionStaticPainter(this.geometry,
      {this.foreground = false, this.ring = false});
  final EditionGeometry geometry;
  final bool foreground;
  // The frame alone, without the art over its middle: only its ring.
  final bool ring;
  @override
  void paint(Canvas canvas, Size size) {
    if (ring) {
      canvas.save();
      canvas.clipPath(geometry.ring);
    }
    canvas.drawPicture(foreground ? geometry.motif : geometry.frame);
    if (ring) canvas.restore();
  }

  @override
  bool shouldRepaint(EditionStaticPainter old) =>
      old.geometry != geometry ||
      old.foreground != foreground ||
      old.ring != ring;
}

class EditionLightPainter extends CustomPainter {
  EditionLightPainter(this.geometry, this.motion,
      {this.layers = editionAllLayers})
      : super(repaint: motion);
  final EditionGeometry geometry;
  final EditionMotion motion;
  final Set<EditionLayer> layers;
  final Paint _paint = Paint();
  @override
  void paint(Canvas canvas, Size size) {
    final recipe = geometry.recipe;
    final at =
        Offset(motion.light.dx * size.width, motion.light.dy * size.height);
    final rect = Offset.zero & size;
    if (layers.contains(EditionLayer.finish)) _finish(canvas, size, at);
    if (layers.contains(EditionLayer.frame) &&
        recipe.frame == EditionFrame.rainbow) {
      // A glint running round the rainbow frame.
      _paint
        ..color = Colors.white
        ..shader = SweepGradient(colors: const [
          Color(0x00FFFFFF),
          Color(0xB3FFFFFF),
          Color(0x00FFFFFF),
          Color(0x00FFFFFF)
        ], stops: const [
          0,
          .06,
          .12,
          1
        ], transform: GradientRotation(motion.time * 1.6))
            .createShader(rect);
      canvas.drawPath(geometry.ring, _paint);
      _paint.shader = null;
    }
  }

  void _finish(Canvas canvas, Size size, Offset at) {
    final recipe = geometry.recipe;
    final side = size.shortestSide;
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipPath(geometry.outer);
    if (recipe.finish == EditionFinish.prism) {
      // AAA's gold foil, as on its badge, drifting with the light.
      final drift = (motion.light.dx + motion.light.dy) * side * .4;
      _paint.shader = ui.Gradient.linear(
          Offset(drift, 0),
          Offset(drift + side * .45, side * .3),
          editionGoldFoil,
          [
            for (var i = 0; i < editionGoldFoil.length; i++)
              i / (editionGoldFoil.length - 1)
          ],
          TileMode.repeated);
      canvas.drawRect(rect, _paint);
    }
    // The light sweeps only where a badge would shine: AAA, GFC, PFC, SDP
    // and MFC frames, flare IX and EX.
    final shines = recipe.finish == EditionFinish.prism ||
        recipe.frame.index >= EditionFrame.silver.index ||
        recipe.flareIndex >= 8;
    if (!shines) {
      canvas.restore();
      return;
    }
    // Exactly one animated full-card gradient; no per-axis blend layers.
    final pearl = recipe.frame == EditionFrame.platinum;
    _paint.shader = ui.Gradient.linear(
        at - Offset(side * .5, side * .18),
        at + Offset(side * .5, side * .18),
        pearl
            ? editionPearl
            : [
                Colors.transparent,
                Colors.white.withValues(alpha: .22),
                Colors.transparent
              ],
        pearl ? const [0, .25, .5, .75, 1] : const [0, .5, 1]);
    canvas.drawRect(rect, _paint);
    _paint.shader = null;
    // Six cheap unblurred glints, all positions precomputed.
    for (var i = 0; i < geometry.glints.length; i++) {
      final p = geometry.glints[i];
      final near = (1 - (p - at).distance / (side * .6)).clamp(0.0, 1.0);
      if (near <= 0) continue;
      _paint.color = Colors.white.withValues(alpha: near * .65);
      final d = side * .006 * near;
      canvas.drawLine(p - Offset(d, 0), p + Offset(d, 0), _paint);
      canvas.drawLine(p - Offset(0, d), p + Offset(0, d), _paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(EditionLightPainter old) =>
      old.geometry != geometry || old.motion != motion;
}

typedef EditionSpark = ({
  double along,
  double phase,
  double speed,
  double size,
  double out
});

/// The flare's aura, outside the art: a halo round the card and particles
/// on its edge, stronger up each band. I–III sparks rise, IV–VI motes run
/// round the frame, VII–IX stars twinkle and EX's stars and halo are rainbow.
/// Unblurred; without [motion] it holds its first frame.
class EditionFlarePainter extends CustomPainter {
  EditionFlarePainter(this.geometry,
      [this.motion, this.layers = editionAllLayers])
      : super(repaint: motion);
  final EditionGeometry geometry;
  final EditionMotion? motion;
  // EX's polychrome belongs to the art; the halo and particles to the aura.
  final Set<EditionLayer> layers;
  final Paint _paint = Paint();

  static final _star = () {
    final path = Path()..moveTo(0, -1);
    for (final (x, y) in [
      (.2, -.2),
      (1.0, 0.0),
      (.2, .2),
      (0.0, 1.0),
      (-.2, .2),
      (-1.0, 0.0),
      (-.2, -.2),
    ]) {
      path.lineTo(x, y);
    }
    return path..close();
  }();

  // A point [along] the card's edge, clockwise from the top left, pushed
  // [out] of it.
  static Offset _edge(Size size, double along, double out) {
    final w = size.width, h = size.height;
    final d = (along % 1) * 2 * (w + h);
    final o = out * size.shortestSide;
    if (d < w) return Offset(d, -o);
    if (d < w + h) return Offset(w + o, d - w);
    if (d < 2 * w + h) return Offset(w - (d - w - h), h + o);
    return Offset(-o, h - (d - 2 * w - h));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final recipe = geometry.recipe;
    if (recipe.flareIndex < 0) return;
    final side = size.shortestSide;
    final t = motion?.time ?? 0;
    final band = recipe.ex ? 3 : recipe.flareIndex ~/ 3;
    final rank = recipe.ex ? 1.0 : (recipe.flareIndex % 3 + 1) / 3;
    final color = recipe.ex
        ? kFlareExColors.first
        : kFlareCardColors[recipe.flareIndex].frame;
    // The halo stays white like foil so it never reads as a coloured
    // border; only the particles carry a hint of the rank's colour.
    final bright = Color.lerp(color, Colors.white, .6)!;

    if (recipe.ex && layers.contains(EditionLayer.art)) {
      // Polychrome: the art's own light and shade, recoloured by bands of
      // rainbow that drift with time and the light.
      final light = motion?.light ?? const Offset(.35, .3);
      final shift = (light.dx + light.dy) * side * .35 + t * side * .08;
      canvas.save();
      canvas.clipPath(geometry.inner);
      _paint
        ..blendMode = BlendMode.color
        ..color = Colors.white.withValues(alpha: editionPolychromeAlpha)
        ..shader = ui.Gradient.linear(
            Offset(shift, 0),
            Offset(shift + side * .9, side * .55),
            editionPolychrome,
            [
              for (var i = 0; i < editionPolychrome.length; i++)
                i / (editionPolychrome.length - 1)
            ],
            TileMode.mirror);
      canvas.drawRect(geometry.innerRect, _paint);
      _paint
        ..blendMode = BlendMode.srcOver
        ..shader = null;
      canvas.restore();
    }

    if (!layers.contains(EditionLayer.aura)) return;
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * editionHaloWidth;
    if (recipe.ex) {
      _paint.shader = SweepGradient(
              colors: [...kFlareExColors, kFlareExColors.first],
              transform: GradientRotation(t * .9))
          .createShader(Offset.zero & size);
    }
    for (var i = 0; i < 4; i++) {
      _paint.color = Colors.white.withValues(
          alpha: const [.32, .16, .07, .03][i] * (.45 + rank * .55));
      canvas.drawPath(geometry.at(-side * editionHaloWidth * (i + .5)), _paint);
    }
    _paint
      ..shader = null
      ..style = PaintingStyle.fill;

    for (var i = 0; i < geometry.sparks.length; i++) {
      final s = geometry.sparks[i];
      final f = (t / s.speed + s.phase) % 1;
      final dot = side * s.size;
      final Offset at;
      var alpha = 1.0;
      switch (band) {
        case 0:
          // Up the sides, fading in and out.
          final right = s.along > .5;
          at = Offset(right ? size.width + s.out * side : -s.out * side,
              size.height * (1 - f));
          alpha = math.sin(f * math.pi);
        case 1:
          at = _edge(size, s.along + t / (s.speed * 6), s.out);
          alpha = .9;
        default:
          at = _edge(size, s.along, s.out);
          alpha = math.sin(f * math.pi);
      }
      if (alpha <= .02) continue;
      _paint.color = (recipe.ex
              ? Color.lerp(
                  kFlareExColors[i % kFlareExColors.length], Colors.white, .3)!
              : bright)
          .withValues(alpha: alpha);
      if (band < 2) {
        canvas.drawCircle(at, dot, _paint);
      } else {
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(alpha * math.pi / 4);
        canvas.scale(dot * 2.4 * alpha * (recipe.ex ? 1.3 : 1));
        canvas.drawPath(_star, _paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(EditionFlarePainter old) =>
      old.geometry != geometry || old.motion != motion;
}
