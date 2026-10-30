/// Name: EditionStamp
/// Parent: JacketEdition
/// Description: Native icon with a narrow white rim following its alpha edge.
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'edition_catalog.dart';

class EditionStamp extends StatefulWidget {
  const EditionStamp(
      {super.key,
      required this.asset,
      required this.height,
      required this.label});
  final String asset;
  final double height;
  final String label;
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
                : CustomPaint(painter: _StampPainter(image))));
  }
}

class _StampPainter extends CustomPainter {
  _StampPainter(this.image);
  final ui.Image image;
  static final _rim = Paint()
    ..filterQuality = FilterQuality.low
    ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn);
  static final _ink = Paint()..filterQuality = FilterQuality.low;
  // Eight fixed silhouette copies; no mask, blur, texture or saveLayer.
  // The enclosing stamp RepaintBoundary retains this paint during card tilt.
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
    for (final offset in _offsets) {
      canvas.drawImageRect(
          image, source, target.shift(offset * editionStampRim), _rim);
    }
    canvas.drawImageRect(image, source, target, _ink);
  }

  @override
  bool shouldRepaint(_StampPainter old) => old.image != image;
}
