/// Name: FloorPopWidgets
/// Parent: Layout, SessionPage, SongPage, DifficultyListPage, HistoryPage,
/// ScoreOverviewPage
/// Description: The small pieces Floor Pop is built from: the pad glyph,
/// a leaning wrapper, the Volt button whose riser collapses on press, and a
/// tab's leaning page title, the pill tab strip and page dots.
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

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

/// A header action on a riser, beside the leaning page titles.
class HeaderButton extends StatelessWidget {
  const HeaderButton(
      {super.key,
      required this.icon,
      required this.tooltip,
      required this.onPressed,
      this.color});

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: icon,
          style: IconButton.styleFrom(
            backgroundColor: FloorPop.of(context).riser,
            foregroundColor: color ?? Theme.of(context).colorScheme.onSurface,
            fixedSize: const Size(44, 44),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
}

/// Where a swipe through [count] pages is: Volt up to the page at [index],
/// which stretches.
class PageDots extends StatelessWidget {
  const PageDots(this.count, {super.key, required this.index});

  final int count, index;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    // A long run shrinks to the width it has rather than overflow.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
              duration: FloorPop.eighth,
              width: i == index ? 18 : 8,
              height: 8,
              decoration: BoxDecoration(
                  color: i <= index ? FloorPop.volt : pop.line,
                  borderRadius: BorderRadius.circular(4))),
      ]),
    );
  }
}

/// [padding] plus the space the glass header takes at the top and the
/// floating tab bar at the bottom, so a page scrolls under both and its first
/// and last rows still sit clear of them. [context] must be inside the page's
/// Scaffold, the only place the header's height is known.
EdgeInsets clearOfBars(BuildContext context, EdgeInsets padding) {
  final bars = MediaQuery.paddingOf(context);
  return padding.copyWith(
      top: padding.top + bars.top, bottom: padding.bottom + bars.bottom);
}

/// A page header's frosted fill, so the page still shows through, blurred, as
/// it scrolls under. [amount] fades it in from clear (0) to full frost (1).
/// Pages using it set `extendBodyBehindAppBar` and pad with [clearOfBars].
class GlassHeader extends StatelessWidget {
  const GlassHeader({super.key, this.amount = 1});

  final double amount;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16 * amount, sigmaY: 16 * amount),
          child: ColoredBox(
              color: FloorPop.of(context).ink.withValues(alpha: 0.55 * amount),
              // Fills the header, whose height comes in loose.
              child: const SizedBox.expand()),
        ),
      );
}

/// [child] rising into place on the beat when it first appears: a quarter
/// note long, each [index] a 1/32 later than the one before. Only the first
/// eight stagger, and nothing moves when the system asks for reduced motion.
/// Fade and slide only, so it costs the compositor and not a relayout.
class BeatIn extends StatefulWidget {
  const BeatIn(
      {super.key, required this.child, this.index = 0, this.animate = true});

  final Widget child;
  final int index;
  final bool animate;

  @override
  State<BeatIn> createState() => _BeatInState();
}

class _BeatInState extends State<BeatIn> with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(vsync: this, duration: FloorPop.beat);
  late final _curve =
      CurvedAnimation(parent: _controller, curve: FloorPop.step);
  late final _slide =
      Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(_curve);
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted || _delay != null) {
      return;
    }
    if (!widget.animate ||
        widget.index > 7 ||
        MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
      return;
    }
    _delay = Timer(
        FloorPop.sixteenth * widget.index ~/ 2, () => _controller.forward());
  }

  @override
  void dispose() {
    _delay?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _controller,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

/// A number that cross-fades when it changes, so a readout ticks over rather
/// than jumps.
class BeatSwap extends StatelessWidget {
  const BeatSwap({super.key, required this.child});

  /// Keyed by its value so a change swaps rather than restyles.
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: FloorPop.sixteenth,
        switchInCurve: FloorPop.settle,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0).animate(animation),
              child: child),
        ),
        child: child,
      );
}

/// A tab strip on a riser track, the selected tab on a primary pill. Uses
/// the surrounding [DefaultTabController] unless [controller] is given.
class PillTabBar extends StatelessWidget {
  const PillTabBar(
      {super.key,
      required this.tabs,
      this.controller,
      this.onTap,
      this.tabHeight = 36});

  final List<Widget> tabs;
  final TabController? controller;
  final ValueChanged<int>? onTap;
  final double tabHeight;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: tabHeight + 8,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: pop.riser, borderRadius: BorderRadius.circular(16)),
      child: TabBar(
        controller: controller,
        onTap: onTap,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        indicator: BoxDecoration(
            color: scheme.primary, borderRadius: BorderRadius.circular(12)),
        labelColor: scheme.onPrimary,
        unselectedLabelColor: pop.haze,
        splashBorderRadius: BorderRadius.circular(12),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        // Plain Text tabs otherwise shrink the InkWell to the label's height.
        // TabBar adds its 2px indicator inset below each child.
        tabs: [
          for (final tab in tabs)
            SizedBox(height: tabHeight - 2, child: Center(child: tab)),
        ],
      ),
    );
  }
}

/// [PillTabBar] as a picker: one tab per value in [values], for a choice
/// that switches content in place rather than paging.
class PillTabs<T> extends StatefulWidget {
  const PillTabs(
      {super.key,
      required this.values,
      required this.tabs,
      required this.selected,
      required this.onChanged,
      this.tabHeight = 36});

  final List<T> values;
  final List<Widget> tabs;
  final T selected;
  final ValueChanged<T> onChanged;
  final double tabHeight;

  @override
  State<PillTabs<T>> createState() => _PillTabsState<T>();
}

class _PillTabsState<T> extends State<PillTabs<T>>
    with SingleTickerProviderStateMixin {
  late final _controller = TabController(
      length: widget.values.length,
      initialIndex: widget.values.indexOf(widget.selected),
      vsync: this);

  @override
  void didUpdateWidget(PillTabs<T> old) {
    super.didUpdateWidget(old);
    final i = widget.values.indexOf(widget.selected);
    if (i != _controller.index) _controller.animateTo(i);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PillTabBar(
        controller: _controller,
        tabs: widget.tabs,
        tabHeight: widget.tabHeight,
        onTap: (i) => widget.onChanged(widget.values[i]),
      );
}
