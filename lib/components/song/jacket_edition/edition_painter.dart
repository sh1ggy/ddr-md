/// Name: EditionPainter
/// Parent: JacketEdition
/// Description: Two owned static display lists and one bounded light pass.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:ddr_md/grades.dart' show kFlareCardColors, kFlareExColors;
import 'package:ddr_md/models/settings_model.dart';
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
    if (recipe.flareIndex >= 0) {
      final metric = outer.computeMetrics().first;
      final n = compact ? editionCompactFlameSamples : editionFlameSamples;
      final ends = [
        for (var i = 0; i < n; i++)
          metric.getTangentForOffset(metric.length * i / n)!
      ];
      // The outline starts on the top edge, after the top left corner.
      final top = (size.width / 2 - ends.first.position.dx) / metric.length;
      edge = List.unmodifiable([
        for (var i = 0; i < n; i++)
          (
            at: ends[i].position,
            out: Offset(ends[i].vector.dy, -ends[i].vector.dx),
            top: ((i / n - top + .5) % 1 - .5).abs(),
          )
      ]);
    } else {
      edge = const [];
    }
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
  late final List<EditionEdge> edge;

  /// The flare gauge's track round the card, made on first use.
  late final ui.PathMetric gauge =
      at(-size.shortestSide * editionGaugeOffset).computeMetrics().first;

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
        final c =
            Offset(size.width / 2 + (i - 4.5) * gap, size.height - width / 2);
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

/// A point on the card's edge, its outward normal, and how far round the
/// edge it is from the top's middle (0 to .5).
typedef EditionEdge = ({Offset at, Offset out, double top});

