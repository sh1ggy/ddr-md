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

/// The stored coordinates are thousandths PLUS ONE, because [Settings.getInt]
/// returns 0 for a key that was never written and 0 is itself a legitimate
/// position (hard against the left/top edge). Biasing by one keeps "never
/// placed" (0) distinct from "placed at the edge" (1), so a pad the user has
/// deliberately parked in the corner isn't mistaken for an unplaced one.
const int kDancingFeetUnset = 0;

/// How far the body turns, given the panel each foot stands on.
///
/// These are the panels the player is really standing on: the parity solve runs
/// on the chart as TURNED, so a stance already accounts for the modifier and no
/// column mapping belongs anywhere on this path.
///
/// You stand facing the machine, and almost nothing turns you. A staircase runs
/// through every panel without ever crossing your legs; a foot on Up while the
/// other is on Down is just one foot forward. So the feet point straight up the
/// pad by default and turn only on a genuine crossover.
///
/// The test is about PANELS, not coordinates: Up and Down are neutral ground
/// that either foot uses freely, so a cross is one foot standing on the SIDE
/// panel that belongs to the other foot — the left foot on Right, or the right
/// foot on Left. Measuring the feet's x positions instead gets this wrong,
/// because a foot reaching for a centre panel can sit further across than its
/// partner without any crossing having happened, which spins the body a quarter
/// turn in the middle of an ordinary staircase.
///
/// BOTH feet share the angle: you turn at the waist, and the whole body goes
/// with it. Turning the crossing foot alone leaves the planted one splayed at
/// right angles to its partner, which is not a stance a body can hold.
///
/// Where it turns TO is the line between the feet — your shoulders square up to
/// your own stance. The axis runs from the planted foot's panel to the crossing
/// foot's, so a cross with the partner on Down opens the body one way and the
/// same cross with the partner on Up winds it the other. That lands on 45deg for
/// a single cross, not the 90 a foot-on-side-panel rule would give: one foot is
/// still on a centre panel, so the diagonal is half a turn.
///
/// Facing along that axis or back down it is the same stance, so the heading
/// folds onto +-90. The fully swapped stance sits exactly on the fold — both
/// feet on side panels puts the axis flat across the pad, where +90 and -90 name
/// the same line — and it resolves to +90, the way the legs actually wind.
@visibleForTesting
double turnFor(int leftCol, int rightCol) {
  // Both feet on one panel is a footswitch — they are stacked, not crossed.
  if (leftCol == rightCol) return 0;
  final leftCrossed = leftCol == _colRight;
  final rightCrossed = rightCol == _colLeft;
  if (!leftCrossed && !rightCrossed) return 0;
  // Fully swapped: the axis is flat across the pad and the fold below can't
  // choose a side, so name the winding explicitly.
  if (leftCrossed && rightCrossed) return _maxTurn;

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

/// Panel geometry, as offsets in "panel units" from the pad centre: the four
/// arrows of one pad sit on a plus, matching the physical stage. Shared between
/// the turn above, which reads the line between the feet off it, and the painter
/// below, which draws the panels there — one stage, one set of coordinates.
const List<Offset> _panelOffsets = [
  Offset(-1, 0), // left
  Offset(0, 1), // down
  Offset(0, -1), // up
  Offset(1, 0), // right
];

/// How far a foot shrinks at the bottom of its press. A foot coming down on a
/// panel is seen from above as it drops, so it reads smaller for the moment it
/// lands — that dip is what separates a foot PLANTED on a panel from one merely
/// hovering over it. Small: enough to register as weight going down, not so much
/// that a stream of steps turns into a row of pulsing blobs.
const double _pressScale = 0.82;

/// Recovery is a shade longer than the panel flash, so the foot is still
/// settling as the light fades rather than snapping back before it.
const double _pressSeconds = 0.2;

/// The size multiplier for a foot [sinceStep] seconds after it landed: smallest
/// on impact, easing back to full as the weight settles. Outside the press
/// window it is exactly 1, so a foot standing through a long gap is drawn at the
/// size it would be if there were no press at all.
@visibleForTesting
double padPressFactor(double sinceStep) {
  if (sinceStep < 0 || sinceStep >= _pressSeconds) return 1.0;
  final recovered =
      Curves.easeOutCubic.transform((sinceStep / _pressSeconds).clamp(0.0, 1.0));
  return _pressScale + (1 - _pressScale) * recovered;
}

/// Column indices for the two side panels.
const int _colLeft = 0;
const int _colRight = 3;

/// A full crossover turns the feet a quarter circle.
const double _maxTurn = math.pi / 2;

/// The pad: a floating, draggable overlay showing where the parity solve stands
/// the player at the playhead. Driven by the scroller's playhead notifier so the
/// feet animate without rebuilding the widget tree per frame.
///
/// It floats rather than sitting in the control column because there is no one
/// right place for it — where it belongs depends on the chart, the phone and
/// where the user's thumbs are. Press and hold to pick it up, drag to place it;
/// the position is remembered as a fraction of the field (see
/// [Settings.dancingFeetXKey]) so it survives rotation and a change of device.
class DancingFeet extends StatefulWidget {
  const DancingFeet({
    super.key,
    required this.stances,
    required this.playhead,
    required this.columnCount,
    this.visualOffset = 0,
  });

  /// The solved stance timeline, ascending by second.
  final List<ParityStance> stances;

  final ValueListenable<double> playhead;

  /// VISUAL OFFSET in seconds, added to the playhead exactly as the field does
  /// it — otherwise a dialled offset would slide the arrows without sliding the
  /// feet, and the pad would step early or late against what's on screen.
  final double visualOffset;

  /// 4 for singles, 8 for doubles — a doubles pad draws as two panels.
  final int columnCount;

  /// Tall enough for the three-panel-high stage to read at a glance without
  /// covering much of the field. Doubles draws two pads in this width, so its
  /// panels come out smaller — deliberately, since the point there is the
  /// distance a foot travels across the whole stage.
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
      // Free space the pad's top-left can range over, so a fraction of 1 puts
      // its far edge on the field's far edge instead of off-screen. The whole
      // field is fair game, chrome included — the pad's layer sits above the
      // controls, so it stays grabbable even parked on top of them.
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
                  // The field runs its OWN long press (2x fast-forward) over the
                  // whole screen, and both recognizers would otherwise reach
                  // their deadline on the same frame — the arena breaks that tie
                  // by entry order, which is not ours to rely on. A shorter
                  // deadline makes the pad win outright whenever the touch
                  // started on it, so picking the pad up never fast-forwards.
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
              child: _PadSurface(
                dragging: _dragging,
                stances: widget.stances,
                playhead: widget.playhead,
                columnCount: widget.columnCount,
                visualOffset: widget.visualOffset,
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// The pad's own chrome and canvas, independent of where it floats.
class _PadSurface extends StatelessWidget {
  const _PadSurface({
    required this.dragging,
    required this.stances,
    required this.playhead,
    required this.columnCount,
    required this.visualOffset,
  });

  final bool dragging;
  final List<ParityStance> stances;
  final ValueListenable<double> playhead;
  final int columnCount;
  final double visualOffset;

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

  const _FootPose(this.heelCol, this.toeCol);

  Offset heel(Offset Function(int) pointFor) => pointFor(heelCol);
  Offset toe(Offset Function(int) pointFor) => pointFor(toeCol);
}

class _PadPainter extends CustomPainter {
  _PadPainter({
    required this.stances,
    required this.playhead,
    required this.columnCount,
    required this.visualOffset,
  }) : super(repaint: playhead);

  final List<ParityStance> stances;
  final ValueListenable<double> playhead;
  final int columnCount;
  final double visualOffset;

  double get second => playhead.value + visualOffset;

  /// Seconds a foot takes to slide from one panel to the next. Short enough
  /// that it lands with the note rather than lagging behind it, long enough
  /// that a fast run reads as movement instead of teleporting.
  static const double _stepSeconds = 0.09;

  /// How long a stepped panel stays lit after it is hit.
  static const double _flashSeconds = 0.16;

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
        : Curves.easeOutCubic.transform((sinceStep / _stepSeconds).clamp(0.0, 1.0));

    final lit = sinceStep <= _flashSeconds
        ? current.stepped
        : const <int>{};
    _paintPanels(canvas, pointFor, unit, lit,
        flash: sinceStep <= _flashSeconds
            ? 1 - (sinceStep / _flashSeconds).clamp(0.0, 1.0)
            : 0);

    // The body's turn, slid alongside the feet so a crossover winds round as the
    // foot travels rather than snapping square on the landing frame. One angle
    // for both feet: the waist turns and the whole body follows.
    final turn = _lerpAngle(_bodyTurn(previous ?? current), _bodyTurn(current), t);

    for (final foot in ParityFoot.values) {
      final to = _poseFor(current, foot);
      if (to == null) continue; // foot not on the pad yet
      final from = (previous == null ? null : _poseFor(previous, foot)) ?? to;
      // Only the foot that actually stepped presses. A foot standing still while
      // its partner steps is holding its weight, not landing, and bobbing it too
      // would read as both feet hitting on every note.
      final press = _stepped(current, foot) ? padPressFactor(sinceStep) : 1.0;
      _paintFoot(canvas, pointFor, unit, foot, from, to, t, turn, press);
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

  /// This stance's [turnFor], read off the panels each foot stands on. Doubles
  /// has no single pair of side panels to cross over, so it stays square.
  ///
  /// No mapping happens here: the solve already ran on the turned chart, so a
  /// stance names the panels the player is really standing on and a crossover in
  /// it is a real crossover.
  double _bodyTurn(ParityStance stance) {
    if (columnCount > 4) return 0;
    // The heel names the panel a foot is standing on; a bracket's toe doesn't
    // change which side of the body the foot is on. A foot not yet on the pad
    // has no side, so the body stays square.
    final left = stance.leftHeel == -1 ? stance.leftToe : stance.leftHeel;
    final right = stance.rightHeel == -1 ? stance.rightToe : stance.rightHeel;
    if (left == -1 || right == -1) return 0;
    return turnFor(left, right);
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
    return _FootPose(heel == -1 ? toe : heel, toe == -1 ? heel : toe);
  }

  static final Paint _panelPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.05);
  static final Paint _panelBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = Colors.white.withValues(alpha: 0.12);

  /// The four arrow panels, lit briefly as they are stepped on.
  void _paintPanels(
    Canvas canvas,
    Offset Function(int) pointFor,
    double unit,
    Set<int> lit, {
    double flash = 0,
  }) {
    final side = unit * 0.88;
    for (int col = 0; col < columnCount; col++) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: pointFor(col), width: side, height: side),
        Radius.circular(unit * 0.12),
      );
      canvas.drawRRect(rect, _panelPaint);
      canvas.drawRRect(rect, _panelBorderPaint);
      if (lit.contains(col) && flash > 0) {
        canvas.drawRRect(
          rect,
          Paint()..color = Colors.white.withValues(alpha: 0.20 * flash),
        );
      }
    }
  }

  /// One foot, drawn as a foot: a wide rounded forefoot tapering to a narrow
  /// heel, pointing from heel toward toe. A symmetric blob can't say which end
  /// is which — and which end is which is the whole point of a bracket, so the
  /// shape carries the heel/toe the solver already worked out. When the foot
  /// isn't bracketing it stands on one panel and points up the pad, turned only
  /// by [bodyTurn] — see [turnFor], which is 0 for everything but a crossover.
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
    final heel = Offset.lerp(from.heel(pointFor), to.heel(pointFor), t)!;
    final toe = Offset.lerp(from.toe(pointFor), to.toe(pointFor), t)!;

    // Heel->toe direction. Equal points mean a single-panel stance, which has no
    // axis of its own: it stands upright, turned only by the body (0 unless the
    // stance is crossed over). A bracket has a real axis and follows it instead.
    final axis = toe - heel;
    final len = axis.distance;
    final angle =
        len < 0.001 ? bodyTurn : math.atan2(axis.dy, axis.dx) + math.pi / 2;

    final color = foot == ParityFoot.left ? kLeftFootColor : kRightFootColor;
    canvas.save();
    canvas.translate((heel.dx + toe.dx) / 2, (heel.dy + toe.dy) / 2);
    canvas.rotate(angle);
    // Scaled about the foot's own centre (we are already translated there), so
    // the press squashes it in place instead of sliding it toward the panel's
    // corner as it shrinks.
    canvas.scale(press);
    // A foot never STRETCHES to its stance. Brackets are rare, and one that
    // stretched to span two panels reads as a rendering glitch rather than as a
    // reach — so a bracket only turns to point along its heel->toe line. The
    // press above is the one thing that changes a foot's size, and it is uniform
    // and brief.
    // Which way is "inward" for THIS foot, in the foot's own rotated frame: the
    // left foot's body is to its right (+x) and vice versa. Constant per foot
    // rather than derived from the pad centre, so the arch never flips sides
    // mid-run when a foot crosses over.
    final inward = foot == ParityFoot.left ? 1.0 : -1.0;
    // Longer than it is wide by about 1.8:1, the way a real foot is and the way
    // SMEditor's bot draws it. A rounder blob reads as a token sitting on the
    // panel; the length is what makes it read as a foot with a direction, and it
    // makes the heel/toe of a bracket legible at this size.
    _drawFootPath(canvas, unit * 0.46, unit * 0.82, color, inward);
    canvas.restore();
  }

  /// The foot outline itself, centred on the origin and pointing up (-y), so the
  /// caller only has to place and rotate it. [length] spans heel to toe.
  ///
  /// Handed: [inward] is the x direction of the pad's centre (-1 for a foot on
  /// the right of the body, +1 for one on the left), and the arch is cut into
  /// THAT side while the outer edge stays full. So the left and right feet are
  /// mirror images that visibly belong to one body, rather than two copies of
  /// the same shape.
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
      ..quadraticBezierTo(outer, -halfL - width * 0.12, 0, -halfL - width * 0.12)
      ..quadraticBezierTo(
          inner, -halfL - width * 0.12, inner, -halfL + width * 0.35)
      // Inner edge: scooped well in at the arch (0.62 of the half-width) before
      // meeting the heel — this hollow is what makes the foot read as a left or
      // a right at a glance.
      ..quadraticBezierTo(
          inner * 0.62, halfL * 0.30, innerHeel, halfL - heelW * 0.4)
      // Heel: a rounded cap across the back.
      ..quadraticBezierTo(innerHeel, halfL + heelW * 0.35, 0, halfL + heelW * 0.35)
      ..quadraticBezierTo(
          outerHeel, halfL + heelW * 0.35, outerHeel, halfL - heelW * 0.4)
      // Outer edge: stays full and convex all the way back to the toe.
      ..quadraticBezierTo(outer * 1.02, halfL * 0.32, outer, -halfL + width * 0.35)
      ..close();

    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.55));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      old.stances != stances ||
      old.columnCount != columnCount ||
      // Without this the feet wouldn't move while dialling VISUAL OFFSET
      // paused — same reason the field's painter watches it.
      old.visualOffset != visualOffset;
}