/// Name: PlayStyleIcon
/// Parent: Shared components
/// Description: Accessible play-style artwork for chart labels and selectors.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:flutter/material.dart';

class PlayStyleIcon extends StatelessWidget {
  const PlayStyleIcon({
    super.key,
    required this.mode,
    this.height = 12,
    this.compact = true,
  });

  final Modes mode;
  final double height;

  /// Compact chart labels omit STYLE; mode switchers keep the full artwork.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final single = mode == Modes.singles;
    final label = single ? 'Singles' : 'Doubles';
    final image = Image.asset(
      'assets/icons/style_${single ? 'single' : 'double'}.png',
      height: height,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => Text(label),
    );
    // Keep only SINGLE / DOUBLE from the 314×42 artwork.
    final start = single ? 22.0 : 6.0;
    final unit = height / 42;
    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: !compact
          ? image
          : SizedBox(
              width: (155 - start) * unit,
              height: height,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 314 * unit,
                  maxWidth: 314 * unit,
                  child: Transform.translate(
                    offset: Offset(-start * unit, 0),
                    child: image,
                  ),
                ),
              ),
            ),
    );
  }
}
