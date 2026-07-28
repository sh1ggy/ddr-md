/// Name: Chart preview models
/// Parent: ChartScroller
/// Description: Small immutable value types shared between the scroller state
/// (which builds them from the note stream) and the painters (which draw
/// them). Split out of chart_scroller.dart so both sides can import them
/// without one depending on the other.
library;

import 'package:flutter/material.dart';

/// The parity palette: left foot warm, right foot cool, so the two read apart
/// at a glance without a legend. Shared by the on-arrow L/R badges, the
/// foot-flow paths and the dancing-feet pad — one solve, one colour language.
const Color kLeftFootColor = Color(0xFFFF5D73);
const Color kRightFootColor = Color(0xFF3FA9FF);

/// A row of simultaneous mines spanning most/all columns — a DDR shock arrow,
/// which is drawn as a single bar per lane rather than individual mines.
class ShockRow {
  final double second;
  final Set<int> cols;
  const ShockRow(this.second, this.cols);
}

class MinimapSegment {
  final Color color;
  final double weight;
  const MinimapSegment(this.color, this.weight);
}

/// A tempo change at [second], to [bpm]. Only real transitions are kept (the
/// song's opening BPM is not a "change"), so the field isn't cluttered with a
/// marker at t=0 on every chart.
class BpmMarker {
  final double second;
  final int bpm;
  const BpmMarker(this.second, this.bpm);
}

/// A stop of [dur] seconds starting at [second]. Rendered as a band spanning its
/// duration on the scroll field so its length reads at a glance.
class StopMarker {
  final double second;
  final double dur;
  const StopMarker(this.second, this.dur);
}

class MinimapBucket {
  final double level;
  final List<MinimapSegment> segments;
  final double holdLevel;
  final bool hasShock;
  const MinimapBucket({
    required this.level,
    required this.segments,
    required this.holdLevel,
    required this.hasShock,
  });
}
