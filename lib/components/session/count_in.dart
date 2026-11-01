/// Name: CountIn
/// Parent: SessionPage
/// Description: The 3, 2, 1 before a session starts, over the whole screen:
/// a Volt ring that drains as the seconds run out around the number, each
/// beat landing with a pop and a tap, then GO. Tapping anywhere calls it off.
library;

import 'dart:math' as math;

import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _beats = 3;

/// Counts in over everything; true once it reaches GO, false if called off.
Future<bool> showCountIn(BuildContext context) async =>
    await Navigator.of(context, rootNavigator: true).push<bool>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: FloorPop.eighth,
        reverseTransitionDuration: FloorPop.eighth,
        pageBuilder: (_, __, ___) => const _CountIn(),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    ) ??
    false;

class _CountIn extends StatefulWidget {
  const _CountIn();

  @override
  State<_CountIn> createState() => _CountInState();
}

class _CountInState extends State<_CountIn>
    with SingleTickerProviderStateMixin {
  // The whole count, then a beat of GO.
  late final _t = AnimationController(
      vsync: this, duration: const Duration(seconds: _beats + 1))
    ..addListener(_tick)
    ..forward().whenComplete(() {
      if (mounted) Navigator.of(context).pop(true);
    });
  int _shown = _beats;

  @override
  void initState() {
    super.initState();
    HapticFeedback.selectionClick();
  }

  void _tick() {
    final left = _beats - (_t.value * (_beats + 1)).floor();
    if (left == _shown) return;
    left > 0 ? HapticFeedback.selectionClick() : HapticFeedback.heavyImpact();
    setState(() => _shown = left);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final size =
        math.min(MediaQuery.sizeOf(context).shortestSide * 0.72, 320.0);
    return Semantics(
      liveRegion: true,
      label: _shown > 0 ? 'Starting in $_shown' : 'Go',
      button: true,
      hint: 'Tap to cancel',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(false),
        child: ColoredBox(
          color: pop.ink.withValues(alpha: 0.94),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox.square(
                dimension: size,
                child: AnimatedBuilder(
                  animation: _t,
                  builder: (context, _) {
                    final secs = _t.value * (_beats + 1);
                    // Drains smoothly over the count; full again for GO.
                    final left = _shown > 0 ? 1 - secs / _beats : 1.0;
                    // Each beat pops in from a little larger.
                    final beat = secs - secs.floor();
                    final scale = 1 + 0.25 * math.pow(1 - beat, 4);
                    return CustomPaint(
                      painter: _Ring(left, track: pop.riser),
                      child: Center(
                        child: Transform.scale(
                          scale: scale.toDouble(),
                          child: Text(_shown > 0 ? '$_shown' : 'GO',
                              style: FloorPop.readout(
                                  _shown > 0 ? size * 0.5 : size * 0.3,
                                  color: FloorPop.volt)),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
              Text('Tap to cancel',
                  style: TextStyle(color: pop.haze, fontSize: 14)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.left, {required this.track});
  // 1 full to 0 empty.
  final double left;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track);
    if (left <= 0) return;
    canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * left,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = FloorPop.volt);
  }

  @override
  bool shouldRepaint(_Ring old) => old.left != left || old.track != track;
}
