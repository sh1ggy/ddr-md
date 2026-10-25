/// Name: SongRadarChart
/// Parent: SongDetails
/// Description: The chosen chart's groove radar, compact beside the title
/// and full screen on tap.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

const _labels = ['Stream', 'Voltage', 'Air', 'Freeze', 'Chaos'];
const _icons = [
  Icons.waves,
  Icons.bolt,
  Icons.flight,
  Icons.ac_unit,
  Icons.shuffle,
];

// Axis i points up and turns clockwise.
Offset _axis(int i) {
  final angle = -math.pi / 2 + i * 2 * math.pi / 5;
  return Offset(math.cos(angle), math.sin(angle));
}

class SongRadarChart extends StatelessWidget {
  const SongRadarChart(
      {super.key, required this.radar, this.expanded = false, this.color});

  final Radar? radar;
  final bool expanded;
  // The chosen chart's difficulty colour.
  final Color? color;

  // The radar grows out of its spot to fill the screen, keeping its colour,
  // a beat long (instant under reduced motion).
  void _openRadar(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      transitionDuration: still ? Duration.zero : FloorPop.beat,
      reverseTransitionDuration: still ? Duration.zero : FloorPop.eighth,
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.6, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: FloorPop.step)),
          child: child,
        ),
      ),
      pageBuilder: (context, animation, secondaryAnimation) => Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(context),
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.9,
                    height: MediaQuery.sizeOf(context).height * 0.65,
                    child: SongRadarChart(
                        radar: radar, expanded: true, color: color),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Close Groove Radar',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final radar = this.radar;
    if (radar == null) return const SizedBox.shrink();
    final pop = FloorPop.of(context);
    final tint = color ?? FloorPop.volt;
    final values = [
      radar.stream,
      radar.voltage,
      radar.air,
      radar.freeze,
      radar.chaos,
    ];
    final still = MediaQuery.of(context).disableAnimations;

    // A new difficulty morphs the shape over from the last one.
    final chart = TweenAnimationBuilder<List<double>>(
      tween: _ValuesTween(end: values),
      duration: still ? Duration.zero : FloorPop.beat,
      curve: FloorPop.step,
      builder: (context, shown, _) => LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final half = size.shortestSide / 2;
          // Room outside the frame for the axis marks.
          final radius = half * (expanded ? 0.5 : 0.74);
          final center = size.center(Offset.zero);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _RadarPainter(
                    values: shown,
                    radius: radius,
                    tint: tint,
                    frame: expanded ? Colors.white10 : pop.riser,
                    line: expanded ? Colors.white24 : pop.line,
                    ink: expanded ? Colors.black : pop.ink,
                  ),
                ),
              ),
              for (var i = 0; i < 5; i++)
                expanded
                    ? _ExpandedMark(
                        at: center + _axis(i) * (radius + 10),
                        towards: _axis(i),
                        index: i,
                        value: values[i],
                        tint: tint)
                    : _CompactMark(
                        at: center + _axis(i) * (radius + 7),
                        index: i,
                        value: values[i],
                        color: values[i] >= 100 ? tint : pop.haze),
            ],
          );
        },
      ),
    );

    final labelled = Semantics(
      label: 'Groove Radar: Stream ${radar.stream}, Voltage ${radar.voltage}, '
          'Air ${radar.air}, Freeze ${radar.freeze}, Chaos ${radar.chaos}',
      child: expanded ? chart : SizedBox(width: 88, height: 88, child: chart),
    );
    if (expanded) return IgnorePointer(child: labelled);
    return Semantics(
      button: true,
      hint: 'Expand Groove Radar',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openRadar(context),
        child: labelled,
      ),
    );
  }
}

class _ValuesTween extends Tween<List<double>> {
  _ValuesTween({required super.end});

  @override
  List<double> lerp(double t) => [
        for (var i = 0; i < end!.length; i++)
          lerpDouble(begin?[i] ?? 0, end![i], t)!,
      ];
}

class _CompactMark extends StatelessWidget {
  const _CompactMark(
      {required this.at,
      required this.index,
      required this.value,
      required this.color});

  final Offset at;
  final int index;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Positioned(
        left: at.dx - 6,
        top: at.dy - 6,
        child: Tooltip(
          message: '${_labels[index]}: ${value.round()}',
          child: Icon(_icons[index], size: 12, color: color),
        ),
      );
}

class _ExpandedMark extends StatelessWidget {
  const _ExpandedMark(
      {required this.at,
      required this.towards,
      required this.index,
      required this.value,
      required this.tint});

  final Offset at;
  // The axis direction: the label grows away from the radar along it.
  final Offset towards;
  final int index;
  final double value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    const width = 120.0, height = 52.0;
    return Positioned(
      left: at.dx - width / 2 + towards.dx * width / 2,
      top: at.dy - height / 2 + towards.dy * height / 2,
      width: width,
      height: height,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icons[index], size: 13, color: Colors.white60),
              const SizedBox(width: 4),
              Text(_labels[index].toUpperCase(),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                      color: Colors.white60)),
            ],
          ),
          const SizedBox(height: 2),
          Text('${value.round()}',
              style: FloorPop.readout(30,
                  color: value >= 100 ? tint : Colors.white)),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.values,
    required this.radius,
    required this.tint,
    required this.frame,
    required this.line,
    required this.ink,
  });

  final List<double> values;
  final double radius;
  final Color tint, frame, line, ink;

  Path _ring(Offset center, double r) => Path()
    ..addPolygon([for (var i = 0; i < 5; i++) center + _axis(i) * r], true);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // The frame is 100 on every axis. A value past it bursts through, and
    // the whole radar shrinks so the burst still fits.
    final unit = radius / values.fold<double>(100, math.max);
    final r100 = unit * 100;

    canvas.drawPath(_ring(center, r100), Paint()..color = frame);
    final grid = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final step in const [25.0, 50.0, 75.0]) {
      canvas.drawPath(_ring(center, unit * step), grid);
    }
    for (var i = 0; i < 5; i++) {
      canvas.drawLine(center, center + _axis(i) * r100, grid);
    }
    canvas.drawPath(
        _ring(center, r100),
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round);

    final points = [
      for (var i = 0; i < 5; i++)
        center + _axis(i) * unit * values[i].clamp(0, double.infinity),
    ];
    final shape = Path()..addPolygon(points, true);
    // Brighter toward the rim, so a big value glows.
    canvas.drawPath(
        shape,
        Paint()
          ..shader = RadialGradient(
            colors: [tint.withValues(alpha: 0.12), tint.withValues(alpha: 0.6)],
          ).createShader(Rect.fromCircle(center: center, radius: r100)));
    canvas.drawPath(
        shape,
        Paint()
          ..color = tint.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.min(radius / 10, 6)
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius / 14));
    canvas.drawPath(
        shape,
        Paint()
          ..color = tint
          ..style = PaintingStyle.stroke
          ..strokeWidth = (radius / 18).clamp(1.5, 2.5)
          ..strokeJoin = StrokeJoin.round);

    final dot = (radius / 36).clamp(1.0, 2.5);
    for (final point in points) {
      canvas.drawCircle(point, dot + 0.8, Paint()..color = ink);
      canvas.drawCircle(point, dot, Paint()..color = tint);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.radius != radius ||
      old.tint != tint ||
      old.frame != frame ||
      old.line != line ||
      old.ink != ink ||
      !_sameValues(old.values, values);

  static bool _sameValues(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
