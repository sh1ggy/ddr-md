/// Name: Noteskin
/// Description: Draws step-chart notes (arrows, freeze/hold bodies, shock
/// arrows, mines) for the chart preview. Ships a fully vector-drawn default so
/// nothing copyrighted lives in the repo, but will prefer bitmap sprites
/// dropped into assets/noteskin/ (e.g. official DDR World arrow textures the
/// user supplies) when they are present — see [SpriteNoteskin.tryLoad].
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Column arrow direction, used to orient the glyph. dance-single is L D U R;
/// dance-double is that pattern twice.
enum NoteDir { left, down, up, right }

const List<NoteDir> kSingleDirs = [
  NoteDir.left,
  NoteDir.down,
  NoteDir.up,
  NoteDir.right,
];
const List<NoteDir> kDoubleDirs = [
  NoteDir.left, NoteDir.down, NoteDir.up, NoteDir.right, //
  NoteDir.left, NoteDir.down, NoteDir.up, NoteDir.right,
];

double rotationForDir(NoteDir dir) {
  switch (dir) {
    case NoteDir.left:
      return 0;
    case NoteDir.down:
      return -1.5707963; // -90°
    case NoteDir.up:
      return 1.5707963; // +90°
    case NoteDir.right:
      return 3.1415926; // 180°
  }
}

/// DDR/ITG quantisation colouring: an arrow is coloured by the fraction of a
/// beat it lands on. 4ths red, 8ths blue, 12ths purple, 16ths yellow, 24ths
/// pink, 32nds orange, everything finer green — the standard reading palette.
class QuantColors {
  static const Color quarter = Color(0xFFF23838); // 4th  - red
  static const Color eighth = Color(0xFF3B8DF2); // 8th  - blue
  static const Color twelfth = Color(0xFFB24BF2); // 12th - purple
  static const Color sixteenth = Color(0xFFF2D53B); // 16th - yellow
  static const Color twentyfourth = Color(0xFFF23B9E); // 24th - pink
  static const Color thirtysecond = Color(0xFFF28A3B); // 32nd - orange
  static const Color other = Color(0xFF43C24A); // finer - green

  static Color forBeat(double beat) {
    final frac = beat - beat.floorToDouble();
    bool near(double v) => (frac - v).abs() < 0.012 || (frac - v).abs() > 0.988;
    if (near(0.0)) return quarter;
    if (near(0.5)) return eighth;
    if (near(1 / 3) || near(2 / 3)) return twelfth;
    if (near(0.25) || near(0.75)) return sixteenth;
    if (near(1 / 6) || near(5 / 6)) return twentyfourth;
    if (near(0.125) || near(0.375) || near(0.625) || near(0.875)) {
      return thirtysecond;
    }
    return other;
  }
}

/// Rendering contract used by the chart painter. A single instance is created
/// per repaint pass (cheap) and asked to draw each element at a canvas point.
abstract class Noteskin {
  /// A tap/step arrow centred at (x,y), oriented by [dir], coloured by [beat].
  void paintArrow(Canvas canvas, double x, double y, double size, NoteDir dir,
      double beat);

  /// A freeze/hold (or roll) body running from the head at [yHead] down to the
  /// tail at [yTail] in one lane.
  void paintHoldBody(Canvas canvas, double x, double yHead, double yTail,
      double size, NoteDir dir, bool isRoll);

  /// The end-cap marker for a freeze/hold tail at [y]. DDR shows a matching
  /// end note to indicate where the sustain ends.
  void paintHoldTail(
      Canvas canvas, double x, double y, double size, NoteDir dir, bool isRoll);

  /// A single mine centred at (x,y).
  void paintMine(Canvas canvas, double x, double y, double size);

  /// A shock arrow: a light-blue arrow in every lit lane linked by electricity
  /// across the row at [y]. Each entry of [lanes] is a lane centre-x paired with
  /// its arrow direction. In DDR a shock is a full row of arrows to avoid.
  void paintShock(
      Canvas canvas, List<(double x, NoteDir dir)> lanes, double y, double size);

