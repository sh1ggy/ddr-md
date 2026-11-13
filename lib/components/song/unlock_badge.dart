/// Name: UnlockBadge
/// Parent: SongListItem, SongDifficultyPicker
/// Description: A round mark for a chart that isn't playable by default:
/// GALAXY BRAVE or a GRAND PRIX pack, named in its tooltip.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

class UnlockBadge extends StatelessWidget {
  const UnlockBadge(this.unlock, {super.key, this.size = 22});

  final ChartUnlock unlock;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color, name) = switch (unlock.source) {
      UnlockSource.galaxyBrave =>
        (Icons.rocket_launch_rounded, FloorPop.grape, 'GALAXY BRAVE'),
      UnlockSource.grandPrix => (
          Icons.shopping_bag_rounded,
          FloorPop.sun,
          unlock.pack.isEmpty ? 'GRAND PRIX' : 'GRAND PRIX · ${unlock.pack}'
        ),
    };
    return Tooltip(
      message: name,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: FloorPop.of(context).stage, width: 2),
        ),
        child: Icon(icon, size: size * 0.6, color: FloorPop.onVolt),
      ),
    );
  }
}
