/// Name: EditionPainter
/// Parent: JacketEdition
/// Description: Two owned static display lists and one bounded light pass.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:ddr_md/grades.dart' show kFlareCardColors;
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
    outer = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(side * .065));
    inner = outer.deflate(width);
    glints = List.unmodifiable(List.generate(
        compact ? 0 : editionGlintCount,
        (i) => Offset(size.width * (.12 + (i * .173) % .77),
            size.height * (.15 + (i * .293) % .70))));
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
  late final RRect outer, inner;
  late final ui.Picture frame, motif;
  late final List<Offset> glints;

  void _recordFrame(Canvas canvas) {
    final palette = editionFramePalettes[recipe.frame]!;
    final rect = outer.outerRect;
    canvas.drawRRect(
        outer,
        Paint()
          ..shader = LinearGradient(
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
              ]).createShader(rect));
    final line = Paint()..style = PaintingStyle.stroke;
    // Raised bevel remains visible with motion disabled, especially PFC.
    for (final (inset, alpha) in [
      (width * .17, .75),
      (width * .38, .25),
      (width * .78, .65)
    ]) {
      canvas.drawRRect(
          outer.deflate(inset),
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
    // Difficulty owns corner geometry; no achievement seals or badges.
    final cut = side * (.023 + recipe.difficultyShape * .003);
    for (final corner in compact
        ? <Offset>[]
        : [
            Offset(width, width),
            Offset(size.width - width, width),
            Offset(width, size.height - width),
            Offset(size.width - width, size.height - width)
          ]) {
      canvas.drawCircle(corner, cut * .34, Paint()..color = palette[1]);
      canvas.drawCircle(corner, cut * .18, Paint()..color = palette[0]);
    }
    if (recipe.secret || recipe.ex) {
      // Thin inlay preserves the gold substrate under EX.
      canvas.drawRRect(
          outer.deflate(width * (recipe.secret ? .52 : .12)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width * .15
            ..shader = const SweepGradient(colors: editionSpectrum)
                .createShader(rect));
    }
  }

  void _recordMotif(Canvas canvas) {
    canvas.save();
    canvas.clipRRect(inner);
    final side = size.shortestSide;
    final finish = recipe.finish;
    final textured = finish.index >= EditionFinish.texturedHolo.index;
    final premium = recipe.secret || recipe.frame == EditionFrame.starlight;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.45, side / 1100);
    if (recipe.failed) {
      canvas.drawRect(
          inner.outerRect, Paint()..color = const Color(0x22000000));
    }
    if (finish != EditionFinish.print || premium) {
      final cut = editionCuts[recipe.cut]!;
      final count = math.min(
          compact ? editionCompactMotifLines : editionMaxMotifLines, cut.lines);
      paint.color =
          (recipe.secret ? const Color(0xFFFFD575) : Colors.white).withValues(
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
      paint.color =
          recipe.secret ? const Color(0x66FFE0A0) : const Color(0x44FFFFFF);
      for (var i = 0; i < (compact ? editionCompactGlints : 28); i++) {
        final p = Offset(size.width * (.08 + (i * .61803) % .84),
            size.height * (.08 + (i * .38197) % .84));
        final d = side * (recipe.frame == EditionFrame.starlight ? .005 : .003);
        canvas.drawLine(p - Offset(d, 0), p + Offset(d, 0), paint);
        canvas.drawLine(p - Offset(0, d), p + Offset(0, d), paint);
      }
    }
    // Complete static finish. This stays when motion is disabled.
    final strength = compact ? editionCompactFinishStrength : 1.0;
    final alpha = editionFinishAlpha[finish.index] * recipe.strength * strength;
    if (alpha > 0 || recipe.ex || recipe.secret) {
      canvas.drawRect(
          inner.outerRect,
          Paint()
            ..shader = LinearGradient(
                    colors: finish.index >= EditionFinish.holo.index ||
                            recipe.ex ||
                            recipe.secret
                        ? [
                            for (final color in editionSpectrum)
                              color.withValues(alpha: color.a * strength)
                          ]
                        : [
                            Colors.transparent,
                            Colors.white.withValues(alpha: alpha),
                            Colors.transparent
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)
                .createShader(inner.outerRect));
    }
    canvas.restore();
  }

  void dispose() {
    frame.dispose();
    motif.dispose();
  }
}

class EditionStaticPainter extends CustomPainter {
  EditionStaticPainter(this.geometry, {this.foreground = false});
  final EditionGeometry geometry;
  final bool foreground;
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawPicture(foreground ? geometry.motif : geometry.frame);
  @override
  bool shouldRepaint(EditionStaticPainter old) =>
      old.geometry != geometry || old.foreground != foreground;
}

class EditionLightPainter extends CustomPainter {
  EditionLightPainter(this.geometry, this.motion) : super(repaint: motion);
  final EditionGeometry geometry;
  final EditionMotion motion;
  final Paint _paint = Paint();
  @override
  void paint(Canvas canvas, Size size) {
    final recipe = geometry.recipe;
    final side = size.shortestSide;
    final at =
        Offset(motion.light.dx * size.width, motion.light.dy * size.height);
    final color = recipe.flareIndex >= 0 && recipe.flareIndex < 9
        ? kFlareCardColors[recipe.flareIndex].frame
        : Colors.white;
    final rect = geometry.outer.outerRect;
    canvas.save();
    canvas.clipRRect(geometry.outer);
    // Exactly one animated full-card gradient; no per-axis blend layers.
    final spectrum = recipe.ex || recipe.secret;
    _paint.shader = ui.Gradient.linear(
        at - Offset(side * .5, side * .18),
        at + Offset(side * .5, side * .18),
        spectrum
            ? editionSpectrum
            : [
                Colors.transparent,
                color.withValues(alpha: .08 + recipe.finish.index * .025),
                Colors.transparent
              ],
        spectrum ? const [0, .25, .5, .75, 1] : const [0, .5, 1]);
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