  /// A receptor ring for one lane, centred at (x,y). [glow] 0..1 pulses on the
  /// beat.
  void paintReceptor(
      Canvas canvas, double x, double y, double size, NoteDir dir, double glow);
}

/// The default, self-contained look: crisp vector arrows with a quantisation
/// tint, gradient freeze bodies, glowing shock bars, and beat-pulsing
/// receptors. No external assets.
class VectorNoteskin implements Noteskin {
  const VectorNoteskin();

  static const Color _holdColor = Color(0xFF39C46B);
  static const Color _rollColor = Color(0xFFF2A03B);

  Path _arrowPath(double s) {
    final half = s / 2;
    // A chevron-style arrow pointing left (rotated per lane). Slightly chunkier
    // than a plain triangle so it reads as a DDR arrow, not a play button.
    return Path()
      ..moveTo(-half, 0)
      ..lineTo(-half * 0.15, -half * 0.95)
      ..lineTo(-half * 0.15, -half * 0.42)
      ..lineTo(half, -half * 0.42)
      ..lineTo(half, half * 0.42)
      ..lineTo(-half * 0.15, half * 0.42)
      ..lineTo(-half * 0.15, half * 0.95)
      ..close();
  }

  @override
  void paintArrow(Canvas canvas, double x, double y, double size, NoteDir dir,
      double beat) {
    final color = QuantColors.forBeat(beat);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    final path = _arrowPath(size);

    // Soft drop shadow for depth.
    canvas.drawPath(
      path.shift(const Offset(0, 1.5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Body with a top-lit vertical gradient.
    final rect = Rect.fromCircle(center: Offset.zero, radius: size / 2);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [_lighten(color, 0.28), color, _darken(color, 0.22)],
          [0.0, 0.5, 1.0],
        ),
    );
    // Crisp outline + inner highlight.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.05
        ..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.03
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.restore();
  }

  @override
  void paintHoldBody(Canvas canvas, double x, double yHead, double yTail,
      double size, NoteDir dir, bool isRoll) {
    final w = size;
    final base = isRoll ? _rollColor : _holdColor;
    final rect = Rect.fromLTRB(x - w / 2, yHead, x + w / 2, yTail);
    if (rect.height <= 0) return;

    // Tube with a centre highlight so it reads as a rounded freeze body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w / 2)),
      Paint()
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          [_darken(base, 0.25), _lighten(base, 0.35), _darken(base, 0.25)],
          [0.0, 0.5, 1.0],
        ),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.black.withValues(alpha: 0.4),
    );
  }

  @override
  void paintHoldTail(
      Canvas canvas, double x, double y, double size, NoteDir dir, bool isRoll) {
    final color = isRoll ? _rollColor : _holdColor;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    final path = _arrowPath(size);
    final rect = Rect.fromCircle(center: Offset.zero, radius: size / 2);
    canvas.drawPath(
      path.shift(const Offset(0, 1.2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [_lighten(color, 0.28), color, _darken(color, 0.22)],
          [0.0, 0.5, 1.0],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.05
        ..color = Colors.black.withValues(alpha: 0.50),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.025
        ..color = Colors.white.withValues(alpha: 0.22),
    );
    canvas.restore();
  }

  @override
  void paintMine(Canvas canvas, double x, double y, double size) {
    final r = size * 0.44;
    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(x, y),
          r,
          [const Color(0xFF4A4A4A), const Color(0xFF161616)],
        ),
    );
    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.08
        ..color = const Color(0xFFE0413B),
    );
    // Spokes for the classic mine look.
    final spoke = Paint()
      ..strokeWidth = size * 0.05
      ..color = const Color(0xFFE0413B);
    for (int i = 0; i < 4; i++) {
      final a = i * 0.7853981; // 45°
      final dx = r * 0.9 * math.cos(a), dy = r * 0.9 * math.sin(a);
      canvas.drawLine(Offset(x - dx, y - dy), Offset(x + dx, y + dy), spoke);
    }
  }

  @override
  void paintShock(
      Canvas canvas, List<(double x, NoteDir dir)> lanes, double y, double size) {
    if (lanes.isEmpty) return;
    // A DDR shock arrow is an ARROW shape charged with electricity — an
    // electric-blue arrow with a bright glow, a white-hot rim, and a lightning
    // bolt crackling inside it, in every lit lane.
    const glow = Color(0xFF6FE0FF);
    for (final (x, dir) in lanes) {
      _paintShockArrow(canvas, x, y, size, dir, glow);
    }
  }

  void _paintShockArrow(
      Canvas canvas, double x, double y, double size, NoteDir dir, Color glow) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    final path = _arrowPath(size);

    // Electric glow bleeding out from the arrow.
    canvas.drawPath(
      path,
      Paint()
        ..color = glow.withValues(alpha: 0.75)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    // Dark-blue energy interior with a bright top-lit gradient.
    final rect = Rect.fromCircle(center: Offset.zero, radius: size / 2);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [glow, const Color(0xFF1C86B0), const Color(0xFF0B3852)],
          [0.0, 0.5, 1.0],
        ),
    );
    // Crackle: a small lightning bolt down the arrow's spine.
    canvas.save();
    canvas.clipPath(path);
    _paintCrackle(canvas, size, glow);
    canvas.restore();
    // Bright electric rim: glow outline then white-hot core edge.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.10
        ..color = glow,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.035
        ..color = Colors.white,
    );
    canvas.restore();
  }

  // A jagged bolt crackling horizontally across the arrow body (the arrow is
  // rotated to point left, so "along the spine" is the x-axis here).
  void _paintCrackle(Canvas canvas, double size, Color glow) {
    const jags = [0.0, 0.22, -0.14, 0.28, -0.08, 0.20, -0.24, 0.10, 0.0];
    final path = Path();
    final half = size / 2;
    for (int i = 0; i < jags.length; i++) {
      final t = i / (jags.length - 1);
      final px = -half + size * t;
      final py = jags[i] * size * 0.22;
      i == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.12
        ..strokeJoin = StrokeJoin.round
        ..color = glow.withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.045
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  void paintReceptor(Canvas canvas, double x, double y, double size,
      NoteDir dir, double glow) {
    final r = size * 0.56;
    // Outer ring, brighter on the beat.
    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.08
        ..color = Color.lerp(Colors.white24, Colors.white, glow)!,
    );
    // Faint direction chevron inside so empty receptors still read as arrows.
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    canvas.drawPath(
      _arrowPath(size * 0.62),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.045
        ..color = Colors.white.withValues(alpha: 0.10 + 0.25 * glow),
    );
    canvas.restore();
  }

  static Color _lighten(Color c, double amt) =>
      Color.lerp(c, Colors.white, amt)!;
  static Color _darken(Color c, double amt) => Color.lerp(c, Colors.black, amt)!;
}

