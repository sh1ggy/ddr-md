/// Name: FloorPopWidgets
/// Parent: Layout, SessionPage, SongPage, DifficultyListPage
/// Description: The small pieces Floor Pop is built from: the pad glyph,
/// a leaning wrapper, the Volt button whose riser collapses on press, and a
/// tab's leaning page title.
library;

import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Four panels of a dance pad, the app's mark and the Home tab's icon;
/// [lit] gives each panel its own spectrum colour.
class PadGlyph extends StatelessWidget {
  const PadGlyph({super.key, this.size = 24, this.color, this.lit = false});

  final double size;
  final Color? color;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.white;
    final cell = size * 0.31;
    Widget panel(double x, double y, Color litColor) => Positioned(
          left: x * size,
          top: y * size,
          child: Container(
            width: cell,
            height: cell,
            decoration: BoxDecoration(
                color: lit ? litColor : c,
                borderRadius: BorderRadius.circular(cell * 0.28)),
          ),
        );
    return SizedBox.square(
      dimension: size,
      child: Stack(children: [
        panel(0.345, 0.02, FloorPop.coral),
        panel(0.02, 0.345, FloorPop.padBlue),
        panel(0.67, 0.345, FloorPop.volt),
        panel(0.345, 0.67, FloorPop.grape),
      ]),
    );
  }
}

/// [child] on the −12° lean; wrap its text in [Upright] to stand it back up.
class Lean extends StatelessWidget {
  const Lean({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Transform(
        alignment: Alignment.center,
        transform: FloorPop.lean,
        child: child,
      );
}

/// Undoes [Lean] for text inside a leaning surface.
class Upright extends StatelessWidget {
  const Upright({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.inverted(FloorPop.lean),
        child: child,
      );
}

/// The primary action: Volt with a hard edge under it that drops away on
/// press, like a panel going down.
class VoltButton extends StatefulWidget {
  const VoltButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = 56,
    this.color = FloorPop.volt,
    this.riser = FloorPop.voltRiser,
    this.foreground = FloorPop.onVolt,
    this.radius = 18,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double height, radius;
  final Color color, riser, foreground;
  final String? tooltip;

  @override
  State<VoltButton> createState() => _VoltButtonState();
}

class _VoltButtonState extends State<VoltButton> {
  bool _down = false;

  static const _rise = 5.0;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final button = Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: SizedBox(
          height: widget.height + _rise,
          child: Stack(children: [
            Positioned.fill(
              top: _rise,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: enabled ? widget.riser : Colors.transparent,
                  borderRadius: BorderRadius.circular(widget.radius),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: FloorPop.sixteenth,
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              top: _down ? _rise : 0,
              height: widget.height,
              child: Opacity(
                opacity: enabled ? 1 : 0.4,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(widget.radius),
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                        color: widget.foreground,
                        fontFamily: kDisplayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 15),
                    child: IconTheme.merge(
                      data: IconThemeData(color: widget.foreground),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    return widget.tooltip == null
        ? button
        : Tooltip(message: widget.tooltip!, child: button);
  }
}

/// A tab's title: Unbounded caps on the title lean.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Transform(
            transform: FloorPop.titleLean,
            alignment: Alignment.bottomLeft,
            child: Text(text.toUpperCase(),
                style: FloorPop.display(28,
                    color: Theme.of(context).colorScheme.onSurface)),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      );
}