/// The flare's aura, outside the art: flames in the rank's colour licking
/// off the frame, white at the root. They rise higher and spread further
/// round the card up the ranks, from the top edge at I to the whole card at
/// IX; EX burns rainbow. Development can show the flare gauge instead.
/// Unblurred; without [motion] it holds its first frame.
class EditionFlarePainter extends CustomPainter {
  EditionFlarePainter(this.geometry,
      [this.motion, this.layers = editionAllLayers])
      : super(repaint: motion);
  final EditionGeometry geometry;
  final EditionMotion? motion;
  // EX's polychrome belongs to the art; the flames to the aura.
  final Set<EditionLayer> layers;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final recipe = geometry.recipe;
    if (recipe.flareIndex < 0) return;
    final side = size.shortestSide;
    final t = motion?.time ?? 0;

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
    final level = recipe.ex ? 1.0 : (recipe.flareIndex + 1) / 9;
    if (Settings.getInt(Settings.jacketFlareGaugeKey) == 1) {
      _gauge(canvas, size, t, level);
    } else {
      _flames(canvas, size, t, level);
    }
  }

  void _flames(Canvas canvas, Size size, double t, double level) {
    final recipe = geometry.recipe;
    final side = size.shortestSide;
    final edge = geometry.edge;
    final reach = .25 + .75 * level;
    final height = side *
        (editionFlameHeight[0] +
            (editionFlameHeight[1] - editionFlameHeight[0]) * level) *
        (geometry.compact ? .6 : 1);
    _paint
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus;
    if (recipe.ex) {
      final shift = t * side * .3;
      _paint.shader = ui.Gradient.linear(
          Offset(shift, 0),
          Offset(shift + side, side),
          kFlareExColors,
          [
            for (var i = 0; i < kFlareExColors.length; i++)
              i / (kFlareExColors.length - 1)
          ],
          TileMode.mirror);
    }
    final tips = List.filled(edge.length, Offset.zero);
    // Outer tongues, then hotter and whiter ones inside them.
    for (final (scale, alpha, white) in const [
      (1.0, .38, 0.0),
      (.66, .55, .35),
      (.36, .85, .8),
    ]) {
      for (var i = 0; i < edge.length; i++) {
        final e = edge[i];
        final a = i / edge.length;
        // Upward edges burn hardest; the fire spreads down from the top.
        final up = math.max(0.0, .35 - e.out.dy * .8 - e.out.dx.abs() * .05);
        final lit = ((reach * .62 - e.top) * 8).clamp(0.0, 1.0);
        final flicker = math.pow(
                    .5 +
                        .5 *
                            math.sin(a * editionFlameTongues +
                                t * 7 +
                                math.sin(a * 13 + t * 3) * 2),
                    editionFlameSharpness) *
                .75 +
            .25 * (.5 + .5 * math.sin(a * 97 - t * 11));
        final h =
            height * scale * lit * (.35 + .65 * flicker) * (.55 + .45 * up);
        // Tongues on the sides lean upward as they rise.
        tips[i] = e.at +
            e.out * h -
            Offset(0, h * editionFlameLean * (1 - e.out.dy.abs()));
      }
      // Curved through the tips: each a control point, the midpoints between
      // them on the outline.
      final path = Path()..fillType = PathFillType.evenOdd;
      var from = (tips.last + tips.first) / 2;
      path.moveTo(from.dx, from.dy);
      for (var i = 0; i < tips.length; i++) {
        final to = (tips[i] + tips[(i + 1) % tips.length]) / 2;
        path.quadraticBezierTo(tips[i].dx, tips[i].dy, to.dx, to.dy);
      }
      path
        ..close()
        ..addPath(geometry.outer, Offset.zero);
      _paint.color = recipe.ex
          ? Colors.white.withValues(alpha: alpha)
          : Color.lerp(kFlareCardColors[recipe.flareIndex].frame, Colors.white,
                  white)!
              .withValues(alpha: alpha);
      canvas.drawPath(path, _paint);
    }
    _paint
      ..shader = null
      ..blendMode = BlendMode.srcOver;
  }

  // A track round the card with a tick each ninth, lit clockwise from the
  // top's middle up to the rank; EX's is a turning rainbow.
  void _gauge(Canvas canvas, Size size, double t, double level) {
    final recipe = geometry.recipe;
    final side = size.shortestSide;
    final metric = geometry.gauge;
    final length = metric.length;
    final start = size.width / 2 - metric.getTangentForOffset(0)!.position.dx;
    final width = side * editionGaugeWidth;
    final pulse = .75 + .25 * math.sin(t * 3);
    Path along(double from, double to) => to <= length
        ? metric.extractPath(from, to)
        : (metric.extractPath(from, length)
          ..addPath(metric.extractPath(0, to - length), Offset.zero));
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = Colors.white.withValues(alpha: .08);
    canvas.drawPath(along(0, length), _paint);
    final lit = along(start, start + length * level);
    final color = recipe.ex
        ? Colors.white
        : Color.lerp(
            kFlareCardColors[recipe.flareIndex].frame, Colors.white, .15)!;
    if (recipe.ex) {
      _paint.shader = SweepGradient(
              colors: [...kFlareExColors, kFlareExColors.first],
              transform: GradientRotation(-t * 1.2))
          .createShader(Offset.zero & size);
    }
    _paint
      ..strokeWidth = width * 3.2
      ..color = color.withValues(alpha: .12 * pulse);
    canvas.drawPath(lit, _paint);
    _paint
      ..strokeWidth = width
      ..color = color.withValues(alpha: .95);
    canvas.drawPath(lit, _paint);
    _paint
      ..shader = null
      ..strokeWidth = math.max(1, side * .008);
    for (var k = 0; k < 9; k++) {
      final tick =
          metric.getTangentForOffset((start + length * k / 9) % length)!;
      final out = Offset(tick.vector.dy, -tick.vector.dx) * width * .7;
      _paint.color = k < (level * 9).round()
          ? const Color(0xE60E0B1F)
          : Colors.white.withValues(alpha: .25);
      canvas.drawLine(tick.position - out, tick.position + out, _paint);
    }
    _paint.style = PaintingStyle.fill;
    if (!recipe.ex) {
      final head =
          metric.getTangentForOffset((start + length * level) % length)!;
      _paint.color = Colors.white.withValues(alpha: pulse);
      canvas.drawCircle(head.position, width * .75, _paint);
    }
  }

  @override
  bool shouldRepaint(EditionFlarePainter old) =>
      old.geometry != geometry || old.motion != motion;
}
