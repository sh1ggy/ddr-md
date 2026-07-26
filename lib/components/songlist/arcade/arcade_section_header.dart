/// Name: ArcadeSectionHeader
/// Parent: ArcadeGridView
/// Description: The folder banner that opens each section of the arcade grid,
/// styled after the cabinet's category headers: an accent-tinted bar fading
/// out to the right, with the folder name and its song count.
library;

import 'package:ddr_md/components/songlist/arcade/arcade_theme.dart';
import 'package:flutter/material.dart';

class ArcadeSectionHeader extends StatelessWidget {
  const ArcadeSectionHeader({
    super.key,
    required this.label,
    required this.accent,
    required this.count,
  });

  final String label;
  final Color accent;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              accent.withValues(alpha: 0.32),
              accent.withValues(alpha: 0.02),
            ],
          ),
          border: Border(
            left: BorderSide(color: accent, width: 3),
            bottom: BorderSide(color: accent.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  fontSize: 17,
                  letterSpacing: 1.5,
                  color: accent,
                ),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                fontFamily: kArcadeFont,
                fontSize: 14,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
