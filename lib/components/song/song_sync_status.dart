/// Name: SongSyncStatus
/// Parent: SongSyncChart, SongListItem, ArcadeGridTile
/// Description: A shared offset readout with an explicit on-sync label.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

class SongSyncStatus extends StatelessWidget {
  const SongSyncStatus({
    super.key,
    required this.sync,
    this.fontSize = 12,
    this.decimals = 0,
    this.showUnit = true,
    this.compact = false,
  });

  final Sync? sync;
  final double fontSize;
  final int decimals;
  final bool showUnit, compact;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final reading = sync;
    if (reading != null && !reading.isOnSync) {
      // Round before adding the sign, so small offsets never read as −0.
      final adjustment = -reading.biasMs;
      final rounded = double.parse(adjustment.toStringAsFixed(decimals));
      final value = rounded == 0 ? 0.0 : rounded;
      final label = '${value >= 0 ? '+' : ''}'
          '${value.toStringAsFixed(decimals)}${showUnit ? ' ms' : ''}';
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Text(label,
          maxLines: 1,
          style: FloorPop.readout(fontSize,
              color: reading.biasMs < 0 ? kSlowColor(dark) : kFastColor(dark)));
    }

    final known = reading != null;
    final color = known ? pop.up : pop.haze;
    final label =
        known ? 'On sync' : (compact && !showUnit ? 'No data' : 'No sync data');
    return Semantics(
      label: known ? 'On sync, no offset adjustment needed' : 'No sync data',
      excludeSemantics: true,
      child: Text(label,
          maxLines: 1, style: FloorPop.readout(fontSize, color: color)),
    );
  }
}
