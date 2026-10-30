/// Name: VersionGroup
/// Parent: ScoreOverview, JacketEdition
/// Description: Shared version families for flare skill and edition motifs.
library;

import 'dart:ui' show Color;
import 'package:ddr_md/constants.dart' show canonicalVersion;

/// DDR WORLD's flare skill groups, by the version a song first appeared in.
enum FlareGroup {
  classic('CLASSIC', Color(0xFF7FA3C8)),
  white('WHITE', Color(0xFFE8E8F0)),
  gold('GOLD', Color(0xFFD4A82A));

  const FlareGroup(this.label, this._color);

  final String label;
  final Color _color;

  /// WHITE darkens to a grey in the light theme so it still reads.
  Color color(bool isDark) =>
      this == white && !isDark ? const Color(0xFF8A8A96) : _color;
}

FlareGroup? flareGroup(String version) => switch (canonicalVersion(version)) {
      '1st' ||
      '2nd' ||
      '3rd' ||
      '4th' ||
      '5th' ||
      'MAX' ||
      'MAX2' ||
      'EXTREME' ||
      'SuperNOVA' ||
      'SuperNOVA2' ||
      'X' ||
      'X2' ||
      'X3' =>
        FlareGroup.classic,
      '2013' || '2014' || 'A' || 'A20' => FlareGroup.white,
      'A20 PLUS' || 'A3' || 'WORLD' => FlareGroup.gold,
      _ => null,
    };