/// Sprite-backed noteskin using real DDR World arrow art extracted into
/// assets/noteskin/ (grey `note.png`, `hold_body.png`, `hold_head.png` — see
/// DDR-BPM-prep/src/extract_noteskin.py and docs/noteskin.md). The grey note is
/// tinted per note quantisation so the authentic arrow shape still reads its
/// rhythm at a glance. Mines, shock arrows and receptors fall back to the
/// vector skin, which already looks good for those.
///
/// [tryLoad] returns null when the sprites aren't bundled (fresh clone / lite
/// build) so the caller uses [VectorNoteskin] everywhere instead.
class SpriteNoteskin implements Noteskin {
  SpriteNoteskin._(
    this._note,
    this._holdBody,
    this._holdTail,
  );

  final ui.Image _note;
  final ui.Image _holdBody;
  final ui.Image? _holdTail;

  // Vector skin handles the elements we didn't extract sprites for.
  static const VectorNoteskin _vector = VectorNoteskin();

  static Future<Noteskin?> tryLoad() async {
    try {
      final note = await _load('assets/noteskin/note.png');
      final body = await _load('assets/noteskin/hold_body.png');
      ui.Image? tail;
      try {
        tail = await _load('assets/noteskin/hold_tail.png');
      } catch (_) {
        tail = null;
      }
      return SpriteNoteskin._(note, body, tail);
    } catch (_) {
      return null; // sprites absent -> vector fallback
    }
  }

