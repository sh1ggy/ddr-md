/// Name: ArcadeSectionHeader
/// Parent: ArcadeGridView
/// Description: The folder banner that opens each section of the grid: a
/// full-width bar with the folder name and its song count, tapped to fold the
/// section away.
library;

import 'package:flutter/material.dart';
import 'package:ddr_md/theme.dart';

class ArcadeSectionHeader extends StatelessWidget {
  const ArcadeSectionHeader({
    super.key,
    required this.label,
    required this.count,
    this.collapsed = false,
    this.onTap,
  });

  final String label;
  final int count;
  final bool collapsed;
  // Null leaves the banner inert, for callers that don't fold sections.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ClipPath(
      clipper: const _BannerClipper(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            // A single bottom rule, not a box: banners butt straight against each
            // other when folded, and an all-round border would double up there.
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Transform(
                        transform: FloorPop.titleLean,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: scheme.onSurface,
                          ),
                        )),
                  ),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  // Fixed footprint whether or not it rotates, so folding never
                  // shifts the count beside it.
                  if (onTap != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: AnimatedRotation(
                        turns: collapsed ? -0.25 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : FloorPop.eighth,
                        child: Icon(
                          Icons.expand_more,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Lean the banner's ends inside its existing footprint, so collapsed folders
// stay as compact as the straight bars they replace.
class _BannerClipper extends CustomClipper<Path> {
  const _BannerClipper();

  @override
  Path getClip(Size size) {
    final lean = size.height * 0.21;
    return Path()
      ..moveTo(lean, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - lean, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_BannerClipper oldClipper) => false;
}
