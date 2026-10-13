/// Name: DancingFeet
/// Parent: ChartScroller
/// Description: A small dance pad showing where the parity solver says both
/// feet are standing at the playhead, sliding between panels as the chart
/// plays. The scrolling field answers "which arrows come next"; this answers
/// "where does that leave my body" — crossovers, footswitches and brackets read
/// as physical positions instead of a column of L/R letters.
///
/// Inspired by SMEditor's dancing bot. It renders the SAME solve the L/R badges
/// come from ([ParityStance]), so the pad can never contradict the arrows.
library;

import 'dart:math' as math;

import 'chart_models.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Stored coordinates are thousandths PLUS ONE: [Settings.getInt] returns 0 for
/// an unwritten key, and 0 is itself a legitimate position (hard against the
/// edge), so the bias keeps "never placed" distinct from "parked in the corner".
const int kDancingFeetUnset = 0;

/// How far the body turns, given the panel each foot stands on. The parity solve
/// runs on the chart as TURNED, so these are the panels the player is really on
/// and no column mapping belongs on this path.
///
/// You stand facing the machine and almost nothing turns you — a staircase runs
/// through every panel without crossing your legs — so the feet point up the pad
/// by default and turn only on a genuine crossover. The test is about PANELS,
/// not coordinates: Up and Down are neutral ground either foot uses freely, so a
/// cross is one foot on the SIDE panel belonging to the other. Comparing the
/// feet's x positions instead spins the body mid-staircase, since a foot
/// reaching for a centre panel can sit further across than its partner.
///
/// BOTH feet share the angle — you turn at the waist. It turns to the line
/// between the feet, running from the planted foot's panel to the crossing
/// foot's, so the same cross winds one way with the partner on Down and the
/// other with it on Up. A single cross lands on 45deg, not 90, because one foot
/// is still on a centre panel. Facing along that axis or back down it is one
/// stance, so the heading folds onto ±90. The fully swapped stance sits exactly
/// on the fold, so it keeps winding whichever way the body [previous]ly faced —
/// a scooby that has turned you left finishes facing left rather than spinning
/// round to the right — and resolves to +90 from square.
@visibleForTesting
double turnFor(int leftCol, int rightCol, {double previous = 0}) {
  // Both feet on one panel is a footswitch — they are stacked, not crossed.
  if (leftCol == rightCol) return 0;
  final leftCrossed = leftCol == _colRight;
  final rightCrossed = rightCol == _colLeft;
  if (!leftCrossed && !rightCrossed) return 0;
  // Fully swapped: the axis is flat across the pad and the fold below can't
  // choose a side, so the body's existing turn does.
  if (leftCrossed && rightCrossed) return previous < 0 ? -_maxTurn : _maxTurn;

  // From the planted foot's panel to the crossing foot's: the body faces along
  // the line its own feet make.
  final planted = _panelOffsets[(leftCrossed ? rightCol : leftCol) % 4];
  final crossing = _panelOffsets[(leftCrossed ? leftCol : rightCol) % 4];
  final dx = crossing.dx - planted.dx;
  final dy = crossing.dy - planted.dy;
  // Canvas y runs down and 0 points up the pad, hence atan2(dx, -dy).
  final heading = math.atan2(dx, -dy);
  // Fold onto (-90, 90]: a heading and its opposite are one stance.
  final folded = (heading + _maxTurn) % math.pi - _maxTurn;
  return folded;
}

/// The body's turn after moving from the stance [fromLeft]/[fromRight] into
/// [leftCol]/[rightCol], given it was turned [previous].
///
/// [turnFor] says how a stance COULD face; context decides whether it does. The
/// body only winds round when one foot steps across its planted partner, the way
/// a scooby walks you round step by step. Landing crossed off a jump, re-pressing
/// a panel or stepping back out of a cross never turns you further — you stay
/// facing the screen with your legs crossed, or ease back towards it.
double stepTurn(
    double previous, int fromLeft, int fromRight, int leftCol, int rightCol) {
  final target = turnFor(leftCol, rightCol, previous: previous);
  final leftMoved = leftCol != fromLeft;
  final rightMoved = rightCol != fromRight;
  final steppedAcross = leftMoved != rightMoved &&
      (leftMoved ? leftCol == _colRight : rightCol == _colLeft);
  if (steppedAcross) return target;
  return previous.sign * math.min(previous.abs(), target.abs());
}