  static Future<ui.Image> _load(String asset) async {
    final data = await rootBundle.load(asset);
    final codec =
        await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  void _drawImage(Canvas canvas, ui.Image img, Rect dst, {Paint? paint}) {
    final src = Rect.fromLTWH(
        0, 0, img.width.toDouble(), img.height.toDouble());
    canvas.drawImageRect(img, src, dst, paint ?? Paint());
  }

  @override
  void paintArrow(Canvas canvas, double x, double y, double size, NoteDir dir,
      double beat) {
    final color = QuantColors.forBeat(beat);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    final dst = Rect.fromCenter(center: Offset.zero, width: size, height: size);
    // modulate: grey (~0.5) * tint keeps shading while colouring the arrow.
    _drawImage(canvas, _note, dst,
        paint: Paint()
          ..colorFilter = ColorFilter.mode(color, BlendMode.modulate)
          ..filterQuality = FilterQuality.high);
    canvas.restore();
  }

  @override
  void paintHoldBody(Canvas canvas, double x, double yHead, double yTail,
      double size, NoteDir dir, bool isRoll) {
    if (yTail <= yHead) return;
    // DDR freeze: a GREEN sustain body (constant colour regardless of the head's
    // quantisation), capped by the note arrow itself. Use full note width so the
    // freeze reads as the same thickness as the note itself.
    final w = size;
    final bodyRect = Rect.fromLTRB(x - w / 2, yHead, x + w / 2, yTail);
    canvas.save();
    canvas.clipRect(bodyRect);
    final tileH = w * _holdBody.height / _holdBody.width;
    final paint = Paint()..filterQuality = FilterQuality.high;
    if (isRoll) {
      paint.colorFilter = const ColorFilter.mode(
          Color(0xFFF2A03B), BlendMode.modulate);
    }
    for (double ty = yHead; ty < yTail; ty += tileH) {
      _drawImage(canvas, _holdBody, Rect.fromLTWH(x - w / 2, ty, w, tileH),
          paint: paint);
    }
    canvas.restore();
    // The freeze head is the note arrow itself; the painter draws it in the
    // tap pass, so nothing more is stamped here (avoids the mismatched
    // hold_head transition frame).
  }

  @override
  void paintHoldTail(
      Canvas canvas, double x, double y, double size, NoteDir dir, bool isRoll) {
    if (_holdTail != null) {
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotationForDir(dir));
      final dst =
          Rect.fromCenter(center: Offset.zero, width: size, height: size);
      final paint = Paint()..filterQuality = FilterQuality.high;
      if (isRoll) {
        paint.colorFilter = const ColorFilter.mode(
            Color(0xFFF2A03B), BlendMode.modulate);
      }
      _drawImage(canvas, _holdTail, dst, paint: paint);
      canvas.restore();
      return;
    }
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    final dst = Rect.fromCenter(center: Offset.zero, width: size, height: size);
    final layerRect = Rect.fromCenter(
      center: Offset.zero,
      width: size * 1.1,
      height: size * 1.1,
    );
    canvas.saveLayer(layerRect, Paint());
    final bodyPaint = Paint()..filterQuality = FilterQuality.high;
    if (isRoll) {
      bodyPaint.colorFilter = const ColorFilter.mode(
          Color(0xFFF2A03B), BlendMode.modulate);
    }
    _drawImage(canvas, _holdBody, dst, paint: bodyPaint);
    _drawImage(canvas, _note, dst,
        paint: Paint()
          ..blendMode = BlendMode.dstIn
          ..filterQuality = FilterQuality.high);
    canvas.restore();
    final tailColor = isRoll
      ? const Color(0xFFF2A03B)
      : const Color(0xFF39C46B);
    // Reintroduce just enough arrow shading to make the tail read as a note
    // end marker, but stay strictly inside the note sprite alpha so no tinted
    // background halo appears.
    _drawImage(canvas, _note, dst,
      paint: Paint()
        ..colorFilter = ColorFilter.mode(
          Color.lerp(tailColor, Colors.black, 0.12)!.withValues(alpha: 0.38),
          BlendMode.modulate)
        ..filterQuality = FilterQuality.high);
    canvas.restore();
  }

