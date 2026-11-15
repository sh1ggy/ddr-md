/// Name: EditionCutShader
/// Parent: JacketEdition, CompactJacketEdition
/// Description: The tier's foil cut over the art: one fragment shader, blended
/// as overlay, shifted with the light and faded away from it.
library;

import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'edition_catalog.dart';
import 'edition_model.dart';
import 'edition_motion.dart';
import 'edition_painter.dart';

class EditionCutShader {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// Loads the shader once; cards drawn before it lands have no cut.
  static Future<void> load() =>
      _loading ??= ui.FragmentProgram.fromAsset('shaders/edition_cut.frag')
          .then((p) => _program = p, onError: (_) {});

  static bool get ready => _program != null;

  /// How strongly [recipe] shows its cut, 0 for none: stronger up the
  /// grades, nothing on print.
  static double power(EditionRecipe recipe, {bool compact = false}) {
    if (recipe.cut == EditionCut.neutral) return 0;
    return editionCutPower[recipe.finish.index] *
        recipe.strength *
        (compact ? editionCompactFinishStrength : 1);
  }

  /// A shader for one card, its uniforms set by [update].
  static ui.FragmentShader? create() => _program?.fragmentShader();

  static ui.FragmentShader update(ui.FragmentShader shader,
      EditionRecipe recipe, Size size, Offset light, double power) {
    return shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, light.dx)
      ..setFloat(3, light.dy)
      ..setFloat(4, recipe.cut.index.toDouble())
      ..setFloat(5, power);
  }
}

/// The cut over the art painted before it in the same layer, at the
/// light's resting place without [motion]. [alone] draws the facets
/// themselves instead, for a layer with no art beneath it.
class EditionCutPainter extends CustomPainter {
  EditionCutPainter(this.geometry, this.shader, this.power,
      {this.motion, this.alone = false})
      : super(repaint: motion);
  final EditionGeometry geometry;
  final ui.FragmentShader shader;
  final double power;
  final EditionMotion? motion;
  final bool alone;
  @override
  void paint(Canvas canvas, Size size) {
    EditionCutShader.update(shader, geometry.recipe, size,
        motion?.light ?? EditionMotion.rest, power);
    canvas.save();
    canvas.clipPath(geometry.inner);
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = alone ? BlendMode.srcOver : BlendMode.overlay
          ..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(EditionCutPainter old) =>
      old.geometry != geometry ||
      old.shader != shader ||
      old.power != power ||
      old.motion != motion ||
      old.alone != alone;
}