/// Panel geometry in "panel units" from the pad centre — one pad's four arrows
/// on a plus, matching the physical stage. Shared by the turn above and the
/// painter below so there is one set of coordinates.
const List<Offset> _panelOffsets = [
  Offset(-1, 0), // left
  Offset(0, 1), // down
  Offset(0, -1), // up
  Offset(1, 0), // right
];

/// Arrow heading per panel (L D U R) on the canvas, 0 pointing up the pad.
const List<double> _arrowTurn = [-math.pi / 2, math.pi, 0, math.pi / 2];

/// The cabinet's arrow acrylic in panel units about its panel's centre,
/// pointing up the pad (+y): rounded tip and wing tips, filleted shoulders,
/// and a shaft that flares into a bowed base. From [kArrowStart], each entry
/// is a line to (x, y) or a cubic through (x1, y1, x2, y2, x, y).
const (double, double) kArrowStart = (-0.1137, -0.2233);
const List<List<double>> kArrowOutline = [
  [-0.0766, -0.2179, -0.0387, -0.2151, 0, -0.2151],
  [0.0387, -0.2151, 0.0766, -0.2179, 0.1137, -0.2233],
  [0.1758, -0.2332, 0.1787, -0.1818, 0.1787, -0.1758],
  [0.1787, 0.0313],
  [0.1787, 0.0373, 0.1835, 0.0422, 0.1895, 0.0422],
  [0.2886, 0.0422],
  [0.3184, 0.0422, 0.3246, 0.0585, 0.3024, 0.0784],
  [0.0404, 0.3138],
  [0.0182, 0.3337, -0.0182, 0.3337, -0.0404, 0.3138],
  [-0.3024, 0.0784],
  [-0.3246, 0.0585, -0.3184, 0.0422, -0.2886, 0.0422],
  [-0.1895, 0.0422],
  [-0.1835, 0.0422, -0.1787, 0.0373, -0.1787, 0.0313],
  [-0.1787, -0.1758],
  [-0.1787, -0.1818, -0.1758, -0.2332, -0.1137, -0.2233],
];

/// [kArrowOutline] as a polygon, each curve cut into [steps] straight pieces.
List<(double, double)> arrowPolygon([int steps = 6]) {
  var (x0, y0) = kArrowStart;
  final out = <(double, double)>[];
  for (final seg in kArrowOutline) {
    if (seg.length == 2) {
      out.add((seg[0], seg[1]));
    } else {
      for (int i = 1; i <= steps; i++) {
        final t = i / steps, u = 1 - t;
        double at(double a, double b, double c, double d) =>
            u * u * u * a +
            3 * u * u * t * b +
            3 * u * t * t * c +
            t * t * t * d;
        out.add(
            (at(x0, seg[0], seg[2], seg[4]), at(y0, seg[1], seg[3], seg[5])));
      }
    }
    (x0, y0) = (seg[seg.length - 2], seg[seg.length - 1]);
  }
  return out;
}

/// The arrow on the canvas, where y runs down.
final Path _arrowPath = () {
  final path = Path()..moveTo(kArrowStart.$1, -kArrowStart.$2);
  for (final s in kArrowOutline) {
    if (s.length == 2) {
      path.lineTo(s[0], -s[1]);
    } else {
      path.cubicTo(s[0], -s[1], s[2], -s[3], s[4], -s[5]);
    }
  }
  return path..close();
}();

/// Move clear before a shock and stay clear through its timing window.
double shockDodge(List<double> shocks, double second) {
  var amount = 0.0;
  for (final shock in shocks) {
    final dt = second - shock;
    if (dt < -0.22 || dt > 0.22) continue;
    final a = dt < -0.09
        ? (dt + 0.22) / 0.13
        : dt > 0.09
            ? (0.22 - dt) / 0.13
            : 1.0;
    amount = math.max(amount, Curves.easeInOut.transform(a.clamp(0.0, 1.0)));
  }
  return amount;
}

/// One panel of the gold cabinet's stage: a 283 mm cell.
const double kPanelMetres = 0.283;

/// Outsole length in metres of a men's US [size] shoe: the last is a third of
/// an inch per size from 22/3 in, the sole a little longer.
double shoeLength(double size) => ((size + 22) / 3 * 25.4 + 15) / 1000;

/// US 9, for a player who hasn't set theirs.
const double kShoeSize = 9;

/// The corners an arrow panel's plate is cut away at, in panel units.
const double kPanelChamfer = 0.15;

