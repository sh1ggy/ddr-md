/// Name: ArcadeGridTile
/// Parent: ArcadeGridView
/// Description: One jacket in the arcade grid. The focused tile grows into the
/// padding its cell reserves and gains a pulsing accent glow, reproducing the
/// cabinet's highlighted selection without overflowing its cell — a scaled
/// tile would be overpainted by later siblings and clipped by the viewport.
library;

import 'package:ddr_md/components/songlist/arcade/arcade_theme.dart';
import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:flutter/material.dart';

// Gap each unfocused tile leaves around its jacket. The focused tile animates
// this to zero, so it grows into the reserved space instead of over its
// neighbours.
const double kArcadeTileGap = 7;

class ArcadeGridTile extends StatefulWidget {
  const ArcadeGridTile({
    super.key,
    required this.item,
    required this.focused,
    required this.onTap,
  });

  final SongItem item;
  final bool focused;
  final VoidCallback onTap;

  @override
  State<ArcadeGridTile> createState() => _ArcadeGridTileState();
}

class _ArcadeGridTileState extends State<ArcadeGridTile>
    with SingleTickerProviderStateMixin {
  // Only the focused tile keeps a ticker running, so the grid has at most one
  // live animation no matter how many jackets are on screen.
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.focused) _startPulse();
  }

  @override
  void didUpdateWidget(ArcadeGridTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused && _pulse == null) {
      _startPulse();
    } else if (!widget.focused && _pulse != null) {
      _pulse!.dispose();
      _pulse = null;
    }
  }

  void _startPulse() {
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.all(widget.focused ? 0 : kArcadeTileGap),
        child: _pulse == null
            ? _jacket(1)
            : AnimatedBuilder(
                animation: _pulse!,
                builder: (context, child) => _jacket(_pulse!.value),
              ),
      ),
    );
  }

  // [glow] runs 0..1 with the pulse; unfocused tiles are drawn at a fixed 1
  // and simply have no glow to modulate.
  Widget _jacket(double glow) {
    final bool focused = widget.focused;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: focused
            ? Border.all(color: kArcadeAccent, width: 2)
            : Border.all(color: Colors.white10),
        boxShadow: focused
            ? <BoxShadow>[
                BoxShadow(
                  color: kArcadeAccent.withValues(alpha: 0.30 + 0.35 * glow),
                  blurRadius: 10 + 8 * glow,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image(
            image: AssetImage(
                'assets/jackets-160/${widget.item.songInfo.name}.png'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) => const ColoredBox(
              color: kArcadeSurface,
              child: Icon(Icons.music_note, size: 30, color: Colors.white24),
            ),
          ),
          if (widget.item.isFav)
            const Positioned(
              top: 2,
              left: 2,
              child: Icon(Icons.star, color: Colors.yellow, size: 14),
            ),
        ],
      ),
    );
  }
}
