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
///
/// The cabinet palette is coarser: DDR colours 4ths, 8ths and 16ths only, and
/// paints every other quantisation — 12ths, 24ths, 32nds and finer — green.
/// [arcadeMode] reproduces that, so the preview reads the way the cabinet does.
class QuantColors {
  static const Color quarter = Color(0xFFF23838); // 4th  - red
  static const Color eighth = Color(0xFF3B8DF2); // 8th  - blue
  static const Color twelfth = Color(0xFFB24BF2); // 12th - purple
  static const Color sixteenth = Color(0xFFF2D53B); // 16th - yellow
  static const Color twentyfourth = Color(0xFFF23B9E); // 24th - pink
  static const Color thirtysecond = Color(0xFFF28A3B); // 32nd - orange
  static const Color other = Color(0xFF43C24A); // finer - green

  /// When true, only the colours the cabinet distinguishes survive; the rest
  /// collapse to green. Global because both noteskins and the minimap colour
  /// notes through [forBeat] alone, and it flips for the whole preview at once.
  static bool arcadeMode = false;

  static Color forBeat(double beat) {
    final frac = beat - beat.floorToDouble();
    bool near(double v) => (frac - v).abs() < 0.012 || (frac - v).abs() > 0.988;
    if (near(0.0)) return quarter;
    if (near(0.5)) return eighth;
    if (!arcadeMode && (near(1 / 3) || near(2 / 3))) return twelfth;
    if (near(0.25) || near(0.75)) return sixteenth;
    if (!arcadeMode) {
      if (near(1 / 6) || near(5 / 6)) return twentyfourth;
      if (near(0.125) || near(0.375) || near(0.625) || near(0.875)) {
        return thirtysecond;
      }
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

  /// The impact flash left behind by a note arriving at the receptor, centred
  /// on the line at (x,y). [progress] runs 0..1 across the flash's lifetime.
  ///
  /// DDR grows the flash over the FIRST HALF, then holds that size and fades it
  /// out over the second half — it never expands while fading. The arrow itself
  /// is not scaled on impact (it is simply gone by then); the flash starting
  /// under-sized where the arrow was is what reads as the note compressing into
  /// the line.
  void paintNoteFlash(Canvas canvas, double x, double y, double size,
      NoteDir dir, double progress);
}

/// Flash size as a multiple of the arrow. It peaks slightly larger than the
/// note so it blooms past the receptor and reads as an impact rather than a
/// tint. DDR's own is bigger (~1.2x growing to ~1.5x), but the receptor sits
/// close to the top of the field here, so a burst that size runs into the
/// status bar — these are pulled in to fit.
const double noteFlashStartScale = 0.95;

/// Largest the flash ever gets, as a multiple of the arrow size. The painter
/// leaves room above the receptor for this so the flash draws uncut.
const double noteFlashPeakScale = 1.15;

/// How long the receptor's recoil lasts, in seconds, and how far it contracts.
/// DDR's own is 75% over 60ms; pushed a little deeper and longer here so the
/// recoil still registers on a phone-sized field.
const double receptorRecoilSeconds = 0.09;
const double receptorRecoilScale = 0.62;

/// Receptor size multiplier [progress] through a recoil, as a multiple of the
/// normal receptor size. Starts contracted and eases back out to 1.0 — the
/// snap is on arrival, the visible motion is the recovery.
double receptorRecoilCurve(double progress) {
  final p = progress.clamp(0.0, 1.0);
  // Ease-out: most of the spring-back happens early, so it reads as a recoil
  // rather than a slow grow.
  final eased = 1 - (1 - p) * (1 - p);
  return receptorRecoilScale + (1 - receptorRecoilScale) * eased;
}

/// Shared shape of the DDR impact flash, so every skin grows and fades in step.
/// Returns the (scale, alpha) for a flash [progress] through its lifetime,
/// where scale is a multiple of the arrow size.
(double scale, double alpha) noteFlashCurve(double progress) {
  final p = progress.clamp(0.0, 1.0);
  // Grow to the peak over the first half; hold that size and fade over the
  // second. It never expands while fading — that hold is the DDR look.
  final scale = p < 0.5
      ? noteFlashStartScale +
          (noteFlashPeakScale - noteFlashStartScale) * 2 * p
      : noteFlashPeakScale;
  final alpha = p < 0.5 ? 1.0 : 1.0 - (p - 0.5) * 2;
  return (scale, alpha);
}

/// The default, self-contained look: crisp vector arrows with a quantisation
/// tint, gradient freeze bodies, glowing shock bars, and beat-pulsing
/// receptors. No external assets.
class VectorNoteskin implements Noteskin {
  const VectorNoteskin();

  static const Color _holdColor = Color(0xFF39C46B);
  static const Color _rollColor = Color(0xFFF2A03B);

  // Arrow paths keyed by size. A handful of sizes are live at once (notes,
  // receptors, shock arrows); rebuilding the Path per glyph per frame was pure
  // allocation churn.
  static final Map<double, Path> _pathCache = {};

  Path _arrowPath(double s) {
    if (_pathCache.length > 8) _pathCache.clear();
    return _pathCache.putIfAbsent(s, () {
      final half = s / 2;
      // A chevron-style arrow pointing left (rotated per lane). Slightly
      // chunkier than a plain triangle so it reads as a DDR arrow, not a play
      // button.
      return Path()
        ..moveTo(-half, 0)
        ..lineTo(-half * 0.15, -half * 0.95)
        ..lineTo(-half * 0.15, -half * 0.42)
        ..lineTo(half, -half * 0.42)
        ..lineTo(half, half * 0.42)
        ..lineTo(-half * 0.15, half * 0.42)
        ..lineTo(-half * 0.15, half * 0.95)
        ..close();
    });
  }

  // --- rasterised tap/tail glyphs -----------------------------------------
  //
  // The full vector arrow costs a blurred shadow (a GPU blur!), two gradient
  // shaders and two strokes PER NOTE PER FRAME — by far the painter's biggest
  // line item at stream densities. Instead each (colour, tap/tail) glyph is
  // drawn once at a fixed reference size into a texture via toImageSync, and
  // every note becomes a single rotated image blit. The texture is rendered at
  // the device pixel ratio and sampled with mipmapped (medium) filtering, so
  // drawing it at any note size — including mid-pinch zoom — stays crisp
  // without ever regenerating the cache. Only 7 quant colours + 2 tail colours
  // exist, so the whole cache is 9 small textures.
  static const double _glyphBaseSize = 96;
  static const double _glyphPadFrac = 0.14; // room for the baked shadow blur
  static final Map<int, ui.Image> _glyphCache = {};
  static double _glyphCacheDpr = -1;
  static final Paint _glyphPaint = Paint()
    ..filterQuality = FilterQuality.medium;

  ui.Image _glyphImage(Color color, {required bool tail}) {
    final dpr =
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 2.0;
    if (dpr != _glyphCacheDpr) {
      _glyphCache.clear();
      _glyphCacheDpr = dpr;
    }
    final key = (color.toARGB32() << 1) | (tail ? 1 : 0);
    final cached = _glyphCache[key];
    if (cached != null) return cached;
    const pad = _glyphBaseSize * _glyphPadFrac;
    const span = _glyphBaseSize + pad * 2;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(dpr);
    canvas.translate(span / 2, span / 2);
    _drawArrowGlyph(canvas, _glyphBaseSize, color, tail: tail);
    final pic = rec.endRecording();
    final img = pic.toImageSync((span * dpr).ceil(), (span * dpr).ceil());
    pic.dispose();
    _glyphCache[key] = img;
    return img;
  }

  // The original vector arrow, centred on the origin pointing left — now only
  // executed when baking a glyph texture, not per note.
  void _drawArrowGlyph(Canvas canvas, double size, Color color,
      {required bool tail}) {
    final path = _arrowPath(size);

    // Soft drop shadow for depth.
    canvas.drawPath(
      path.shift(Offset(0, tail ? 1.2 : 1.5)),
      Paint()
        ..color = Colors.black.withValues(alpha: tail ? 0.30 : 0.35)
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
        ..color = Colors.black.withValues(alpha: tail ? 0.50 : 0.55),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * (tail ? 0.025 : 0.03)
        ..color = Colors.white.withValues(alpha: tail ? 0.22 : 0.35),
    );
  }

  // Stamp a cached glyph texture centred on the (already translated/rotated)
  // origin so the glyph body spans [size]; the baked-in shadow padding scales
  // with it.
  void _stampGlyph(Canvas canvas, ui.Image img, double size) {
    final half = size * (0.5 + _glyphPadFrac);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTRB(-half, -half, half, half),
      _glyphPaint,
    );
  }

  @override
  void paintArrow(Canvas canvas, double x, double y, double size, NoteDir dir,
      double beat) {
    final img = _glyphImage(QuantColors.forBeat(beat), tail: false);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    _stampGlyph(canvas, img, size);
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
    final img = _glyphImage(isRoll ? _rollColor : _holdColor, tail: true);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    _stampGlyph(canvas, img, size);
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

  @override
  void paintNoteFlash(Canvas canvas, double x, double y, double size,
      NoteDir dir, double progress) {
    final (scale, alpha) = noteFlashCurve(progress);
    if (alpha <= 0) return;
    final s = size * scale;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    // A soft additive bloom in the arrow's shape — DDR's flash is light thrown
    // off the receptor, not an opaque arrow stamped over the lane, so it lifts
    // what's underneath rather than hiding it. The vector stand-in for the
    // sprite burst, needing no external art.
    canvas.drawPath(
      _arrowPath(s),
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Colors.white.withValues(alpha: alpha * 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.22),
    );
    canvas.drawPath(
      _arrowPath(s * 0.82),
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Colors.white.withValues(alpha: alpha * 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.10),
    );
    canvas.restore();
  }

  static Color _lighten(Color c, double amt) =>
      Color.lerp(c, Colors.white, amt)!;
  static Color _darken(Color c, double amt) => Color.lerp(c, Colors.black, amt)!;
}

/// Sprite-backed noteskin using real DDR World arrow art from assets/noteskin/
/// (grey `note.png` rotated + tinted per quantisation for taps; direction-
/// oriented `hold-{left,down,up,right}-{body,tail}.png` for freezes — see
/// docs/noteskin.md). The grey note is tinted per note quantisation so the
/// authentic arrow shape still reads its rhythm at a glance. Mines, shock arrows
/// and receptors fall back to the vector skin, which already looks good for
/// those.
///
/// [tryLoad] returns null when the sprites aren't bundled (fresh clone / lite
/// build) so the caller uses [VectorNoteskin] everywhere instead.
class SpriteNoteskin implements Noteskin {
  SpriteNoteskin._(
    this._note,
    this._holdBodies,
  );

  final ui.Image _note;
  // Per-direction freeze body sprites, keyed by NoteDir.index. Unlike the note
  // glyph (one down-facing arrow rotated per lane), the DDR World freeze body art
  // is authored already oriented for each of L/D/U/R, so we pick the matching
  // sprite and draw it upright rather than rotating a single one. The tail
  // end-cap reuses the tinted note sprite instead.
  final List<ui.Image> _holdBodies;

  // Vector skin handles the elements we didn't extract sprites for.
  static const VectorNoteskin _vector = VectorNoteskin();

  // Loaded once per app run. Decoding the PNGs is async, so without memoising
  // every chart preview would open on the vector fallback for a frame or two
  // and visibly swap skins. After the first resolve, [resolved]/[resolvedSkin]
  // answer synchronously and previews start on the right skin immediately.
  static Future<Noteskin?>? _loadFuture;
  static Noteskin? _loadedSkin;
  static bool _resolved = false;

  /// Whether [tryLoad] has completed (either outcome) this app run.
  static bool get resolved => _resolved;

  /// The completed load's result: the sprite skin, or null when the sprites
  /// aren't bundled. Only meaningful once [resolved] is true.
  static Noteskin? get resolvedSkin => _loadedSkin;

  static Future<Noteskin?> tryLoad() => _loadFuture ??= _doLoad();

  static Future<Noteskin?> _doLoad() async {
    try {
      final note = await _load('assets/noteskin/note.png');
      // NoteDir order: left, down, up, right (see enum NoteDir).
      const dirNames = ['left', 'down', 'up', 'right'];
      final bodies = await Future.wait(
          dirNames.map((d) => _load('assets/noteskin/hold-$d-body.png')));
      _loadedSkin = SpriteNoteskin._(note, bodies);
    } catch (_) {
      _loadedSkin = null; // sprites absent -> vector fallback
    }
    _resolved = true;
    return _loadedSkin;
  }

  static Future<ui.Image> _load(String asset) async {
    final data = await rootBundle.load(asset);
    final codec =
        await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static final Paint _plainPaint = Paint();

  // Tint paints cached per colour: ColorFilter + Paint allocation per note per
  // frame is measurable at stream density, and only a handful of tints exist
  // (7 quant colours, hold/roll tails, receptor greys). Medium filter quality
  // (bilinear + mipmaps) instead of high (bicubic): visually identical at
  // note sizes, notably cheaper per blit.
  static final Map<int, Paint> _tintPaints = {};

  static Paint _tintPaint(Color color) {
    if (_tintPaints.length > 96) _tintPaints.clear();
    return _tintPaints.putIfAbsent(
      color.toARGB32(),
      () => Paint()
        ..colorFilter = ColorFilter.mode(color, BlendMode.modulate)
        ..filterQuality = FilterQuality.medium,
    );
  }

  void _drawImage(Canvas canvas, ui.Image img, Rect dst, {Paint? paint}) {
    final src = Rect.fromLTWH(
        0, 0, img.width.toDouble(), img.height.toDouble());
    canvas.drawImageRect(img, src, dst, paint ?? _plainPaint);
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
    _drawImage(canvas, _note, dst, paint: _tintPaint(color));
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
    final body = _holdBodies[dir.index];
    final bodyRect = Rect.fromLTRB(x - w / 2, yHead, x + w / 2, yTail);
    canvas.save();
    canvas.clipRect(bodyRect);
    final tileH = w * body.height / body.width;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (isRoll) {
      paint.colorFilter = const ColorFilter.mode(
          Color(0xFFF2A03B), BlendMode.modulate);
    }
    for (double ty = yHead; ty < yTail; ty += tileH) {
      _drawImage(canvas, body, Rect.fromLTWH(x - w / 2, ty, w, tileH),
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
    // End-cap: the ordinary note sprite (keeps its texture/shading), tinted to
    // the tail colour. No hold-body texture.
    final tailColor = isRoll
      ? const Color(0xFFF2A03B)
      : const Color(0xFF39C46B);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    final dst = Rect.fromCenter(center: Offset.zero, width: size, height: size);
    _drawImage(canvas, _note, dst, paint: _tintPaint(tailColor));
    canvas.restore();
  }

  @override
  void paintMine(Canvas c, double x, double y, double s) =>
      _vector.paintMine(c, x, y, s);

  @override
  void paintNoteFlash(Canvas canvas, double x, double y, double size,
      NoteDir dir, double progress) {
    final (scale, alpha) = noteFlashCurve(progress);
    if (alpha <= 0) return;
    // The real arrow art blown out to white, so the burst keeps the sprite
    // skin's silhouette instead of dropping to the vector chevron.
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(rotationForDir(dir));
    final dst = Rect.fromCenter(
        center: Offset.zero, width: size * scale, height: size * scale);
    // Additive so the burst reads as light off the receptor rather than an
    // opaque white arrow covering the lane.
    _drawImage(canvas, _note, dst,
        paint: Paint()
          ..blendMode = BlendMode.plus
          ..colorFilter =
              const ColorFilter.mode(Colors.white, BlendMode.srcIn)
          ..color = Colors.white.withValues(alpha: alpha * 0.45)
          ..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

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
    // The glow is quantised to 1/64 steps so the pulse reuses a bounded set of
    // cached tint paints instead of minting a ColorFilter per receptor per
    // frame (the step is far below what the eye can pick out of the pulse).
    final v = ((0.30 + 0.25 * glow).clamp(0.0, 1.0) * 64).round() / 64;
    _drawImage(canvas, _note, dst,
        paint: _tintPaint(Color.from(alpha: 1, red: v, green: v, blue: v)));
    canvas.restore();
  }
}