/// A lit panel's lamp.
const Color _lamp = Color(0xFFECF2FF);

/// How far a foot shrinks at the bottom of its press. Seen from above, a foot
/// coming down reads smaller for the moment it lands, which is what separates a
/// PLANTED foot from one hovering. Kept small so a stream of steps doesn't turn
/// into a row of pulsing blobs.
const double _pressScale = 0.82;

/// Long enough to read as the weight settling, short enough to finish before
/// the next step in a stream.
const double _pressSeconds = 0.2;

/// Size multiplier for a foot [sinceStep] seconds after landing: smallest on
/// impact, easing back to full as the weight settles, exactly 1 outside the
/// press window.
@visibleForTesting
double padPressFactor(double sinceStep) {
  if (sinceStep < 0 || sinceStep >= _pressSeconds) return 1.0;
  final recovered = Curves.easeOutCubic
      .transform((sinceStep / _pressSeconds).clamp(0.0, 1.0));
  return _pressScale + (1 - _pressScale) * recovered;
}

/// Column indices for the two side panels.
const int _colLeft = 0;
const int _colRight = 3;

/// A full crossover turns the feet a quarter circle.
const double _maxTurn = math.pi / 2;

/// How the dancers move. STANDARD lands on panel centres. MINIMAL is top-player
/// economy: feet on the inner part of each panel, shoulders square and still,
/// low quick lifts. EXAGGERATED is the opposite: high lifts and a body that
/// turns and bounces with every step. The flat pad only tells MINIMAL apart.
enum DancerForm { standard, minimal, exaggerated }

/// Where [foot] lands on [col]'s panel in [form], as an offset from the panel's
/// centre in panel units, +x right and +y up the pad. [otherCol] is the panel
/// the other foot is on (-1 for none).
///
/// MINIMAL keeps every foot on the inner side of its panel: the inner edge of
/// Left and Right, and the inner corner of Up and Down on the foot's own side,
/// which shortens every reach between them. A foot crossing onto the far side
/// panel takes its top corner in front of a partner on Down and its bottom
/// corner behind one on Up; one crossing onto Up or Down takes its inner centre.
///
/// Both feet on one panel (a footswitch) stand side by side on it, left foot
/// on the left; on a side panel MINIMAL puts them one ahead of the other
/// against its inner edge instead.
Offset formSpot(DancerForm form, int col, ParityFoot foot, int otherCol) {
  final side = foot == ParityFoot.left ? -1.0 : 1.0;
  final minimal = form == DancerForm.minimal;
  final sideways = col % 4 == _colLeft || col % 4 == _colRight;
  final inner = !minimal
      ? 0.0
      : sideways
          ? 0.25
          : 0.22;
  final inward = sideways
      ? Offset(col % 4 == _colLeft ? inner : -inner, 0)
      : Offset(0, col % 4 == 2 ? -inner : inner);
  if (otherCol == col) {
    if (minimal && sideways) return inward + Offset(0, -0.18 * side);
    return inward + Offset(0.28 * side, 0);
  }
  if (!minimal) return Offset.zero;
  final own = foot == ParityFoot.left ? _colLeft : _colRight;
  final far = foot == ParityFoot.left ? _colRight : _colLeft;
  final other = otherCol < 0 ? -1 : otherCol % 4;
  if (sideways) {
    if (col % 4 != far) return inward;
    return inward + Offset(0, other == 1 ? 0.2 : (other == 2 ? -0.2 : 0));
  }
  return inward + Offset(other == own ? 0 : 0.2 * side, 0);
}

/// The pad: a floating, draggable overlay showing where the parity solve stands
/// the player at the playhead. Driven by the scroller's playhead notifier so the
/// feet animate without rebuilding the widget tree per frame.
///
/// It floats because where it belongs depends on the chart, the phone and the
/// user's thumbs. Press and hold to pick it up; the position is remembered as a
/// fraction of the field so it survives rotation and a change of device.
class DancingFeet extends StatefulWidget {
  const DancingFeet({
    super.key,
    required this.stances,
    required this.playhead,
    required this.columnCount,
    this.visualOffset = 0,
    this.form = DancerForm.standard,
    this.shoeSize = kShoeSize,
    this.shocks = const [],
  });

  final DancerForm form;

  /// US shoe size; the feet are drawn to scale against the panels.
  final double shoeSize;
  final List<double> shocks;

