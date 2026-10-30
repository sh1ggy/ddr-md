/// Name: GeneratedJacket
/// Parent: SongArtwork
/// Description: Deterministic Floor Pop cover art for songs without a jacket.
/// Each song keeps its colours and geometry across views and app launches.
library;

import 'dart:math' as math;

import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

class GeneratedJacket extends StatelessWidget {
  const GeneratedJacket({super.key, required this.songName, this.title});

  final String songName;
  final String? title;

  // String.hashCode isn't a persistent identity. FNV gives the same cover on
  // every platform, without writing generated assets into the content bundle.
  static int seedFor(String name) {
    var hash = 0x811c9dc5;
    for (final unit in name.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  @override
  Widget build(BuildContext context) {
    final seed = seedFor(songName);
    final name = (title ?? songName).trim();
    final words =
        name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final initials = words.isEmpty
        ? '♪'
        : words.take(2).map((s) => s.characters.first).join().toUpperCase();
    return LayoutBuilder(builder: (context, constraints) {
      final side = constraints.biggest.shortestSide;
      return CustomPaint(
        painter: _CoverPainter(seed),
        child: Padding(
          padding: EdgeInsets.all(side * 0.1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Transform(
                    transform: FloorPop.titleLean,
                    alignment: Alignment.center,
                    child: FittedBox(
                      child: Text(initials,
                          maxLines: 1,
                          style:
                              FloorPop.display(side * 0.4, color: Colors.white)
                                  .copyWith(inherit: false)),
                    ),
                  ),
                ),
              ),
              if (side >= 80)
                Text(name.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        inherit: false,
                        fontFamily: kTextFont,
                        fontSize: side * 0.075,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
            ],
          ),
        ),
      );
    });
  }
}

class _CoverPainter extends CustomPainter {
  const _CoverPainter(this.seed);
  final int seed;

  static const _palettes = [
    (Color(0xFF3548C8), FloorPop.grape),
    (Color(0xFF84265E), FloorPop.coral),
    (Color(0xFF006B78), Color(0xFF60E7D5)),
    (Color(0xFF535D19), FloorPop.volt),
    (Color(0xFF874119), FloorPop.sun),
    (Color(0xFF5423AA), FloorPop.padBlue),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final (base, accent) = _palettes[seed % _palettes.length];
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [base, Color.lerp(base, FloorPop.night.ink, 0.8)!],
          ).createShader(rect));
    canvas.save();
    canvas.clipRect(rect);
    final unit = size.shortestSide;
    final center = Offset(
        size.width * (0.65 + ((seed >> 8) % 20) / 100), size.height * 0.3);
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(
          center,
          unit * (0.18 + i * 0.14),
          Paint()
            ..color = accent.withValues(alpha: 0.5 - i * 0.07)
            ..style = PaintingStyle.stroke
            ..strokeWidth = unit * 0.035);
    }
    canvas.translate(size.width * 0.82, size.height * 0.72);
    canvas.rotate(-math.pi / 4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: unit * 0.65, height: unit * 0.65),
            Radius.circular(unit * 0.07)),
        Paint()..color = accent.withValues(alpha: 0.22));
    canvas.restore();
    // A dark lower wash keeps even a long title readable over the geometry.
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xA00E0B1F)],
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(_CoverPainter old) => old.seed != seed;
}