  @override
  void paintMine(Canvas c, double x, double y, double s) =>
      _vector.paintMine(c, x, y, s);

  @override
  void paintShock(Canvas canvas, List<(double x, NoteDir dir)> lanes, double y,
      double size) {
    if (lanes.isEmpty) return;
    final sorted = [...lanes]..sort((a, b) => a.$1.compareTo(b.$1));
    const glow = Color(0xFF79E7FF);
    final shockSize = size;
    final lightningY = y - shockSize * 0.18;

    if (sorted.length >= 2) {
      final crackle = Path();
      for (int i = 0; i < sorted.length; i++) {
        final x = sorted[i].$1;
        final dy = (i.isEven ? -1 : 1) * shockSize * 0.06;
        if (i == 0) {
          crackle.moveTo(x, lightningY + dy);
        } else {
          final midX = (sorted[i - 1].$1 + x) / 2;
          crackle
            ..lineTo(midX, lightningY - dy * 0.8)
            ..lineTo(x, lightningY + dy);
        }
      }
      canvas.drawPath(
        crackle,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = shockSize * 0.11
          ..color = glow.withValues(alpha: 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(
        crackle,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = shockSize * 0.028
          ..color = Colors.white.withValues(alpha: 0.56),
      );
    }

    for (final (x, dir) in sorted) {
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotationForDir(dir));
      final glowDst = Rect.fromCenter(
        center: Offset.zero,
        width: shockSize * 1.08,
        height: shockSize * 1.08,
      );
      _drawImage(canvas, _note, glowDst,
          paint: Paint()
            ..colorFilter = ColorFilter.mode(
                glow.withValues(alpha: 0.42), BlendMode.modulate)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
            ..filterQuality = FilterQuality.high);
      final dst = Rect.fromCenter(
          center: Offset.zero, width: shockSize, height: shockSize);
      _drawImage(canvas, _note, dst,
          paint: Paint()
            ..colorFilter = ColorFilter.mode(
                glow.withValues(alpha: 0.74), BlendMode.modulate)
            ..filterQuality = FilterQuality.high);
      canvas.restore();
    }
  }

  @override
  void paintReceptor(Canvas canvas, double x, double y, double size,
      NoteDir dir, double glow) {
    // Match the note: draw the SAME grey arrow sprite, dimmed, so the receptor
    // reads as the receptacle for that lane's arrow (not a mismatched ring).
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    final dst = Rect.fromCenter(center: Offset.zero, width: size, height: size);
    // Dim the grey arrow to a faint receptacle; brighten slightly on the beat
    // pulse. modulate by a grey scales all channels + alpha down uniformly.
    final v = (0.30 + 0.25 * glow).clamp(0.0, 1.0);
    _drawImage(canvas, _note, dst,
        paint: Paint()
          ..colorFilter = ColorFilter.mode(
              Color.from(alpha: 1, red: v, green: v, blue: v),
              BlendMode.modulate)
          ..filterQuality = FilterQuality.high);
    canvas.restore();
  }
}