  /// The solved stance timeline, ascending by second.
  final List<ParityStance> stances;

  final ValueListenable<double> playhead;

  /// VISUAL OFFSET in seconds, added to the playhead exactly as the field does,
  /// so the feet don't step early or late against the arrows on screen.
  final double visualOffset;

  /// 4 for singles, 8 for doubles — a doubles pad draws as two panels.
  final int columnCount;

  /// Tall enough for the three-panel stage to read at a glance without covering
  /// much of the field. Doubles fits two pads in this width, so its panels come
  /// out smaller — the point there is the distance a foot travels.
  static const double height = 108;

  /// Singles is a square-ish plus; doubles needs twice the width for its pair.
  double get width => columnCount <= 4 ? 132 : 244;

  @override
  State<DancingFeet> createState() => _DancingFeetState();
}

class _DancingFeetState extends State<DancingFeet> {
  // Top-left of the pad as a fraction of the free space (0 = hard against the
  // left/top edge, 1 = against the right/bottom). Fractions rather than pixels
  // so the pad keeps its place across rotations and screen sizes.
  double? _fx;
  double? _fy;

  // Picked up by a long press: while held, the pad follows the finger and lifts
  // visually so it's clear it's being moved rather than merely touched.
  bool _dragging = false;

  // The previous update's cumulative offset, so moves apply as deltas.
  Offset _lastDrag = Offset.zero;

  @override
  void initState() {
    super.initState();
    final x = Settings.getInt(Settings.dancingFeetXKey);
    final y = Settings.getInt(Settings.dancingFeetYKey);
    if (x != kDancingFeetUnset && y != kDancingFeetUnset) {
      _fx = (x - 1) / 1000.0;
      _fy = (y - 1) / 1000.0;
    }
  }

  // Default berth: centre-right, in the open part of the field where it blocks
  // neither the arrows nor the controls. Only a starting point — the pad may be
  // dragged anywhere from here, chrome included.
  static const double _defaultFx = 0.72;
  static const double _defaultFy = 0.46;

  double get _fxOrDefault => _fx ?? _defaultFx;
  double get _fyOrDefault => _fy ?? _defaultFy;

