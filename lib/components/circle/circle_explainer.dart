/// Name: CircleExplainer
/// Parent: CirclePage
/// Description: How circles work, drawn: two round dancers and their phones.
/// You scan their QR and you cheer for them; they scan yours and they cheer
/// for you; both ways round, you're friends. Shown once when a circle is
/// started and from the Circle tab's info button; the last panel also fills
/// the tab while nobody's in a circle yet.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

/// The three steps, each a drawing, a heading and a line.
const _steps = [
  (
    CircleScene.youScan,
    'You scan their QR',
    "Now you cheer for them: you'll see when they're on the pad."
  ),
  (
    CircleScene.theyScan,
    'They scan yours',
    'Now they cheer for you too.',
  ),
  (
    CircleScene.friends,
    "You're friends",
    'Both ways round, you cheer each other on.',
  ),
];

/// Which step of scanning each other a [CircleArt] draws.
enum CircleScene { youScan, theyScan, friends }

Future<void> showCircleExplainer(BuildContext context) => showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ExplainerSheet(),
    );

class _ExplainerSheet extends StatefulWidget {
  const _ExplainerSheet();

  @override
  State<_ExplainerSheet> createState() => _ExplainerSheetState();
}

class _ExplainerSheetState extends State<_ExplainerSheet> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final last = _page == _steps.length - 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 300,
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final (scene, title, line) in _steps)
                  Column(children: [
                    Expanded(child: CircleArt(scene)),
                    const SizedBox(height: 12),
                    Text(title,
                        style: FloorPop.display(20,
                            color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 6),
                    Text(line,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: pop.haze, height: 1.4)),
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PageDots(_steps.length, index: _page),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: VoltButton(
              onPressed: () => last
                  ? Navigator.pop(context)
                  : _pages.nextPage(
                      duration: FloorPop.beat, curve: FloorPop.settle),
              child: Text(last ? 'Got it' : 'Next',
                  style: const TextStyle(
                      fontFamily: kTextFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Two dancers, you in Pad Blue on the left and them in Coral on the
/// right, bobbing on the beat through one [scene].
class CircleArt extends StatefulWidget {
  const CircleArt(this.scene, {super.key});
  final CircleScene scene;

  @override
  State<CircleArt> createState() => _CircleArtState();
}

class _CircleArtState extends State<CircleArt>
    with SingleTickerProviderStateMixin {
  late final _beat =
      AnimationController(vsync: this, duration: FloorPop.beat * 2)..repeat();

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: switch (widget.scene) {
          CircleScene.youScan => "You scanning a friend's QR code",
          CircleScene.theyScan => 'A friend scanning your QR code',
          CircleScene.friends => 'You and a friend, friends',
        },
        child: AspectRatio(
          aspectRatio: 1.7,
          child: AnimatedBuilder(
            animation: _beat,
            builder: (context, _) => CustomPaint(
                painter: _ArtPainter(
                    widget.scene, _beat.value, FloorPop.of(context).stage)),
          ),
        ),
      );
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.scene, this.t, this.ground);

  final CircleScene scene;
  // 0–1 through two beats.
  final double t;
  final Color ground;

  static const _ink = FloorPop.onVolt;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 340×200 stage, scaled to fit.
    final s = math.min(size.width / 340, size.height / 200);
    canvas.translate((size.width - 340 * s) / 2, (size.height - 200 * s) / 2);
    canvas.scale(s);

    // The floor they stand on.
    canvas.drawOval(
        const Rect.fromLTWH(30, 168, 280, 22), Paint()..color = ground);

    final bob = math.sin(t * 2 * math.pi);
    final friends = scene == CircleScene.friends;
    final you = Offset(friends ? 128 : 90, 120 + bob * 3);
    final them = Offset(friends ? 212 : 250, 120 - bob * 3);

    if (friends) {
      _arrows(canvas, you, them);
      _heart(canvas, const Offset(170, 52), 1 + 0.08 * bob);
      _sparkle(canvas, const Offset(120, 38), 6 + bob * 1.5);
      _sparkle(canvas, const Offset(224, 44), 5 - bob * 1.5);
    } else {
      final youScan = scene == CircleScene.youScan;
      final scanner = youScan ? you : them;
      final shower = youScan ? them : you;
      final towards = youScan ? 1.0 : -1.0;
      final scanPhone = scanner + Offset(42 * towards, -10);
      final qrPhone = shower + Offset(-42 * towards, -10);
      _beam(canvas, scanPhone, qrPhone, bob);
      _phone(canvas, qrPhone, qr: true);
      _phone(canvas, scanPhone, qr: false);
      _sparkle(canvas, qrPhone + const Offset(0, -38), 5 + bob * 1.5);
    }
    _dancer(canvas, you, FloorPop.padBlue,
        happy: friends || scene == CircleScene.youScan);
    _dancer(canvas, them, FloorPop.coral,
        happy: friends || scene == CircleScene.theyScan);
  }

  /// A round dancer: body, eyes (closed and smiling when [happy]), blush.
  void _dancer(Canvas canvas, Offset at, Color color, {required bool happy}) {
    canvas.drawOval(Rect.fromCenter(center: at, width: 76, height: 70),
        Paint()..color = color);
    // Feet, tapping in time.
    final feet = Paint()..color = color;
    canvas.drawOval(
        Rect.fromCenter(
            center: at + const Offset(-16, 36), width: 20, height: 10),
        feet);
    canvas.drawOval(
        Rect.fromCenter(
            center: at + const Offset(16, 36), width: 20, height: 10),
        feet);
    final eye = Paint()
      ..color = _ink
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = happy ? PaintingStyle.stroke : PaintingStyle.fill;
    for (final dx in [-12.0, 12.0]) {
      final c = at + Offset(dx, -6);
      if (happy) {
        canvas.drawArc(Rect.fromCenter(center: c, width: 10, height: 8),
            math.pi, math.pi, false, eye);
      } else {
        canvas.drawOval(Rect.fromCenter(center: c, width: 7, height: 9), eye);
      }
    }
    final blush = Paint()..color = const Color(0x66FF7EB0);
    canvas.drawOval(
        Rect.fromCenter(
            center: at + const Offset(-21, 5), width: 11, height: 6),
        blush);
    canvas.drawOval(
        Rect.fromCenter(center: at + const Offset(21, 5), width: 11, height: 6),
        blush);
    canvas.drawArc(
        Rect.fromCenter(center: at + const Offset(0, 3), width: 12, height: 9),
        0.2,
        math.pi - 0.4,
        false,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round);
  }

  /// A phone held up: its screen a QR code, or a viewfinder when scanning.
  void _phone(Canvas canvas, Offset at, {required bool qr}) {
    final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: at, width: 34, height: 54),
        const Radius.circular(7));
    canvas.drawRRect(body, Paint()..color = const Color(0xFF231E42));
    final screen = Rect.fromCenter(center: at, width: 26, height: 42);
    canvas.drawRRect(RRect.fromRectAndRadius(screen, const Radius.circular(4)),
        Paint()..color = Colors.white);
    final ink = Paint()..color = _ink;
    if (qr) {
      // A few finder squares and modules: reads as a QR at this size.
      const cell = 3.4;
      final origin = at - const Offset(cell * 3.5, cell * 3.5);
      const pattern = [
        '111 111',
        '101 101',
        '111 111',
        '  1 1  ',
        '111 1 1',
        '101  11',
        '1111 1 ',
      ];
      for (var y = 0; y < pattern.length; y++) {
        for (var x = 0; x < pattern[y].length; x++) {
          if (pattern[y][x] == '1') {
            canvas.drawRect(
                Rect.fromLTWH(
                    origin.dx + x * cell, origin.dy + y * cell, cell, cell),
                ink);
          }
        }
      }
    } else {
      final corner = Paint()
        ..color = FloorPop.voltRiser
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final r = Rect.fromCenter(center: at, width: 16, height: 16);
      for (final (c, dx, dy) in [
        (r.topLeft, 1.0, 1.0),
        (r.topRight, -1.0, 1.0),
        (r.bottomLeft, 1.0, -1.0),
        (r.bottomRight, -1.0, -1.0),
      ]) {
        canvas.drawLine(c, c + Offset(5 * dx, 0), corner);
        canvas.drawLine(c, c + Offset(0, 5 * dy), corner);
      }
    }
  }

  /// The scanning phone's light reaching the QR, pulsing.
  void _beam(Canvas canvas, Offset from, Offset to, double bob) {
    const spread = 24.0;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy - spread)
      ..lineTo(to.dx, to.dy + spread)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..color = FloorPop.volt.withValues(alpha: 0.22 + 0.08 * bob.abs()));
  }

  /// Two curved arrows, one each way: cheering both ways round.
  void _arrows(Canvas canvas, Offset you, Offset them) {
    final paint = Paint()
      ..color = FloorPop.volt
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    void arrow(Offset a, Offset b, double lift) {
      final mid = Offset((a.dx + b.dx) / 2, a.dy + lift);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
      canvas.drawPath(path, paint);
      final dir = (b - mid);
      final angle = math.atan2(dir.dy, dir.dx);
      for (final turn in [2.5, -2.5]) {
        canvas.drawLine(
            b,
            b + Offset(math.cos(angle + turn), math.sin(angle + turn)) * 9,
            paint);
      }
    }

    arrow(you + const Offset(14, -46), them + const Offset(-14, -46), -34);
    arrow(them + const Offset(-14, 46), you + const Offset(14, 46), 26);
  }

  void _heart(Canvas canvas, Offset at, double scale) {
    final w = 30 * scale, h = 27 * scale;
    final path = Path()
      ..moveTo(at.dx, at.dy + h * 0.35)
      ..cubicTo(at.dx - w * 0.9, at.dy - h * 0.35, at.dx - w * 0.25,
          at.dy - h * 0.85, at.dx, at.dy - h * 0.3)
      ..cubicTo(at.dx + w * 0.25, at.dy - h * 0.85, at.dx + w * 0.9,
          at.dy - h * 0.35, at.dx, at.dy + h * 0.35)
      ..close();
    canvas.drawPath(path, Paint()..color = FloorPop.coral);
  }

  void _sparkle(Canvas canvas, Offset at, double r) {
    final path = Path()
      ..moveTo(at.dx, at.dy - r)
      ..quadraticBezierTo(at.dx, at.dy, at.dx + r, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + r)
      ..quadraticBezierTo(at.dx, at.dy, at.dx - r, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = FloorPop.sun);
  }

  @override
  bool shouldRepaint(_ArtPainter old) =>
      old.t != t || old.scene != scene || old.ground != ground;
}
