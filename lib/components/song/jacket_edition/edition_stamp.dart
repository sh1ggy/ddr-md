/// Name: EditionStamp
/// Parent: JacketEdition
/// Description: Native icons as die-cut stickers stuck on the card: a white
/// rim following the icon's edge, a shadow cast away from the light and a
/// gloss of their own, apart from the card's finish.
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'edition_catalog.dart';
import 'edition_motion.dart';

class EditionStamp extends StatefulWidget {
  const EditionStamp(
      {super.key,
      required this.asset,
      required this.height,
      required this.label,
      this.motion});
  final String asset;
  final double height;
  final String label;
  // The card's light; without it the sticker holds a still one.
  final EditionMotion? motion;
  @override
  State<EditionStamp> createState() => _EditionStampState();
}

class _EditionStampState extends State<EditionStamp> {
  ImageStream? _stream;
  ImageInfo? _image;
  bool _failed = false;
  late final _listener = ImageStreamListener(_loaded, onError: (_, __) {
    if (mounted) setState(() => _failed = true);
  });

  void _loaded(ImageInfo image, bool synchronous) {
    final old = _image;
    if (mounted) {
      setState(() {
        _image = image;
        _failed = false;
      });
    } else {
      image.dispose();
    }
    old?.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(EditionStamp old) {
    super.didUpdateWidget(old);
    if (old.asset != widget.asset) _resolve();
  }

  void _resolve() {
    final next = AssetImage(widget.asset)
        .resolve(createLocalImageConfiguration(context));
    if (next.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _image?.dispose();
    _image = null;
    _failed = false;
    _stream = next;
    next.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Text(widget.label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900));
    }
    final image = _image?.image;
    return Semantics(
        image: true,
        label: widget.label,
        child: SizedBox(
            height: widget.height + editionStampRim * 2,
            width: image == null
                ? widget.height
                : widget.height * image.width / image.height +
                    editionStampRim * 2,
            child: image == null
                ? null
                : CustomPaint(painter: _StampPainter(image, widget.motion))));
  }
}

// Where the light sits, from the card's motion or held still.
Offset _lightOf(EditionMotion? motion) =>
    motion?.light ?? const Offset(.35, .3);

// A sticker's shadow falls away from the light, a little below.
Offset editionStickerShadow(EditionMotion? motion) {
  final l = _lightOf(motion);
  return Offset((.5 - l.dx) * 2.4, 1 + (.5 - l.dy) * 1.6);
}

// Soft-edged gloss bands crossing [bounds] with the light, as clips; the
// caller fills each with white at its alpha.
void paintEditionGloss(Canvas canvas, Rect bounds, EditionMotion? motion,
    void Function(double alpha) fill) {
  final l = _lightOf(motion);
  final at = bounds.left + bounds.width * (-.4 + (l.dx + l.dy) * .9);
  final slant = bounds.height * .6;
  for (final (half, alpha) in [(.2, .06), (.1, .1), (.035, .18)]) {
    final w = bounds.height * half * 2;
    canvas.save();
    canvas.clipPath(Path()
      ..moveTo(at - w + slant, bounds.top)
      ..lineTo(at + w + slant, bounds.top)
      ..lineTo(at + w - slant, bounds.bottom)
      ..lineTo(at - w - slant, bounds.bottom)
      ..close());
    fill(alpha);
    canvas.restore();
  }
}

class _StampPainter extends CustomPainter {
  _StampPainter(this.image, this.motion) : super(repaint: motion);
  final ui.Image image;
  final EditionMotion? motion;
  static final _shadow = Paint()
    ..filterQuality = FilterQuality.low
    ..colorFilter = const ColorFilter.mode(Color(0x73000000), BlendMode.srcIn);
  static final _rim = Paint()
    ..filterQuality = FilterQuality.low
    ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn);
  static final _ink = Paint()..filterQuality = FilterQuality.low;
  final _gloss = Paint()..filterQuality = FilterQuality.low;
  // Eight fixed silhouette copies make the rim and the shadow; no mask,
  // blur, texture or saveLayer.
  static const _offsets = [
    Offset(-1, 0),
    Offset(1, 0),
    Offset(0, -1),
    Offset(0, 1),
    Offset(-.707, -.707),
    Offset(.707, -.707),
    Offset(-.707, .707),
    Offset(.707, .707)
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final source =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final target = (Offset.zero & size).deflate(editionStampRim);
    final shadow = target.shift(editionStickerShadow(motion));
    for (final offset in _offsets) {
      canvas.drawImageRect(
          image, source, shadow.shift(offset * editionStampRim), _shadow);
    }
    for (final offset in _offsets) {
      canvas.drawImageRect(
          image, source, target.shift(offset * editionStampRim), _rim);
    }
    canvas.drawImageRect(image, source, target, _ink);
    // Gloss only where the sticker is: its silhouette, clipped to each band.
    paintEditionGloss(canvas, Offset.zero & size, motion, (alpha) {
      _gloss.colorFilter = ColorFilter.mode(
          Colors.white.withValues(alpha: alpha), BlendMode.srcIn);
      for (final offset in _offsets) {
        canvas.drawImageRect(
            image, source, target.shift(offset * editionStampRim), _gloss);
      }
    });
  }

  @override
  bool shouldRepaint(_StampPainter old) =>
      old.image != image || old.motion != motion;
}

/// A label sticker: [child] on a dark rounded backing with a white die-cut
/// edge, its shadow and gloss following the light like the icon stickers.
class EditionLabelSticker extends StatelessWidget {
  const EditionLabelSticker({super.key, required this.child, this.motion});
  final Widget child;
  final EditionMotion? motion;
  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _LabelPainter(motion, back: true),
      foregroundPainter: _LabelPainter(motion, back: false),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 4, 7, 4), child: child));
}

class _LabelPainter extends CustomPainter {
  _LabelPainter(this.motion, {required this.back}) : super(repaint: motion);
  final EditionMotion? motion;
  final bool back;
  final _paint = Paint();
  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(size.height * .32));
    if (back) {
      canvas.drawRRect(shape.shift(editionStickerShadow(motion)),
          _paint..color = const Color(0x73000000));
      canvas.drawRRect(shape, _paint..color = Colors.white);
      canvas.drawRRect(shape.deflate(editionLabelRim),
          _paint..color = const Color(0xF216122C));
      return;
    }
    canvas.save();
    canvas.clipRRect(shape);
    paintEditionGloss(canvas, Offset.zero & size, motion, (alpha) {
      canvas.drawRect(Offset.zero & size,
          _paint..color = Colors.white.withValues(alpha: alpha * .6));
    });
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LabelPainter old) =>
      old.motion != motion || old.back != back;
}
