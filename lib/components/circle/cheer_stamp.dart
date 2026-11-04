/// Name: CheerStamp
/// Parent: CircleCreditCard, CheerSheet, CheerNotifications
/// Description: How a cheer looks: a tilted stamp in the cheer's own colour
/// and icon, with who gave it; one that's just arrived pops in. Also the
/// outlined action icon that marks cheering, and the confetti a sent cheer bursts into.
library;

import 'dart:math' as math;

import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

extension CheerLook on Cheer {
  Color get color => switch (this) {
        Cheer.letsGo => FloorPop.volt,
        Cheer.clean => FloorPop.padBlue,
        Cheer.stamina => FloorPop.coral,
        Cheer.soClose => FloorPop.grape,
        Cheer.restUp => const Color(0xFF3DDC84),
        Cheer.legend => FloorPop.sun,
      };

  /// Text on [color]: dark on the light ones.
  Color get ink => switch (this) {
        Cheer.clean || Cheer.stamina || Cheer.soClose => Colors.white,
        _ => FloorPop.onVolt,
      };

  IconData get icon => switch (this) {
        Cheer.letsGo => Icons.bolt,
        Cheer.clean => Icons.auto_awesome,
        Cheer.stamina => Icons.local_fire_department,
        Cheer.soClose => Icons.favorite,
        Cheer.restUp => Icons.bedtime,
        Cheer.legend => Icons.emoji_events,
      };

  /// A lean of its own, so a row of stamps looks slapped on.
  double get tilt => const [-0.07, 0.05, -0.04, 0.08, -0.06, 0.04][index];
}

/// A cheer as a stamp: [cheer] on its colour, leaning, with [name] (who
/// gave it) above when given. [pop] springs it in, for one just arrived.
class CheerStamp extends StatelessWidget {
  const CheerStamp(this.cheer,
      {super.key, this.name, this.large = false, this.pop = false});

  final Cheer cheer;
  final String? name;
  final bool large;
  final bool pop;

  @override
  Widget build(BuildContext context) {
    final stamp = Transform.rotate(
      angle: cheer.tilt,
      child: Container(
        padding: large
            ? const EdgeInsets.fromLTRB(14, 12, 16, 12)
            : const EdgeInsets.fromLTRB(8, 5, 10, 5),
        decoration: BoxDecoration(
          color: cheer.color,
          borderRadius: BorderRadius.circular(large ? 16 : 10),
          boxShadow: [
            BoxShadow(
                color: cheer.color.withValues(alpha: 0.35),
                blurRadius: large ? 16 : 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(cheer.icon, size: large ? 22 : 14, color: cheer.ink),
          SizedBox(width: large ? 8 : 5),
          Text(cheer.label,
              style: FloorPop.display(large ? 16 : 11, color: cheer.ink)),
        ]),
      ),
    );
    final body = name == null
        ? stamp
        : Column(mainAxisSize: MainAxisSize.min, children: [
            Text(name!,
                style: TextStyle(
                    color: FloorPop.of(context).haze,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            stamp,
          ]);
    if (!pop || MediaQuery.disableAnimationsOf(context)) return body;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      builder: (context, t, child) => Transform.scale(
          scale: 0.4 + 0.6 * t,
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child)),
      child: body,
    );
  }
}

/// Outlined applause, matching the app's other Material action icons.
class CheerIcon extends StatelessWidget {
  const CheerIcon({super.key, this.size = 20});
  final double size;
  @override
  Widget build(BuildContext context) =>
      Icon(Icons.celebration_outlined, size: size);
}

/// A player's avatar colour, from [key] (their id, else their name); never
/// Volt, which on the Circle tab means live.
Color avatarColour(String key) => const [
      FloorPop.coral,
      FloorPop.padBlue,
      FloorPop.sun,
      FloorPop.grape
    ][key.codeUnits.fold(0, (a, b) => a + b) % 4];

/// The letter on [colour]: white on the dark ones.
Color avatarInk(Color colour) =>
    colour == FloorPop.padBlue || colour == FloorPop.grape
        ? Colors.white
        : FloorPop.onVolt;

/// A note from a player: a bold pill above their avatar. Every note occupies
/// the same slot, so changing the cheer cannot move this or nearby avatars.
class CheerNote extends StatelessWidget {
  const CheerNote(this.cheer,
      {super.key, required this.name, this.personId, this.onTap});
  final Cheer cheer;
  final String name;
  final String? personId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final colour = avatarColour(personId ?? name);
    return Semantics(
      button: onTap != null,
      label:
          '$name: ${cheer.label}${onTap == null ? '' : '. Tap to change your cheer'}',
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
              width: 120,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: double.infinity,
                      height: 34,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                          color: cheer.color,
                          borderRadius: BorderRadius.circular(14)),
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(cheer.icon, color: cheer.ink, size: 15),
                            const SizedBox(width: 4),
                            Text(cheer.label,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: cheer.ink))
                          ]))),
                  const SizedBox(height: 6),
                  CircleAvatar(
                      radius: 19,
                      backgroundColor: colour,
                      child: Text(name.isEmpty ? '?' : name.substring(0, 1),
                          style:
                              FloorPop.display(15, color: avatarInk(colour)))),
                  const SizedBox(height: 4),
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: pop.haze,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ))),
    );
  }
}

/// Confetti bursting from [at] (global) in [colour] and the stage's own,
/// once, over everything; it removes itself.
void burstConfetti(BuildContext context, Offset at, Color colour) {
  if (MediaQuery.disableAnimationsOf(context)) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
      builder: (_) =>
          _Confetti(at: at, colour: colour, onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _Confetti extends StatefulWidget {
  const _Confetti(
      {required this.at, required this.colour, required this.onDone});
  final Offset at;
  final Color colour;
  final VoidCallback onDone;

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward().whenComplete(widget.onDone);

  // Each piece: direction, speed, spin, colour.
  late final _pieces = () {
    final random = math.Random();
    final colours = [
      widget.colour,
      FloorPop.volt,
      FloorPop.coral,
      FloorPop.sun,
      FloorPop.padBlue,
    ];
    return [
      for (var i = 0; i < 36; i++)
        (
          angle: -math.pi / 2 + (random.nextDouble() - 0.5) * math.pi * 1.4,
          speed: 160 + random.nextDouble() * 220,
          spin: (random.nextDouble() - 0.5) * 12,
          colour: colours[i % colours.length],
        )
    ];
  }();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _t,
          builder: (_, __) => CustomPaint(
            size: MediaQuery.sizeOf(context),
            painter: _ConfettiPainter(widget.at, _pieces, _t.value),
          ),
        ),
      );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.at, this.pieces, this.t);
  final Offset at;
  final List<({double angle, double speed, double spin, Color colour})> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Thrown out, then falling.
    final secs = t * 1.1;
    for (final p in pieces) {
      final pos = at +
          Offset(math.cos(p.angle), math.sin(p.angle)) * p.speed * secs +
          Offset(0, 420 * secs * secs);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * secs);
      canvas.drawRect(const Rect.fromLTWH(-4, -2.5, 8, 5),
          Paint()..color = p.colour.withValues(alpha: 1 - t * t));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