  void _persist() {
    Settings.setInt(
        Settings.dancingFeetXKey, (_fxOrDefault * 1000).round() + 1);
    Settings.setInt(
        Settings.dancingFeetYKey, (_fyOrDefault * 1000).round() + 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = widget.width;
      const h = DancingFeet.height;
      // Free space the top-left can range over, so a fraction of 1 puts the
      // pad's far edge on the field's rather than off-screen. Chrome included:
      // the pad's layer is above the controls, so it stays grabbable there.
      final freeX = math.max(0.0, constraints.maxWidth - w);
      final freeY = math.max(0.0, constraints.maxHeight - h);

      void moveBy(Offset delta) {
        setState(() {
          if (freeX > 0) {
            _fx = ((_fxOrDefault * freeX + delta.dx) / freeX).clamp(0.0, 1.0);
          }
          if (freeY > 0) {
            _fy = ((_fyOrDefault * freeY + delta.dy) / freeY).clamp(0.0, 1.0);
          }
        });
      }

      return Stack(
        children: [
          Positioned(
            left: _fxOrDefault * freeX,
            top: _fyOrDefault * freeY,
            width: w,
            height: h,
            child: RawGestureDetector(
              // Opaque so the pad claims touches that land ON it rather than
              // letting them fall through to the field.
              behavior: HitTestBehavior.opaque,
              gestures: {
                LongPressGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer>(
                  // The field runs its own long press (2x fast-forward) over the
                  // whole screen, and both would otherwise hit their deadline on
                  // the same frame, leaving the arena to break the tie by entry
                  // order. A shorter deadline makes the pad win outright.
                  () => LongPressGestureRecognizer(
                    duration: const Duration(milliseconds: 220),
                    debugOwner: this,
                  ),
                  (r) => r
                    ..onLongPressStart = (_) {
                      _lastDrag = Offset.zero;
                      setState(() => _dragging = true);
                    }
                    // offsetFromOrigin is cumulative from where the press began,
                    // so difference it into a per-update delta.
                    ..onLongPressMoveUpdate = (d) {
                      moveBy(d.offsetFromOrigin - _lastDrag);
                      _lastDrag = d.offsetFromOrigin;
                    }
                    ..onLongPressEnd = (_) {
                      setState(() => _dragging = false);
                      _persist();
                    },
                ),
              },
              child: DancePad(
                dragging: _dragging,
                stances: widget.stances,
                playhead: widget.playhead,
                columnCount: widget.columnCount,
                visualOffset: widget.visualOffset,
                form: widget.form,
                shoeSize: widget.shoeSize,
                shocks: widget.shocks,
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// The pad's own chrome and canvas, independent of where it floats. Also used
/// on its own, e.g. to replay a footing in the questionnaire.
class DancePad extends StatelessWidget {
  const DancePad({
    super.key,
    this.dragging = false,
    required this.stances,
    required this.playhead,
    required this.columnCount,
    this.visualOffset = 0,
    this.form = DancerForm.standard,
    this.shoeSize = kShoeSize,
    this.shocks = const [],
  });

  final bool dragging;
  final List<ParityStance> stances;
  final ValueListenable<double> playhead;
  final int columnCount;
  final double visualOffset;
  final DancerForm form;
  final double shoeSize;
  final List<double> shocks;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: dragging ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: dragging ? 0.55 : 0.32),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: dragging ? 0.35 : 0.08),
          ),
        ),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _PadPainter(
              stances: stances,
              playhead: playhead,
              columnCount: columnCount,
              visualOffset: visualOffset,
              form: form,
              shoeSize: shoeSize,
              shocks: shocks,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// Where one foot's heel and toe sit, as drawn columns. A plain step puts both
/// on the same panel; a bracket splits them, and the ORDER is what tells the
/// silhouette which way to point — so unlike [ParityStance.columnsFor] this
/// deliberately keeps heel and toe apart instead of folding them to a set.
class _FootPose {
  final int heelCol;
  final int toeCol;

  /// Nudge off the panel centre in panel units (canvas axes): sharing a panel
  /// with the other foot, or the spot the [DancerForm] puts it on.
  final Offset shift;

  const _FootPose(this.heelCol, this.toeCol, [this.shift = Offset.zero]);

  Offset heel(Offset Function(int) pointFor, double unit) =>
      pointFor(heelCol) + shift * unit;
  Offset toe(Offset Function(int) pointFor, double unit) =>
      pointFor(toeCol) + shift * unit;
}

class _PadPainter extends CustomPainter {
  _PadPainter({
    required this.stances,
    required this.playhead,
    required this.columnCount,
    required this.visualOffset,
    required this.form,
    required this.shoeSize,
    required this.shocks,
  }) : super(repaint: playhead);

  final List<ParityStance> stances;
  final ValueListenable<double> playhead;
  final int columnCount;
  final double visualOffset;
  final DancerForm form;
  final double shoeSize;
  final List<double> shocks;

  /// The body's turn at each stance, solved in order since whether a stance
  /// turns you depends on how you stepped into it (see [stepTurn]). Doubles has
  /// no single pair of side panels to cross over, so it stays square.
  ///
  /// No mapping happens here: the solve already ran on the turned chart, so a
  /// stance names the panels the player is really standing on and a crossover in
  /// it is a real crossover.
  late final List<double> _turns = () {
    final turns = <double>[];
    var last = 0.0;
    var fromLeft = -1, fromRight = -1;
    for (final stance in stances) {
      // The heel names the panel a foot is standing on; a bracket's toe doesn't
      // change which side of the body the foot is on. A foot not yet on the pad
      // has no side, so the body stays square.
      final left = stance.leftHeel == -1 ? stance.leftToe : stance.leftHeel;
      final right = stance.rightHeel == -1 ? stance.rightToe : stance.rightHeel;
      last = columnCount > 4 || left == -1 || right == -1
          ? 0
          : stepTurn(last, fromLeft, fromRight, left, right);
      turns.add(last);
      fromLeft = left;
      fromRight = right;
    }
    return turns;
  }();

  double get second => playhead.value + visualOffset;

  /// Seconds a foot takes to slide from one panel to the next. Short enough
  /// that it lands with the note rather than lagging behind it, long enough
  /// that a fast run reads as movement instead of teleporting.
  static const double _stepSeconds = 0.09;

  /// Each foot's arrivals in order: when it lands and the panels under it.
  late final List<List<(double, List<int>)>> _arrivals = [
    for (final foot in ParityFoot.values)
      () {
        final out = <(double, List<int>)>[];
        String? prev;
        for (final s in stances) {
          final cols = s.columnsFor(foot);
          if (cols.isEmpty) continue;
          final key = cols.join(',');
          if (!cols.any(s.stepped.contains) && key == prev) continue;
          prev = key;
          out.add((s.second, cols));
        }
        return out;
      }(),
  ];

  /// The panels with a foot drawn on them at [t]: lit once a sliding foot is
  /// halfway onto its panel until it's halfway off, with a short blink before
  /// a jack re-presses the same panel.
  Set<int> _pressed(double t) {
    final lit = <int>{};
    for (final ev in _arrivals) {
      var lo = 0, hi = ev.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (ev[mid].$1 <= t) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      // The arrival in force, and the one before it still sliding off.
      for (final k in [lo - 1, lo - 2]) {
        if (k < 0) continue;
        final (at, cols) = ev[k];
        bool same(int j) => listEquals(ev[j].$2, cols);
        final start = k > 0 && !same(k - 1) ? at + _stepSeconds / 2 : at;
        var end = double.infinity;
        if (k + 1 < ev.length) {
          final next = ev[k + 1].$1;
          end = same(k + 1)
              ? next - math.min(0.05, (next - at) / 3)
              : next + _stepSeconds / 2;
        }
        if (start <= t && t < end) lit.addAll(cols);
      }
    }
    return lit;
  }

  /// The drawn centre of a column, in panel units from the whole pad's centre.
  /// A doubles column past the fourth belongs to the second panel, shifted
  /// right by its width (3 panel units) — and both panels shift out from the
  /// centre so the pair straddles it.
  Offset _panelCenter(int col) {
    final base = _panelOffsets[col % 4];
    if (columnCount <= 4) return base;
    return base + Offset(col < 4 ? -1.5 : 1.5, 0);
  }

  /// First index whose second is > [t], i.e. the count of stances already
  /// reached. The stance in force is the one before it.
  int _upperBound(double t) {
    int lo = 0, hi = stances.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (stances[mid].second <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (stances.isEmpty) return;

    // Panel size: fit the pad's width (3 units per panel, 2 panels on doubles)
    // and its height (3 units), whichever binds. The extra ~0.3 unit of slack
    // keeps the outer panels off the widget's edges — a foot's oval overhangs
    // its panel, and flush against the boundary it reads as clipped.
    final unitsWide = columnCount <= 4 ? 3.3 : 6.3;
    final unit = math.min(size.width / unitsWide, size.height / 3.3);
    final center = Offset(size.width / 2, size.height / 2);
    Offset pointFor(int col) => center + _panelCenter(col) * unit;

    final idx = _upperBound(second);
    // Before the first row nobody is standing anywhere yet.
    if (idx == 0) {
      _paintPanels(canvas, pointFor, unit, const {});
      return;
    }
    final current = stances[idx - 1];
    final previous = idx >= 2 ? stances[idx - 2] : null;

    // Slide from the previous stance into the current one over [_stepSeconds],
    // eased so a foot settles rather than arriving at full speed.
    final sinceStep = second - current.second;
    final t = sinceStep >= _stepSeconds
        ? 1.0
        : Curves.easeOutCubic
            .transform((sinceStep / _stepSeconds).clamp(0.0, 1.0));

    final dodge = shockDodge(shocks, second);
    _paintPanels(
        canvas, pointFor, unit, dodge > 0.99 ? const {} : _pressed(second));

    // The body's turn, slid alongside the feet so a crossover winds round as the
    // foot travels rather than snapping square on the landing frame. One angle
    // for both feet: the waist turns and the whole body follows.
    final turn = _lerpAngle(
        _turns[previous == null ? idx - 1 : idx - 2], _turns[idx - 1], t);

    for (final foot in ParityFoot.values) {
      final to = _poseFor(current, foot);
      if (to == null) continue; // foot not on the pad yet
      final from = (previous == null ? null : _poseFor(previous, foot)) ?? to;
      // Only the foot that actually stepped presses. A foot standing still while
      // its partner steps is holding its weight, not landing, and bobbing it too
      // would read as both feet hitting on every note.
      final press = _stepped(current, foot) ? padPressFactor(sinceStep) : 1.0;
      final padX = columnCount <= 4
          ? 0.0
          : (_panelCenter(to.heelCol).dx < 0 ? -1.5 : 1.5);
      final safe =
          center + Offset(padX + (foot == ParityFoot.left ? -1 : 1), 1) * unit;
      Offset dodgePoint(int col) => Offset.lerp(pointFor(col), safe, dodge)!;
      _paintFoot(canvas, dodgePoint, unit, foot, from, to, t,
          turn * (1 - dodge), press);
    }
  }

  /// Did [foot] step on this row, as opposed to standing where it already was?
  bool _stepped(ParityStance stance, ParityFoot foot) {
    if (stance.stepped.isEmpty) return false;
    for (final col in stance.columnsFor(foot)) {
      if (stance.stepped.contains(col)) return true;
    }
    return false;
  }

  /// Shortest-path angle interpolation, so turning through the -pi/pi seam spins
  /// the short way instead of unwinding all the way round.
  double _lerpAngle(double a, double b, double t) {
    var delta = (b - a) % (math.pi * 2);
    if (delta > math.pi) delta -= math.pi * 2;
    if (delta < -math.pi) delta += math.pi * 2;
    return a + delta * t;
  }

  /// A foot's heel/toe columns, or null when it isn't on the pad yet. A foot
  /// standing on a single panel reports that panel as both, so the silhouette
  /// has a zero-length axis and stands upright.
  _FootPose? _poseFor(ParityStance stance, ParityFoot foot) {
    final heel = foot == ParityFoot.left ? stance.leftHeel : stance.rightHeel;
    final toe = foot == ParityFoot.left ? stance.leftToe : stance.rightToe;
    if (heel == -1 && toe == -1) return null;
    // Where on the panel comes from the form; both feet on one panel
    // (mid-footswitch) stand side by side rather than on top of each other.
    final left = stance.columnsFor(ParityFoot.left);
    final right = stance.columnsFor(ParityFoot.right);
    final own = foot == ParityFoot.left ? left : right;
    final other = foot == ParityFoot.left ? right : left;
    if (own.length != 1) {
      return _FootPose(heel == -1 ? toe : heel, toe == -1 ? heel : toe);
    }
    final spot =
        formSpot(form, own[0], foot, other.length == 1 ? other[0] : -1);
    return _FootPose(own[0], own[0], Offset(spot.dx, -spot.dy));
  }

  static final Paint _panelPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.05);
  static final Paint _panelBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = Colors.white.withValues(alpha: 0.12);

  static final Paint _arrowIdlePaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.14);
  static final Paint _arrowLitPaint = Paint()
    ..color = _lamp.withValues(alpha: 0.72);
  static final Paint _panelLitPaint = Paint()
    ..color = _lamp.withValues(alpha: 0.1);

  /// The arrow panels, each arrow lit while a foot is on its panel, the way
  /// the cabinet's lamps follow the press.
  void _paintPanels(
    Canvas canvas,
    Offset Function(int) pointFor,
    double unit,
    Set<int> lit,
  ) {
    // Plates fill their cells but for the seams between them.
    final h = unit * 0.485, c = unit * 0.97 * kPanelChamfer;
    // Scaled with the canvas, so the blur is in panel units.
    final glow = Paint()
      ..color = _lamp.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.08);
    for (int col = 0; col < columnCount; col++) {
      final centre = pointFor(col);
      // The plate, its corners cut away where the brackets hold it.
      final plate = Path()
        ..addPolygon([
          for (final (x, y) in [
            (-h + c, -h),
            (h - c, -h),
            (h, -h + c),
            (h, h - c),
            (h - c, h),
            (-h + c, h),
            (-h, h - c),
            (-h, -h + c),
          ])
            centre + Offset(x, y),
        ], true);
      final on = lit.contains(col);
      canvas.drawPath(plate, on ? _panelLitPaint : _panelPaint);
      canvas.drawPath(plate, _panelBorderPaint);
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(_arrowTurn[col % 4]);
      canvas.scale(unit);
      if (on) canvas.drawPath(_arrowPath, glow);
      canvas.drawPath(_arrowPath, on ? _arrowLitPaint : _arrowIdlePaint);
      canvas.restore();
    }
  }

  /// One foot: a wide rounded forefoot tapering to a narrow heel, pointing from
  /// heel toward toe. A symmetric blob couldn't say which end is which, which is
  /// the whole point of a bracket. Off a bracket the foot stands on one panel
  /// and points up the pad, turned only by [bodyTurn] (see [turnFor]).
  void _paintFoot(
    Canvas canvas,
    Offset Function(int) pointFor,
    double unit,
    ParityFoot foot,
    _FootPose from,
    _FootPose to,
    double t,
    double bodyTurn,
    double press,
  ) {
    final heel =
        Offset.lerp(from.heel(pointFor, unit), to.heel(pointFor, unit), t)!;
    final toe =
        Offset.lerp(from.toe(pointFor, unit), to.toe(pointFor, unit), t)!;

    // Heel->toe direction. Equal points mean a single-panel stance, which has no
    // axis of its own and stands upright under the body's turn; a bracket has a
    // real axis and follows it.
    final axis = toe - heel;
    final len = axis.distance;
    final angle =
        len < 0.001 ? bodyTurn : math.atan2(axis.dy, axis.dx) + math.pi / 2;

    final color = foot == ParityFoot.left ? kLeftFootColor : kRightFootColor;
    canvas.save();
    canvas.translate((heel.dx + toe.dx) / 2, (heel.dy + toe.dy) / 2);
    canvas.rotate(angle);
    // Scaled about the foot's own centre (already translated there) so the press
    // squashes it in place rather than sliding it toward the panel's corner. A
    // foot never STRETCHES to its stance — a bracket only turns to point along
    // its heel->toe line, since one stretched across two panels reads as a
    // rendering glitch. The press is the only thing that changes a foot's size.
    canvas.scale(press);
    // Which way is "inward" in the foot's own rotated frame: the left foot's
    // body is to its right (+x) and vice versa. Constant per foot rather than
    // derived from the pad centre, so the arch never flips sides on a crossover.
    final inward = foot == ParityFoot.left ? 1.0 : -1.0;
    // About 1.8:1, the way a real foot is and the way SMEditor's bot draws it.
    // The length is what gives the silhouette a direction and keeps a bracket's
    // heel/toe legible at this size.
    // To scale: the shoe's length against the 283 mm panel. The outline
    // tapers to the heel and scoops at the arch, so it takes a wider forefoot
    // than a real sole to read as one.
    final length = unit * shoeLength(shoeSize) / kPanelMetres;
    _drawFootPath(canvas, length * 0.55, length, color, inward);
    canvas.restore();
  }

  /// The foot outline, centred on the origin and pointing up (-y) so the caller
  /// only places and rotates it. [length] spans heel to toe.
  ///
  /// [inward] is the x direction of the body (+1 for the left foot, -1 for the
  /// right); the arch is cut into that side and the outer edge stays full, so
  /// the two feet are mirror images rather than two copies of one shape.
  void _drawFootPath(
      Canvas canvas, double width, double length, Color color, double inward) {
    final halfW = width / 2;
    final halfL = length / 2;
    // Forefoot is the full width; the heel is drawn at ~60% of it, which is what
    // gives the silhouette its direction at a glance.
    final heelW = halfW * 0.6;
    // The arch scoops in on the inner edge; the outer edge stays convex. Mirror
    // the x of every point by [inward] so one path serves both feet.
    final inner = halfW * inward;
    final outer = -inner;
    final innerHeel = heelW * inward;
    final outerHeel = -innerHeel;
    final path = Path()
      ..moveTo(outer, -halfL + width * 0.35)
      // Toe: a rounded cap across the front.
      ..quadraticBezierTo(
          outer, -halfL - width * 0.12, 0, -halfL - width * 0.12)
      ..quadraticBezierTo(
          inner, -halfL - width * 0.12, inner, -halfL + width * 0.35)
      // Inner edge: scooped in at the arch before meeting the heel — the hollow
      // is what makes the foot read as a left or a right at a glance.
      ..quadraticBezierTo(
          inner * 0.62, halfL * 0.30, innerHeel, halfL - heelW * 0.4)
      // Heel: a rounded cap across the back.
      ..quadraticBezierTo(
          innerHeel, halfL + heelW * 0.35, 0, halfL + heelW * 0.35)
      ..quadraticBezierTo(
          outerHeel, halfL + heelW * 0.35, outerHeel, halfL - heelW * 0.4)
      // Outer edge: stays full and convex all the way back to the toe.
      ..quadraticBezierTo(
          outer * 1.02, halfL * 0.32, outer, -halfL + width * 0.35)
      ..close();

    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(color, Colors.black, 0.35)!,
    );
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      old.stances != stances ||
      old.columnCount != columnCount ||
      // Without this the feet wouldn't move while dialling VISUAL OFFSET
      // paused — same reason the field's painter watches it.
      old.visualOffset != visualOffset ||
      old.form != form ||
      old.shoeSize != shoeSize ||
      old.shocks != shocks;
}
