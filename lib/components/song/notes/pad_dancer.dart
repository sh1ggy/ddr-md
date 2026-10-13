/// Name: PadDancer
/// Parent: ChartScroller
/// Description: A low-poly dancer on a cabinet pad behind the arrows, seen
/// from behind by a fixed camera, stepping the chart with or without the back
/// bar. It reads the same parity stances as [DancingFeet], so the body can
/// never contradict the L/R badges; what the solve doesn't say (foot arcs,
/// hips, knees, arms) is filled in every frame, in the chosen [DancerForm].
/// Panels light while a foot is on them, the way the cabinet's do.
///
/// No 3D engine: a few hundred flat-shaded quads, depth-sorted on the CPU and
/// drawn with one [Canvas.drawVertices] call.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'chart_models.dart';
import 'dancing_feet.dart'
    show
        DancerForm,
        arrowPolygon,
        formSpot,
        kPanelChamfer,
        kPanelMetres,
        kShoeSize,
        shoeLength,
        stepTurn;
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/parity_shocks.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// World units are metres: x to the player's right, y up, z toward the screen.
// One stage unit is 910 mm wide: a 3x3 grid of 283 mm panels in a 30 mm rim.
const double _u = kPanelMetres; // one panel
const double _rim = 0.0305;
const double _padY = 0.15; // top of the pad
const double _stageDepth = 1.085;
const double _stageFront = 1.5 * _u + _rim;
const double _stageBack = _stageFront - _stageDepth;
const double _thigh = 0.44, _shin = 0.43, _upperArm = 0.30, _foreArm = 0.30;

/// How tall the mannequin stands at its own proportions, in metres; a set
/// height scales the body from here.
const double kDancerHeight = 1.71;

/// How the player holds the bar: palms down over it, or palms up under it
/// with the elbows tucked.
enum BarGrip { overhand, underhand }

/// Where on the bar the hands go: together on the top, or out on the bends.
enum GripSpot { middle, edges }

typedef _Rig = ({
  bool bar,
  BarGrip grip,
  GripSpot spot,
  double k,
  double shoe,
});
// Rail centreline dimensions; the padded outside top is 1.09 m above the
// floor and the outside width is 0.456 m. Geometry notes kept locally.
const double _barTubeRadius = 0.021;
const double _barPaddingRadius = 0.032;
const double _barY = 1.09 - _barPaddingRadius;
const double _barHalfWidth = 0.196;
const double _barBendRadius = 0.125;
const double _gripHalfWidth = 0.055;
const double _barZ = _stageBack + 0.085;
const double _stageHalfWidth = 1.5 * _u + _rim;

// The cabinet in front of the stage, to its dimension drawings (notes kept
// locally). Its base stands 60-90 cm in front of the stage (the near end here)
// and is 585 mm deep and 1480 mm wide. The 55" 16:9 monitor stands upright
// 198 mm back from the base's front edge, with a deeper bezel above it than
// below. The top unit leans its title panel out over the player up to 2.51 m.
const double _cabFront = _stageFront + 0.60;
const double _cabBack = _cabFront + 0.585;
const double _cabHalfWidth = 0.74;
const double _deckY = 0.75; // where the control panel starts sloping back
const double _screenZ = _cabFront + 0.198;
const double _screenW = 1.218, _screenH = 0.685;
const double _screenBottom = 1.026;
const double _monitorBottom = 0.939, _monitorTop = 1.884;
const double _topUnitY = 2.07, _cabTop = 2.51;

/// The cabinet's game screen, in its own pixels.
const Size kCabinetScreen = Size(1280, 720);

/// Where the lane field sits on that screen: the left edge of lane 0 and the
/// receptor line, for the 1P side (Singles) and centred (Doubles).
const double kCabinetReceptorY = 117;
double cabinetLaneLeft(int columnCount) => columnCount > 4 ? 256 : 88;

/// The canvas the chart paints into on that screen: the cabinet's own lane
/// panel, which centres the lanes as the chart painter does.
Size cabinetLaneSize(int columnCount) =>
    Size(columnCount > 4 ? 860 : 640, kCabinetScreen.height);

/// Panel centres in panel units, matching the parity solver's stage.
const List<(double, double)> _singles = [(-1, 0), (0, -1), (0, 1), (1, 0)];
const List<(double, double)> _doubles = [
  (-2.5, 0),
  (-1.5, -1),
  (-1.5, 1),
  (-0.5, 0),
  (0.5, 0),
  (1.5, -1),
  (1.5, 1),
  (2.5, 0),
];

/// Arrow heading per panel (L D U R), 0 pointing up the pad.
const List<double> _arrowTurn = [-math.pi / 2, math.pi, 0, math.pi / 2];

/// The arrow acrylic as a fan of triangles about a point in its head, which
/// sees the whole outline.
final List<(double, double)> _arrow = arrowPolygon();

typedef _Rgb = (double, double, double);

_Rgb _rgb(Color c) => (c.r * 255, c.g * 255, c.b * 255);
_Rgb _mix(_Rgb a, _Rgb b, double t) => (
      a.$1 + (b.$1 - a.$1) * t,
      a.$2 + (b.$2 - a.$2) * t,
      a.$3 + (b.$3 - a.$3) * t,
    );
_Rgb _scale(_Rgb a, double s) => (a.$1 * s, a.$2 * s, a.$3 * s);
int _argb(_Rgb c) =>
    0xFF000000 |
    (c.$1.round().clamp(0, 255).toInt() << 16) |
    (c.$2.round().clamp(0, 255).toInt() << 8) |
    c.$3.round().clamp(0, 255).toInt();

const _Rgb _jacket = (184, 190, 202);
const _Rgb _pants = (116, 124, 140);
const _Rgb _skin = (208, 212, 222);
const _Rgb _shoe = (244, 244, 246);
const _Rgb _padBase = (34, 32, 40);
const _Rgb _panelArrow = (48, 46, 58);
const _Rgb _panelPlate = (78, 76, 88);
const _Rgb _panelCentre = (62, 60, 72);
const _Rgb _arrowIdle = (118, 116, 136);
const _Rgb _bracket = (58, 56, 66);
const _Rgb _lamp = (236, 242, 255);
const _Rgb _chrome = (170, 172, 184);
const _Rgb _white = (255, 255, 255);
const _Rgb _cabBody = (72, 70, 80);
const _Rgb _cabTrim = (150, 132, 92);
const _Rgb _cabDeck = (46, 44, 54);
const _Rgb _marquee = (255, 214, 140);
const _Rgb _sideLed = (150, 206, 255);
final _Rgb _leftC = _rgb(kLeftFootColor);
final _Rgb _rightC = _rgb(kRightFootColor);

/// The field's own backdrop: the dancer replaces [ChartPainter]'s background,
/// so it paints the same gradient and fades into its bottom colour.
const Color _bgTop = Color(0xFF11151C);
const Color _bgBottom = Color(0xFF080A0E);
final _Rgb _fog = _rgb(const Color(0xFF0C0F15));

/// How far everything fades toward the backdrop, so the arrows stay the thing
/// you read.
const double _dim = 0.42;

class _V {
  const _V(this.x, this.y, this.z);
  final double x, y, z;
  _V operator +(_V o) => _V(x + o.x, y + o.y, z + o.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V operator *(double s) => _V(x * s, y * s, z * s);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;
  _V cross(_V o) => _V(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  _V get unit {
    final l = length;
    return l < 1e-9 ? this : this * (1 / l);
  }
}

const _V _up = _V(0, 1, 0);
const _V _xAxis = _V(1, 0, 0);
const _V _zAxis = _V(0, 0, 1);
_V _fwdOf(double yaw) => _V(math.sin(yaw), 0, math.cos(yaw));
_V _rightOf(double yaw) => _V(math.cos(yaw), 0, -math.sin(yaw));
double _lerp(double a, double b, double t) => a + (b - a) * t;
double _smooth(double t) {
  t = t.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _angLerp(double a, double b, double t) {
  final d = b - a;
  return a + math.atan2(math.sin(d), math.cos(d)) * t;
}

/// First index whose value is greater than [x].
int _upper(List<double> a, double x) {
  var lo = 0, hi = a.length;
  while (lo < hi) {
    final m = (lo + hi) >> 1;
    if (a[m] <= x) {
      lo = m + 1;
    } else {
      hi = m;
    }
  }
  return lo;
}

/// How a [DancerForm] moves the body, as multipliers on the standard motion.
class _Style {
  const _Style(this.lift, this.air, this.torsoTurn, this.shoulderFollow,
      this.dip, this.weightShift, this.armSwing);

  /// Foot height off the panel, and how early it leaves for the next one.
  final double lift, air;

  /// How much of the hips' turn the shoulders take.
  final double torsoTurn;

  /// How much of the hips' travel the shoulders take (singles).
  final double shoulderFollow;
  final double dip, weightShift, armSwing;

  static _Style of(DancerForm form) => switch (form) {
        DancerForm.standard => const _Style(1, 1, 0.55, 1, 1, 0.28, 0.05),
        DancerForm.minimal => const _Style(0.45, 0.75, 0, 0.15, 0.3, 0.1, 0),
        DancerForm.exaggerated => const _Style(2.4, 1.5, 1, 1, 2.5, 0.45, 0.22),
      };
}

/// A foot arriving somewhere: a step, or a move the solve made without one.
class _Step {
  const _Step(this.t, this.x, this.z, this.bracketYaw, this.holdEnd,
      this.stepped, this.cols);
  final double t;
  final double x, z; // panel units
  final double? bracketYaw; // heel-to-toe heading when bracketing
  final double holdEnd; // the foot stays down until here
  final bool stepped;
  final List<int> cols; // panels under the foot
}

/// When a foot planted at [cur] leaves for [next]: no earlier than the hold
/// under it lets go, and only as early as the reach needs. A jack is a quick
/// tap, a crossover a long swing.
double _liftAt(_Step cur, _Step next, _Style st) {
  final dx = next.x - cur.x, dz = next.z - cur.z;
  final d = math.sqrt(dx * dx + dz * dz);
  final free = math.max(cur.holdEnd, cur.t + 0.04);
  final airT = math.min((0.11 + 0.08 * d).clamp(0.11, 0.3) * st.air,
      math.max(0.03, next.t - free));
  return math.max(free, next.t - airT);
}

/// The stances reworked into what the body needs: per-foot step events, the
/// body's turn at each stance, and when each panel is pressed. Built once per
/// solve and kept with the motion state carried between frames.
class _Track {
  _Track(this.stances, List<StepNote> notes, this.columnCount, this.form,
      [List<ShockEvasion>? plannedShocks])
      : style = _Style.of(form) {
    sourcePlans = plannedShocks;
    final layout = columnCount > 4 ? _doubles : _singles;
    times = [for (final s in stances) s.second];

    shockPlans = plannedShocks ??
        planShockEvasions(
            notes, stances, columnCount == 4 ? Modes.singles : Modes.doubles);
    final holdEnds = <double, Map<int, double>>{};
    for (final n in notes) {
      if (n.isHold && n.endSecond != null) {
        (holdEnds[n.second] ??= {})[n.col] = n.endSecond!;
      }
    }

    // The same turn the dancing-feet pad shows; doubles stays square.
    var last = 0.0;
    var fromL = -1, fromR = -1;
    for (final s in stances) {
      final l = s.leftHeel == -1 ? s.leftToe : s.leftHeel;
      final r = s.rightHeel == -1 ? s.rightToe : s.rightHeel;
      last = columnCount > 4 || l == -1 || r == -1
          ? 0
          : stepTurn(last, fromL, fromR, l, r);
      turns.add(last);
      fromL = l;
      fromR = r;
    }

    for (final foot in ParityFoot.values) {
      final out = foot == ParityFoot.left ? left : right;
      final otherFoot =
          foot == ParityFoot.left ? ParityFoot.right : ParityFoot.left;
      String? prevKey;
      for (final s in stances) {
        final heel = foot == ParityFoot.left ? s.leftHeel : s.rightHeel;
        final toe = foot == ParityFoot.left ? s.leftToe : s.rightToe;
        final cols = [if (heel != -1) heel, if (toe != -1 && toe != heel) toe];
        if (cols.isEmpty) continue;
        final key = cols.join(',');
        final hit = [
          for (final c in cols)
            if (s.stepped.contains(c)) c
        ];
        if (hit.isEmpty && key == prevKey) continue;
        prevKey = key;
        double x, z;
        double? bracketYaw;
        if (cols.length == 2) {
          final a = layout[cols[0]], b = layout[cols[1]];
          x = (a.$1 + b.$1) / 2;
          z = (a.$2 + b.$2) / 2;
          bracketYaw = math.atan2(b.$1 - a.$1, b.$2 - a.$2);
        } else {
          final other = s.columnsFor(otherFoot);
          final spot =
              formSpot(form, cols[0], foot, other.length == 1 ? other[0] : -1);
          x = layout[cols[0]].$1 + spot.dx;
          z = layout[cols[0]].$2 + spot.dy;
        }
        var holdEnd = s.second;
        for (final c in hit) {
          final e = holdEnds[s.second]?[c];
          if (e != null && e > holdEnd) holdEnd = e;
        }
        out.add(
            _Step(s.second, x, z, bracketYaw, holdEnd, hit.isNotEmpty, cols));
      }
    }

    // A panel is pressed from a foot landing on it until that foot lifts.
    for (int c = 0; c < columnCount; c++) {
      pressed.add([[], []]);
    }
    for (final (f, ev) in [(0, left), (1, right)]) {
      for (int k = 0; k < ev.length; k++) {
        final end = k + 1 < ev.length ? _liftAt(ev[k], ev[k + 1], style) : 1e9;
        for (final c in ev[k].cols) {
          if (c < columnCount) pressed[c][f].add((ev[k].t, end));
        }
      }
    }

    final cx = columnCount > 4
        ? (left.isNotEmpty && left.first.x > 0 ? 1.5 : -1.5)
        : 0.0;
    restLeft = _Step(-1e9, cx - 0.42, 0, null, -1e9, false, const []);
    restRight = _Step(-1e9, cx + 0.42, 0, null, -1e9, false, const []);
  }

  final List<ParityStance> stances;
  final int columnCount;
  final DancerForm form;
  final _Style style;
  late final List<ShockEvasion> shockPlans;
  List<ShockEvasion>? sourcePlans;
  late final List<double> times;
  final List<double> turns = [];
  final List<_Step> left = [], right = [];
  // Per column, per foot: (from, to) while that foot is on the panel.
  final List<List<List<(double, double)>>> pressed = [];
  late final _Step restLeft, restRight;

  // Motion carried between frames.
  double yaw = 0;
  double? lastT;

  /// Eases the body's turn toward the stance at [t]; snaps on a seek.
  void advance(double t) {
    final i = _upper(times, t + 0.05) - 1;
    final turn = i >= 0 ? turns[i] : 0.0;
    final dt = lastT == null ? -1.0 : t - lastT!;
    yaw = dt < 0 || dt > 0.3
        ? turn
        : yaw + (turn - yaw) * (1 - math.exp(-dt * 12));
    lastT = t;
  }

  /// Is a foot on panel [col] at [t]? Not one that's evading a shock.
  bool lit(int col, double t) {
    for (final foot in ParityFoot.values) {
      if ((shockFor(shockPlans, foot, t)?.amount(foot, t) ?? 0) > 0.99) {
        continue;
      }
      final spans = pressed[col][foot.index];
      var lo = 0, hi = spans.length;
      while (lo < hi) {
        final m = (lo + hi) >> 1;
        if (spans[m].$1 <= t) {
          lo = m + 1;
        } else {
          hi = m;
        }
      }
      if (lo > 0 && t < spans[lo - 1].$2) return true;
    }
    return false;
  }
}

/// One foot at a moment: planted on its last panel, or partway along the arc
/// that lands it on the next note.
class _FootAt {
  double x = 0, z = 0, h = 0, air = 0, e = 0, tilt = 0, landAge = 0;
  // Where the foot's next step lands.
  double nx = 0, nz = 0;
  double? yawA, yawB;
  bool stepped = false, bracket = false;
}

_FootAt _footAt(List<_Step> ev, _Step rest, double t, _Style st) {
  var lo = 0, hi = ev.length - 1, k = -1;
  while (lo <= hi) {
    final m = (lo + hi) >> 1;
    if (ev[m].t <= t) {
      k = m;
      lo = m + 1;
    } else {
      hi = m - 1;
    }
  }
  final cur = k >= 0 ? ev[k] : rest;
  final next = k + 1 < ev.length ? ev[k + 1] : null;
  final f = _FootAt()
    ..x = cur.x
    ..z = cur.z
    ..nx = next?.x ?? cur.x
    ..nz = next?.z ?? cur.z
    ..yawA = cur.bracketYaw
    ..yawB = cur.bracketYaw
    ..landAge = t - cur.t
    ..stepped = cur.stepped
    ..bracket = cur.bracketYaw != null;
  if (next == null) return f;
  final lift = _liftAt(cur, next, st);
  if (t < lift) return f;
  final dx = next.x - cur.x, dz = next.z - cur.z;
  final d = math.sqrt(dx * dx + dz * dz);
  final s = ((t - lift) / math.max(1e-3, next.t - lift)).clamp(0.0, 1.0);
  final e = _smooth(s), arc = math.sin(math.pi * s);
  return f
    ..x = _lerp(cur.x, next.x, e)
    ..z = _lerp(cur.z, next.z, e)
    ..h =
        (d < 0.01 ? 0.035 : (0.05 + 0.06 * d).clamp(0.05, 0.2)) * st.lift * arc
    ..air = arc
    ..e = e
    ..yawB = next.bracketYaw
    ..tilt = arc * (d < 0.01 ? 0.15 : 0.4) * math.min(1.0, st.lift)
    ..bracket = e < 0.5 ? cur.bracketYaw != null : next.bracketYaw != null;
}

/// A knee bounce for a moment after landing.
double _landDip(_FootAt f) => f.stepped && f.landAge >= 0 && f.landAge < 0.16
    ? math.sin(math.pi * f.landAge / 0.16)
    : 0;

/// Two-bone reach from [root] toward [target], bending toward [pole]. Returns
/// the joint and where the chain actually ends (short of an unreachable target).
(_V, _V) _ik(_V root, _V target, double a, double b, _V pole) {
  final d = target - root;
  var l = d.length;
  final dn = l > 1e-6 ? d * (1 / l) : const _V(0, -1, 0);
  l = l.clamp((a - b).abs() + 1e-3, (a + b) * 0.999);
  final x = (a * a - b * b + l * l) / (2 * l);
  final h = math.sqrt(math.max(0.0, a * a - x * x));
  var pd = pole - dn * pole.dot(dn);
  pd = pd.length < 1e-6 ? _zAxis : pd.unit;
  return (root + dn * x + pd * h, root + dn * l);
}

class _Camera {
  _Camera(this.eye, this.target, this.cx, this.cy, this.focal)
      : f = (target - eye).unit {
    r = _up.cross(f).unit;
    u = f.cross(r);
  }
  final _V eye, target, f;
  late final _V r, u;
  final double cx, cy, focal;

  /// Screen position and depth from behind the player. Left stays left.
  (double, double, double)? project(_V p) {
    final v = p - eye;
    final z = v.dot(f);
    if (z < 0.08) return null;
    return (cx + v.dot(r) / z * focal, cy - v.dot(u) / z * focal, z);
  }
}

class _Face {
  _Face(this.pts, this.depth, this.color, this.layer, this.decals);
  final List<Offset> pts;
  final double depth;
  final int color;
  final int layer; // 0 stage, 1 panels, 2 everything standing on them
  final List<(List<_V>, _Rgb, bool)>? decals; // lit triangles on this face
}

class _Scene {
  _Scene(this.cam) {
    light = (cam.f * -0.55 + const _V(0.35, 0.9, 0.1)).unit;
  }
  final _Camera cam;
  late final _V light;
  final List<_Face> faces = [];

  _Rgb _shade(_Rgb c, _V n, double depth, bool emissive, {bool lit = false}) {
    // A lamp shines at full strength, past the fog and the dimming.
    if (lit) return c;
    var col = c;
    if (!emissive) {
      final nn = n.unit;
      col = _scale(
          c,
          0.34 +
              0.62 * math.max(0.0, nn.dot(light)) +
              0.1 * math.max(0.0, nn.y));
    }
    col = _mix(col, _fog, ((depth - 3.2) / 9).clamp(0.0, 0.55));
    return _mix(col, _fog, _dim);
  }

  /// A flat convex polygon (three or more corners, in order).
  void quad(List<_V> p, _V n, _Rgb c,
      {int layer = 2,
      bool emissive = false,
      bool lit = false,
      List<(List<_V>, _Rgb, bool)>? decals}) {
    var centre = p[0];
    for (int i = 1; i < p.length; i++) {
      centre = centre + p[i];
    }
    centre = centre * (1 / p.length);
    if (n.dot(cam.eye - centre) <= 0) return;
    final pts = <Offset>[];
    var depth = 0.0;
    for (final v in p) {
      final s = cam.project(v);
      if (s == null) return;
      pts.add(Offset(s.$1, s.$2));
      depth += s.$3;
    }
    depth /= p.length;
    faces.add(_Face(pts, depth, _argb(_shade(c, n, depth, emissive, lit: lit)),
        layer, decals));
  }

  void box(_V c, _V ax, _V ay, _V az, double hx, double hy, double hz, _Rgb col,
      {int layer = 2, bool emissive = false}) {
    final x = ax * hx, y = ay * hy, z = az * hz;
    _V p(double a, double b, double d) => c + x * a + y * b + z * d;
    void q(List<_V> pts, _V n) =>
        quad(pts, n, col, layer: layer, emissive: emissive);
    q([p(1, -1, -1), p(1, 1, -1), p(1, 1, 1), p(1, -1, 1)], ax);
    q([p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1)], ax * -1);
    q([p(-1, 1, -1), p(-1, 1, 1), p(1, 1, 1), p(1, 1, -1)], ay);
    q([p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1)], ay * -1);
    q([p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1)], az);
    q([p(-1, -1, -1), p(-1, 1, -1), p(1, 1, -1), p(1, -1, -1)], az * -1);
  }

  /// A box stretched from [p0] to [p1]: a bone, a bar, a post.
  void limb(_V p0, _V p1, double hw, double hd, _Rgb col, _V ref) {
    final axis = p1 - p0;
    final l = axis.length;
    if (l < 1e-4) return;
    final y = axis * (1 / l);
    var x = y.cross(ref);
    if (x.length < 1e-3) x = y.cross(_xAxis);
    x = x.unit;
    box((p0 + p1) * 0.5, x, y, x.cross(y), hw, l / 2, hd, col);
  }

  void tube(_V start, _V end, double radius, _Rgb color) {
    final axis = (end - start).unit;
    var side = axis.cross(_up);
    if (side.length < 0.01) side = axis.cross(_xAxis);
    side = side.unit;
    final forward = side.cross(axis).unit;
    rings(
        start,
        side,
        axis,
        forward,
        [
          (0.0, radius, radius),
          ((end - start).length, radius, radius),
        ],
        color);
  }

  /// Elliptical rings give the silhouette rounded shoulders and tapered forms
  /// without textures or a second renderer.
  void rings(_V centre, _V side, _V axis, _V forward,
      List<(double, double, double)> profile, _Rgb color) {
    const count = 12;
    _V point(int ring, int segment) {
      final (height, width, depth) = profile[ring];
      final angle = segment / count * math.pi * 2;
      return centre +
          axis * height +
          side * (math.cos(angle) * width) +
          forward * (math.sin(angle) * depth);
    }

    for (var j = 0; j < profile.length - 1; j++) {
      for (var i = 0; i < count; i++) {
        final a = point(j, i), b = point(j + 1, i);
        final c = point(j + 1, i + 1), d = point(j, i + 1);
        quad([a, b, c, d], (b - a).cross(c - a).unit, color);
      }
    }
  }

  /// Screen area the faces cover, so a layer drawn under them stays small.
  Rect get bounds {
    var l = double.infinity, t = double.infinity;
    var r = -double.infinity, b = -double.infinity;
    for (final f in faces) {
      for (final p in f.pts) {
        if (p.dx < l) l = p.dx;
        if (p.dx > r) r = p.dx;
        if (p.dy < t) t = p.dy;
        if (p.dy > b) b = p.dy;
      }
    }
    return l > r ? Rect.zero : Rect.fromLTRB(l, t, r, b).inflate(2);
  }

  void draw(Canvas canvas) {
    faces.sort((a, b) =>
        a.layer != b.layer ? a.layer - b.layer : b.depth.compareTo(a.depth));
    final pos = <double>[];
    final cols = <int>[];
    void tri(Offset a, Offset b, Offset c, int col) {
      pos.addAll([a.dx, a.dy, b.dx, b.dy, c.dx, c.dy]);
      cols.addAll([col, col, col]);
    }

    for (final f in faces) {
      final p = f.pts;
      for (int i = 1; i + 1 < p.length; i++) {
        tri(p[0], p[i], p[i + 1], f.color);
      }
      for (final (world, rgb, lit)
          in f.decals ?? const <(List<_V>, _Rgb, bool)>[]) {
        final col = _argb(_shade(rgb, _up, f.depth, true, lit: lit));
        for (int i = 0; i + 2 < world.length; i += 3) {
          final a = cam.project(world[i]),
              b = cam.project(world[i + 1]),
              c = cam.project(world[i + 2]);
          if (a == null || b == null || c == null) continue;
          tri(Offset(a.$1, a.$2), Offset(b.$1, b.$2), Offset(c.$1, c.$2), col);
        }
      }
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.fromList(pos),
      colors: Int32List.fromList(cols),
    );
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
  }
}

/// Where every joint is at one moment.
class _Pose {
  _Pose(this.yaw);
  final double yaw;
  late final double torsoYaw;
  late final _V pelvis, chest, head;
  final Map<ParityFoot, ({_V centre, _V side, _V up, _V fwd, double len})>
      shoes = {};
  final Map<ParityFoot, _FootAt> feet = {};
  final Map<ParityFoot, ({_V hip, _V knee, _V ankle})> legs = {};
  final Map<ParityFoot, ({_V shoulder, _V elbow, _V hand})> arms = {};

  /// Where each hand closes round the bar: the tube's centre there, its
  /// direction, and the side the palm is on.
  final Map<ParityFoot, ({_V at, _V axis, _V palm})> grips = {};
}

_Pose _pose(_Track tr, double t, _Rig rig) {
  final st = tr.style;
  final bar = rig.bar, k = rig.k;
  final thigh = _thigh * k, shin = _shin * k;
  final upperArm = _upperArm * k, foreArm = _foreArm * k;
  final pose = _Pose(tr.yaw);
  final yaw = tr.yaw, fwd = _fwdOf(yaw), side = _rightOf(yaw);
  final ankles = <ParityFoot, _V>{};
  for (final foot in ParityFoot.values) {
    final isLeft = foot == ParityFoot.left;
    final f = _footAt(isLeft ? tr.left : tr.right,
        isLeft ? tr.restLeft : tr.restRight, t, st);
    final evasion = shockFor(tr.shockPlans, foot, t);
    var dodge = evasion?.amount(foot, t) ?? 0.0;
    if (evasion != null && dodge > 0) {
      final target = evasion.pose(foot, rig.shoe / _u, t);
      final role = evasion.of(foot)!.role;
      final out = evasion.exit(foot, t);
      if (out > 0) {
        // Off the metal onto the next arrow: the step's arc starts from here.
        final e = _smooth(out), arc = math.sin(math.pi * out);
        final d = math
            .sqrt(math.pow(f.nx - target.x, 2) + math.pow(f.nz - target.y, 2));
        f
          ..x = _lerp(target.x, f.nx, e)
          ..z = _lerp(target.y, f.nz, e)
          ..h = target.lift * (1 - e) +
              (0.05 + 0.06 * d).clamp(0.05, 0.2) * st.lift * arc
          ..tilt = target.tilt * (1 - e) + arc * 0.4 * math.min(1.0, st.lift)
          ..air = math.max(arc, target.airborne ? 1 - e : 0)
          ..e = e;
        dodge = 1 - e;
      } else {
        if (role != ShockRole.air) {
          f.x = _lerp(f.x, target.x, dodge);
          f.z = _lerp(f.z, target.y, dodge);
        }
        f.h = _lerp(f.h, target.lift, dodge);
        f.tilt = _lerp(f.tilt, target.tilt, dodge);
        f.air = _lerp(f.air, target.airborne ? 1 : 0, dodge);
        if (role == ShockRole.centre || role == ShockRole.hover) {
          // A launch springs off the arrows like a step-jump, so the body
          // leaves the pad with the feet before landing on the metal.
          final arc = math.sin(math.pi * evasion.hop(t));
          f.h += 0.08 * arc;
          f.air = math.max(f.air, arc);
          if (role == ShockRole.centre && t >= evasion.land) {
            f
              ..stepped = true
              ..landAge = t - evasion.land;
          }
        }
      }
      f.bracket = dodge < 0.5 && f.bracket;
    }
    final splay = yaw * (1 - dodge) + (isLeft ? -0.16 : 0.16);
    final ff = _fwdOf(_angLerp(f.yawA ?? splay, f.yawB ?? splay, f.e));
    // Toes dip while the foot is in the air.
    final cp = math.cos(f.tilt), sp = math.sin(f.tilt);
    final shoeF = _V(ff.x * cp, -sp, ff.z * cp).unit;
    final shoeS = _up.cross(shoeF).unit;
    final shoeU = shoeF.cross(shoeS);
    final centre = _V(f.x * _u, _padY + f.h + 0.04, f.z * _u);
    pose.feet[foot] = f;
    pose.shoes[foot] = (
      centre: centre,
      side: shoeS,
      up: shoeU,
      fwd: shoeF,
      len: rig.shoe / 2 * (f.bracket ? 1.18 : 1),
    );
    ankles[foot] = centre + shoeF * (-0.26 * rig.shoe) + shoeU * 0.045;
  }
  final fl = pose.feet[ParityFoot.left]!, fr = pose.feet[ParityFoot.right]!;
  final ankL = ankles[ParityFoot.left]!, ankR = ankles[ParityFoot.right]!;

  // Hips ride over whichever foot is carrying the weight, and sit back toward
  // the bar when holding it.
  final w = 0.5 + st.weightShift * (fl.air - fr.air);
  final back = bar ? 0.05 : 0.0;
  var px = _lerp(ankL.x, ankR.x, w) - fwd.x * back;
  var pz = _lerp(ankL.z, ankR.z, w) - fwd.z * back;
  final dl = _landDip(fl), dr = _landDip(fr);
  final dip = (0.03 * math.max(dl, dr) + 0.02 * math.min(dl, dr)) * st.dip;
  final jump =
      math.min(fl.air, fr.air) > 0.2 ? math.min(fl.h, fr.h) * 0.9 : 0.0;
  var py = _padY + 0.88 * k - dip + jump;
  // Never higher than both legs can reach, so the feet stay on the pad.
  final reach = (thigh + shin) * 0.985;
  for (final (a, sgn) in [(ankL, -1.0), (ankR, 1.0)]) {
    final hx = px + side.x * 0.095 * k * sgn,
        hz = pz + side.z * 0.095 * k * sgn;
    final hd = math.sqrt((hx - a.x) * (hx - a.x) + (hz - a.z) * (hz - a.z));
    py = math.min(py, a.y + math.sqrt(math.max(0.01, reach * reach - hd * hd)));
  }
  final pelvis = _V(px, py, pz);
  pose.pelvis = pelvis;

  for (final (foot, sgn) in [
    (ParityFoot.left, -1.0),
    (ParityFoot.right, 1.0)
  ]) {
    final hip = pelvis + side * (0.095 * k * sgn);
    final pole = (fwd + pose.shoes[foot]!.fwd * 0.6 + side * (0.15 * sgn)).unit;
    final (knee, ankle) = _ik(hip, ankles[foot]!, thigh, shin, pole);
    pose.legs[foot] = (hip: hip, knee: knee, ankle: ankle);
  }

  // The shoulders take only part of the hips' turn and travel: in MINIMAL
  // they stay square over the middle of the pad while the legs do the work.
  // On doubles the body has to travel between the pads.
  final torsoYaw = (yaw * st.torsoTurn).clamp(-0.9, 0.9);
  pose.torsoYaw = torsoYaw;
  final tf = _fwdOf(torsoYaw), ts = _rightOf(torsoYaw);
  final follow = tr.columnCount > 4 ? 1.0 : st.shoulderFollow;
  final over = _V(_lerp(0, px, follow), py, _lerp(-back, pz, follow));
  // Holding the bar, the chest leans back further the further the pelvis is
  // from it, so the hands can keep hold.
  final lean = bar
      ? -0.08 - (pz - _barZ - 0.45).clamp(0.0, 0.5) * 0.45 + dip * 0.4
      : 0.02 + dip * 0.4;
  var chest = over + tf * lean + _V(0, 0.46 * k - dip * 0.4, 0);
  // Grips belong to the stage, not the moving pelvis. On doubles the player
  // holds the inner side of each bar; neither hand slides during a transfer.
  // EDGES takes the bend halfway round; overhand sits on the tube, underhand
  // under it.
  final doubles = tr.columnCount > 4;
  final edges = rig.spot == GripSpot.edges;
  const bend = math.pi / 4;
  final along = edges
      ? _barHalfWidth - _barBendRadius + _barBendRadius * math.cos(bend)
      : _gripHalfWidth;
  final drop = edges ? _barBendRadius * (1 - math.sin(bend)) : 0.0;
  final overhand = rig.grip == BarGrip.overhand;
  ({_V at, _V axis, _V palm}) hold(double sign) {
    final d = doubles ? -sign : sign;
    final out =
        edges ? _V(d * math.cos(bend), math.sin(bend), 0) : const _V(0, 1, 0);
    return (
      at: _V((doubles ? sign * 1.5 * _u : 0) + d * along, _barY - drop, _barZ),
      axis: out.cross(_zAxis).unit,
      palm: overhand ? out : out * -1,
    );
  }

  // The wrist sits off the palm's side of the bar, toward the body.
  _V grip(double sign) {
    final h = hold(sign);
    return h.at + h.palm * 0.04 + _zAxis * 0.03;
  }

  final armReach = (upperArm + foreArm) * 0.97;
  if (bar) {
    // Lean the shoulders into the reachable intersection of both arm chains.
    for (var pass = 0; pass < 12; pass++) {
      for (final sign in [-1.0, 1.0]) {
        final shoulder = chest + ts * (0.2 * k * sign) + _V(0, 0.06 * k, 0);
        final delta = shoulder - grip(sign);
        if (delta.length > armReach) {
          chest = chest - delta.unit * (delta.length - armReach);
        }
      }
    }
  }
  pose.chest = chest;
  pose.head = chest + tf * 0.02 + _V(0, 0.27 * k, 0);
  for (final (foot, sgn) in [
    (ParityFoot.left, -1.0),
    (ParityFoot.right, 1.0)
  ]) {
    final shoulder = chest + ts * (0.2 * k * sgn) + _V(0, 0.06 * k, 0);
    if (bar) {
      final target = grip(sgn);
      // Overhand flares the elbows out; underhand tucks them down by the ribs.
      final pole = rig.grip == BarGrip.overhand
          ? (tf * -0.4 + ts * (0.7 * sgn) + const _V(0, -0.3, 0)).unit
          : (tf * -0.3 + ts * (0.15 * sgn) + const _V(0, -0.9, 0)).unit;
      final (elbow, _) = _ik(shoulder, target, upperArm, foreArm, pole);
      pose.grips[foot] = hold(sgn);
      pose.arms[foot] = (shoulder: shoulder, elbow: elbow, hand: target);
    } else {
      // Hands free: hanging by the hips, swinging against the leg on that
      // side the way a walking arm does.
      final mine = foot == ParityFoot.left ? fl : fr;
      final theirs = foot == ParityFoot.left ? fr : fl;
      final swing = st.armSwing * (theirs.air - mine.air) * 2;
      final target = shoulder +
          ts * ((0.06 + st.armSwing * 0.4) * k * sgn) +
          tf * (0.08 + swing) * k +
          _V(0, -0.52 * k, 0);
      final (elbow, hand) = _ik(shoulder, target, upperArm, foreArm, tf * -1);
      pose.arms[foot] = (shoulder: shoulder, elbow: elbow, hand: hand);
    }
  }
  return pose;
}

void _buildPad(_Scene s, _Track tr, double t, double pcx, int base) {
  s.box(_V(pcx * _u, _padY / 2, (_stageFront + _stageBack) / 2), _xAxis, _up,
      _zAxis, 1.5 * _u + _rim, _padY / 2, _stageDepth / 2, _padBase,
      layer: 0);
  const y = _padY + 0.002;
  for (int gx = -1; gx <= 1; gx++) {
    for (int gz = -1; gz <= 1; gz++) {
      final x0 = (pcx + gx - 0.5) * _u + 0.012,
          x1 = (pcx + gx + 0.5) * _u - 0.012;
      final z0 = (gz - 0.5) * _u + 0.012, z1 = (gz + 0.5) * _u - 0.012;
      final panel = switch ((gx, gz)) {
        (-1, 0) => 0,
        (0, -1) => 1,
        (0, 1) => 2,
        (1, 0) => 3,
        _ => -1,
      };
      if (panel < 0) {
        s.quad([
          _V(x0, y, z0),
          _V(x0, y, z1),
          _V(x1, y, z1),
          _V(x1, y, z0)
        ], _up, gx == 0 && gz == 0 ? _panelCentre : _panelPlate, layer: 1);
        continue;
      }
      // An octagonal plate with the corner brackets showing at its cut
      // corners; the arrow on it lights while a foot is on the panel.
      const c = kPanelChamfer * _u;
      for (final (cx, cz, sx, sz) in [
        (x0, z0, 1.0, 1.0),
        (x0, z1, 1.0, -1.0),
        (x1, z1, -1.0, -1.0),
        (x1, z0, -1.0, 1.0),
      ]) {
        final corner = [
          _V(cx, y, cz),
          _V(cx, y, cz + c * sz),
          _V(cx + c * sx, y, cz),
        ];
        s.quad(corner, _up, _bracket, layer: 1);
      }
      final on = base + panel < tr.columnCount && tr.lit(base + panel, t);
      s.quad(
          [
            _V(x0, y, z0 + c),
            _V(x0, y, z1 - c),
            _V(x0 + c, y, z1),
            _V(x1 - c, y, z1),
            _V(x1, y, z1 - c),
            _V(x1, y, z0 + c),
            _V(x1 - c, y, z0),
            _V(x0 + c, y, z0),
          ],
          _up,
          on ? _mix(_panelArrow, _lamp, 0.22) : _panelArrow,
          layer: 1,
          lit: on,
          decals: [
            (
              _arrowTris(
                  (pcx + gx) * _u, gz * _u, _arrowTurn[panel], _u, y + 0.001),
              on ? _lamp : _arrowIdle,
              on,
            )
          ]);
    }
  }
}

List<_V> _arrowTris(double cx, double cz, double turn, double size, double y) {
  final c = math.cos(turn), sn = math.sin(turn);
  final p = [
    for (final (u, v) in _arrow)
      _V(cx + (u * c + v * sn) * size, y, cz + (-u * sn + v * c) * size)
  ];
  final hub = _V(cx + 0.06 * sn * size, y, cz + 0.06 * c * size);
  return [
    for (int i = 0; i < p.length; i++) ...[hub, p[i], p[(i + 1) % p.length]]
  ];
}

/// The cabinet's body round its monitor, centred on [cx]. The screen itself is
/// painted afterwards, through [_screenMatrix].
void _buildCabinet(_Scene s, double cx) {
  const hw = _cabHalfWidth;
  s.box(_V(cx, _deckY / 2, (_cabFront + _cabBack) / 2), _xAxis, _up, _zAxis,
      hw, _deckY / 2, (_cabBack - _cabFront) / 2, _cabBody,
      layer: 0);
  s.quad([
    _V(cx - hw, _deckY, _cabFront),
    _V(cx - hw, _monitorBottom, _screenZ),
    _V(cx + hw, _monitorBottom, _screenZ),
    _V(cx + hw, _deckY, _cabFront),
  ], const _V(0, 0.198, _deckY - _monitorBottom), _cabDeck, layer: 0);
  s.box(
      _V(cx, (_monitorBottom + _monitorTop) / 2, (_screenZ + _cabBack) / 2),
      _xAxis,
      _up,
      _zAxis,
      hw,
      (_monitorTop - _monitorBottom) / 2,
      (_cabBack - _screenZ) / 2,
      _cabBody,
      layer: 0);
  // The top unit overhangs the monitor, its title panel leaning out further.
  s.box(
      _V(cx, (_monitorTop + _topUnitY) / 2, (_screenZ - 0.117 + _cabBack) / 2),
      _xAxis,
      _up,
      _zAxis,
      hw - 0.015,
      (_topUnitY - _monitorTop) / 2,
      (_cabBack - _screenZ + 0.117) / 2,
      _cabTrim,
      layer: 0);
  s.quad([
    _V(cx - 0.70, _topUnitY, _cabFront + 0.222),
    _V(cx - 0.70, _cabTop, _cabFront + 0.021),
    _V(cx + 0.70, _cabTop, _cabFront + 0.021),
    _V(cx + 0.70, _topUnitY, _cabFront + 0.222),
  ], const _V(0, -0.201, -0.44), _marquee, layer: 0, lit: true);
  // The side LEDs, a strip down each side of the screen.
  for (final sign in [-1.0, 1.0]) {
    final x = cx + sign * (_screenW / 2 + 0.045);
    s.quad([
      _V(x - 0.012, _screenBottom, _screenZ - 0.002),
      _V(x - 0.012, _screenBottom + _screenH, _screenZ - 0.002),
      _V(x + 0.012, _screenBottom + _screenH, _screenZ - 0.002),
      _V(x + 0.012, _screenBottom, _screenZ - 0.002),
    ], const _V(0, 0, -1), _sideLed, layer: 0, lit: true);
  }
}

/// Maps the cabinet's screen pixels ([kCabinetScreen]) onto the monitor as
/// [cam] sees it: a flat rectangle through a pinhole is exactly a projective
/// map, so the chart can be painted under it like any other canvas.
Float64List _screenMatrix(_Camera cam, double cx) {
  final tl = _V(cx - _screenW / 2, _screenBottom + _screenH, _screenZ);
  final a = _V(_screenW / kCabinetScreen.width, 0, 0);
  final b = _V(0, -_screenH / kCabinetScreen.height, 0);
  final o = tl - cam.eye;
  final w = [cam.f.dot(a), cam.f.dot(b), cam.f.dot(o)];
  final x = [cam.r.dot(a), cam.r.dot(b), cam.r.dot(o)];
  final y = [cam.u.dot(a), cam.u.dot(b), cam.u.dot(o)];
  double px(int i) => cam.cx * w[i] + cam.focal * x[i];
  double py(int i) => cam.cy * w[i] - cam.focal * y[i];
  return Float64List.fromList([
    px(0), py(0), 0, w[0], //
    px(1), py(1), 0, w[1], //
    0, 0, 1, 0, //
    px(2), py(2), 0, w[2],
  ]);
}

/// Where the cabinet stands: centred between the two stages, so a Singles
/// player on the 1P stage has it off to their right.
double _cabinetX(int columnCount) => columnCount > 4 ? 0 : _stageHalfWidth;

/// Looking down past the player's head at the screen, high enough that the
/// sight line to its bottom edge clears a tall player, framing the lanes
/// across and the screen down to the stage's back row on any shape of field.
_Camera _cabinetCamera(Size size, int columnCount) {
  final cabX = _cabinetX(columnCount);
  double screenX(double px) =>
      cabX + (px / kCabinetScreen.width - 0.5) * _screenW;
  final laneL = screenX(cabinetLaneLeft(columnCount));
  final laneR = screenX(cabinetLaneLeft(columnCount) + 96.0 * columnCount);
  final fx = (laneL + laneR) / 2;
  final eye = _V(fx, 2.6, _stageBack - 0.8);
  final unit = _Camera(eye, _V(fx, 0.9, 0.6), 0, 0, 1);
  final margin = columnCount > 4 ? 0.25 : 0.35;
  final across = [
    _V(laneL - margin, _screenBottom, _screenZ),
    _V(laneR + margin, _screenBottom, _screenZ),
  ];
  final down = [
    _V(fx, _monitorTop, _screenZ),
    _V(fx, _padY, -1.5 * _u),
  ];
  double l = double.infinity, r = -double.infinity;
  double t = double.infinity, b = -double.infinity;
  for (final p in across) {
    final (x, _, _) = unit.project(p)!;
    l = math.min(l, x);
    r = math.max(r, x);
  }
  for (final p in down) {
    final (_, y, _) = unit.project(p)!;
    t = math.min(t, y);
    b = math.max(b, y);
  }
  final focal =
      math.min(size.width / (r - l), size.height * 0.94 / (b - t));
  return _Camera(eye, unit.target, size.width / 2 - focal * (l + r) / 2,
      size.height / 2 - focal * (t + b) / 2, focal);
}

/// Field pixels per cabinet screen pixel at the middle of the screen, so a
/// drag over the cabinet view scrubs at the speed the arrows move under it.
double cabinetScreenScale(Size size, int columnCount) {
  if (size.isEmpty) return 1;
  final cam = _cabinetCamera(size, columnCount);
  final z = (_V(cam.eye.x, _screenBottom + _screenH / 2, _screenZ) - cam.eye)
      .dot(cam.f);
  return cam.focal * (_screenH / kCabinetScreen.height) / z;
}

void _buildBar(_Scene s, List<double> centres) {
  for (final centre in centres) {
    const radius = _barBendRadius;
    const hx = _barHalfWidth;
    for (final sign in [-1.0, 1.0]) {
      s.tube(
          _V(centre + sign * hx, _padY, _barZ),
          _V(centre + sign * hx, _barY - radius, _barZ),
          _barTubeRadius,
          _chrome);
      // The padding extends below both bends, over the narrower upright tube.
      s.tube(
          _V(centre + sign * hx, _barY - radius - 0.10, _barZ),
          _V(centre + sign * hx, _barY - radius, _barZ),
          _barPaddingRadius,
          _chrome);
      for (var i = 0; i < 6; i++) {
        _V point(int j) {
          final angle = j / 6 * math.pi / 2;
          return _V(centre + sign * (hx - radius + radius * math.cos(angle)),
              _barY - radius + radius * math.sin(angle), _barZ);
        }

        s.tube(point(i), point(i + 1), _barPaddingRadius, _chrome);
      }
    }
    s.tube(_V(centre - hx + radius, _barY, _barZ),
        _V(centre + hx - radius, _barY, _barZ), _barPaddingRadius, _chrome);
  }
}

/// Each hand closed round the bar: a band of palm and fingers wrapped from
/// the wrist's side over the far side of the tube, so the grip reads from
/// behind. Drawn solid, after the bar.
void _buildHands(_Scene s, _Pose p, double k) {
  const r = _barPaddingRadius + 0.004, steps = 8;
  // The tube's side facing the camera, away from the body.
  const side = _V(0, 0, -1);
  // From the heel of the palm on the body's side, the back of the hand over
  // the palm's side, then the fingers round the far side to their tips just
  // past the opposite side.
  const from = -0.3 * math.pi, knuckles = 0.25 * math.pi, tips = 1.1 * math.pi;
  for (final g in p.grips.values) {
    final width = 0.085 * k;
    _V ring(double a, double radius, double w) =>
        g.at +
        (g.palm * math.cos(a) + side * math.sin(a)) * radius +
        g.axis * w;
    for (int i = 0; i < steps; i++) {
      final a0 = from + i / steps * (tips - from);
      final a1 = from + (i + 1) / steps * (tips - from);
      final depth = (a0 + a1) / 2 < knuckles ? 0.036 * k : 0.018 * k;
      for (final (rad, out) in [(r + depth, 1.0), (r, -1.0)]) {
        final mid = (a0 + a1) / 2;
        s.quad([
          ring(a0, rad, -width / 2),
          ring(a1, rad, -width / 2),
          ring(a1, rad, width / 2),
          ring(a0, rad, width / 2),
        ], (g.palm * math.cos(mid) + side * math.sin(mid)) * out, _skin);
      }
      for (final w in [-width / 2, width / 2]) {
        s.quad([
          ring(a0, r, w),
          ring(a1, r, w),
          ring(a1, r + depth, w),
          ring(a0, r + depth, w),
        ], g.axis * w.sign, _skin);
      }
    }
  }
}

void _buildDancer(_Scene s, _Pose p, _Rig rig) {
  final k = rig.k;
  List<(double, double, double)> sized(List<(double, double, double)> rings) =>
      [for (final (h, w, d) in rings) (h * k, w * k, d * k)];
  final fwd = _fwdOf(p.yaw), side = _rightOf(p.yaw);
  final tf = _fwdOf(p.torsoYaw), ts = _rightOf(p.torsoYaw);
  for (final foot in ParityFoot.values) {
    final shoe = p.shoes[foot]!, f = p.feet[foot]!;
    final leg = p.legs[foot]!, arm = p.arms[foot]!;
    // About as wide as it is long, the way a trainer is.
    final halfW = rig.shoe * 0.185;
    s.box(shoe.centre, shoe.side, shoe.up, shoe.fwd, halfW, 0.035, shoe.len,
        _shoe);
    // Soles in the foot's colour, flaring as it lands.
    final glow = f.stepped && f.landAge < 0.2 ? 1 - f.landAge / 0.2 : 0.0;
    s.box(
        shoe.centre + shoe.up * -0.033,
        shoe.side,
        shoe.up,
        shoe.fwd,
        halfW + 0.003,
        0.008,
        shoe.len + 0.004,
        _mix(foot == ParityFoot.left ? _leftC : _rightC, _white, glow * 0.5),
        emissive: true);
    s.limb(leg.hip, leg.knee, 0.068 * k, 0.072 * k, _pants, fwd);
    s.limb(leg.knee, leg.ankle, 0.056 * k, 0.06 * k, _pants, fwd);
    s.limb(arm.shoulder, arm.elbow, 0.046 * k, 0.046 * k, _jacket, tf);
    s.limb(arm.elbow, arm.hand, 0.036 * k, 0.036 * k, _skin, tf);
    if (!p.grips.containsKey(foot)) {
      final h = 0.035 * k;
      s.box(arm.hand, _xAxis, _up, _zAxis, h, h, h, _skin);
    }
  }
  s.rings(
      p.pelvis,
      side,
      _up,
      fwd,
      sized([
        (-0.08, 0.10, 0.08),
        (0.0, 0.145, 0.10),
        (0.08, 0.13, 0.09),
      ]),
      _pants);
  final torsoAxis = (p.chest - p.pelvis).unit;
  final torsoSide = ts;
  final torsoForward = torsoSide.cross(torsoAxis).unit;
  final height = (p.chest - p.pelvis).length;
  s.rings(
      p.pelvis,
      torsoSide,
      torsoAxis,
      torsoForward,
      [
        (0.04 * k, 0.13 * k, 0.09 * k),
        (height * 0.4, 0.135 * k, 0.095 * k),
        (height * 0.8, 0.18 * k, 0.11 * k),
        (height, 0.19 * k, 0.105 * k),
        (height + 0.085 * k, 0.13 * k, 0.08 * k),
        (height + 0.10 * k, 0.035 * k, 0.035 * k),
      ],
      _jacket);
  s.tube(p.chest + _V(0, 0.11 * k, 0), p.head + _V(0, -0.09 * k, 0), 0.035 * k,
      _skin);
  final hf = _fwdOf(p.torsoYaw * 0.5), hs = _rightOf(p.torsoYaw * 0.5);
  s.rings(
      p.head,
      hs,
      _up,
      hf,
      sized([
        (-0.105, 0.035, 0.05),
        (-0.075, 0.067, 0.075),
        (0.0, 0.085, 0.095),
        (0.065, 0.08, 0.09),
        (0.10, 0.025, 0.03),
        (0.105, 0.001, 0.001),
      ]),
      _skin);
}

/// Paints the backdrop, the stage and the dancer at the playhead. Replaces the
/// field's background, so it sits under [ChartPainter] in the same stack.
class PadDancerPainter extends CustomPainter {
  PadDancerPainter({
    required this.stances,
    required this.notes,
    required this.playhead,
    required this.columnCount,
    this.visualOffset = 0,
    this.form = DancerForm.standard,
    this.bar = true,
    this.grip = BarGrip.overhand,
    this.gripSpot = GripSpot.middle,
    this.height = kDancerHeight,
    this.shoeSize = kShoeSize,
    this.shockPlans,
    this.cabinet = false,
    this.screen,
  }) : super(repaint: playhead);

  /// Seen from behind at the cabinet, with [screen] (the chart) on its
  /// monitor, instead of the stage alone under a full-field chart.
  final bool cabinet;

  /// Paints the lane field into a [cabinetLaneSize] canvas whose receptor
  /// line sits at [kCabinetReceptorY].
  final CustomPainter? screen;

  /// The solve's stances and the notes it was solved on (turned), for holds.
  final List<ParityStance> stances;
  final List<StepNote> notes;
  final List<ShockEvasion>? shockPlans;
  final ValueListenable<double> playhead;
  final int columnCount;
  final double visualOffset;
  final DancerForm form;

  /// Holding the cabinet's back bar, or hands free without one.
  final bool bar;
  final BarGrip grip;
  final GripSpot gripSpot;

  /// The player's height in metres.
  final double height;

  /// EU shoe size, drawn to scale against the panels.
  final double shoeSize;

  _Rig get _rig => (
        bar: bar,
        grip: grip,
        spot: gripSpot,
        k: height / kDancerHeight,
        shoe: shoeLength(shoeSize),
      );

  static _Track? _cache;

  _Track get _track {
    final c = _cache;
    if (c != null &&
        identical(c.stances, stances) &&
        c.columnCount == columnCount &&
        c.form == form &&
        identical(c.sourcePlans, shockPlans)) {
      return c;
    }
    return _cache = _Track(stances, notes, columnCount, form, shockPlans);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ).createShader(rect));
    if (stances.isEmpty || size.isEmpty) return;

    final tr = _track;
    final t = playhead.value + visualOffset;
    tr.advance(t);
    final pose = _pose(tr, t, _rig);

    final cam = cabinet ? _cabinetCamera(size, columnCount) : _stageCamera(size);
    final chest = cabinet ? null : cam.project(pose.chest);
    if (chest != null) {
      final r = 1.4 / chest.$3 * cam.focal;
      final c = Offset(chest.$1, chest.$2);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              const Color(0xFFFFAA5A).withValues(alpha: 0.12),
              const Color(0xFFFFAA5A).withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }
    _floor(canvas, cam);
    if (cabinet) _paintCabinet(canvas, cam);

    final pad = _Scene(cam);
    if (columnCount > 4) {
      _buildPad(pad, tr, t, -1.5, 0);
      _buildPad(pad, tr, t, 1.5, 4);
    } else {
      _buildPad(pad, tr, t, 0, 0);
      // The 2P stage beside it, never stepped on.
      if (cabinet) _buildPad(pad, tr, t, 2 * _stageHalfWidth / _u, 4);
    }
    pad.draw(canvas);
    // From behind, the body stands over the centre and Up; drawn see-through
    // so every panel and its lamp stays readable through it.
    final body = _Scene(cam);
    _buildDancer(body, pose, _rig);
    canvas.saveLayer(body.bounds, _bodyPaint);
    body.draw(canvas);
    canvas.restore();
    if (bar) {
      final rail = _Scene(cam);
      _buildBar(rail, [
        if (columnCount > 4) ...[-1.5 * _u, 1.5 * _u] else 0.0,
        if (cabinet && columnCount <= 4) 2 * _stageHalfWidth,
      ]);
      rail.draw(canvas);
      final hands = _Scene(cam);
      _buildHands(hands, pose, _rig.k);
      hands.draw(canvas);
    }
  }

  // The camera never moves: the stage stays put and the dancer moves on it.
  _Camera _stageCamera(Size size) {
    const dist = 3.3, pitch = 0.62;
    const target = _V(0, 0.7, 0);
    final eye = target + _V(0, math.sin(pitch), -math.cos(pitch)) * dist;
    // Fit the stage's width on a portrait phone; the height on anything wider.
    final sceneW = columnCount > 4 ? 2.6 : 2.0;
    final focal = math.min(size.height / (2 * math.tan(30 * math.pi / 180)),
        size.width * dist / sceneW);
    return _Camera(eye, target, size.width / 2, size.height * 0.56, focal);
  }

  void _paintCabinet(Canvas canvas, _Camera cam) {
    final cx = _cabinetX(columnCount);
    final body = _Scene(cam);
    _buildCabinet(body, cx);
    body.draw(canvas);

    // The screen is lit: it skips the fog and dimming the room gets.
    canvas.save();
    canvas.transform(_screenMatrix(cam, cx));
    final rect = Offset.zero & kCabinetScreen;
    canvas.clipRect(rect);
    canvas.drawRect(rect, _screenPaint);
    final lanes = cabinetLaneSize(columnCount);
    final left = cabinetLaneLeft(columnCount) -
        (lanes.width - 96.0 * columnCount) / 2;
    // The screen filter behind the lanes, a little wider than them.
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(left + lanes.width / 2, rect.center.dy),
            width: 107.5 * columnCount,
            height: kCabinetScreen.height),
        _filterPaint);
    final chart = screen;
    if (chart != null) {
      canvas.translate(left, 0);
      chart.paint(canvas, lanes);
    }
    canvas.restore();
  }

  static final Paint _screenPaint = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF1C2433), Color(0xFF0E121A)],
    ).createShader(Offset.zero & kCabinetScreen);

  static final Paint _filterPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.5);

  static final Paint _bodyPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.62);

  static final Paint _gridPaint = Paint()
    ..color = const Color(0xFF8C6EFF).withValues(alpha: 0.10)
    ..strokeWidth = 1;

  void _floor(Canvas canvas, _Camera cam) {
    void line(_V a, _V b) {
      final p = cam.project(a), q = cam.project(b);
      if (p == null || q == null) return;
      canvas.drawLine(Offset(p.$1, p.$2), Offset(q.$1, q.$2), _gridPaint);
    }

    for (double x = -4; x <= 4; x += 0.5) {
      line(_V(x, 0, -3), _V(x, 0, 2.4));
    }
    for (double z = -3; z <= 2.4; z += 0.5) {
      line(_V(-4, 0, z), _V(4, 0, z));
    }
  }

  @override
  bool shouldRepaint(PadDancerPainter old) =>
      !identical(old.stances, stances) ||
      !identical(old.shockPlans, shockPlans) ||
      old.columnCount != columnCount ||
      old.visualOffset != visualOffset ||
      old.form != form ||
      old.bar != bar ||
      old.grip != grip ||
      old.gripSpot != gripSpot ||
      old.height != height ||
      old.shoeSize != shoeSize ||
      old.cabinet != cabinet ||
      old.screen != screen ||
      old.playhead != playhead;
}

/// For tests: where each single-panel landing sits relative to its panel's
/// centre (column, x, z in panel units, +z up the pad), and the shoulders'
/// midpoint in metres at each of [times], walked in order like playback.
@visibleForTesting
({
  List<(int, double, double)> landings,
  List<(double, double, double)> shoulders
}) padDancerTrace(List<ParityStance> stances, List<StepNote> notes,
    int columnCount, DancerForm form,
    {bool bar = true, List<double> times = const []}) {
  final tr = _Track(stances, notes, columnCount, form);
  final layout = columnCount > 4 ? _doubles : _singles;
  final landings = [
    for (final s in [...tr.left, ...tr.right])
      if (s.cols.length == 1)
        (
          s.cols[0],
          s.x - layout[s.cols[0]].$1,
          s.z - layout[s.cols[0]].$2,
        )
  ];
  final shoulders = <(double, double, double)>[];
  for (final t in times) {
    tr.advance(t);
    final c = _pose(tr, t, (
          bar: bar,
          grip: BarGrip.overhand,
          spot: GripSpot.middle,
          k: 1,
          shoe: shoeLength(kShoeSize),
        )).chest +
        const _V(0, 0.06, 0);
    shoulders.add((c.x, c.y, c.z));
  }
  return (landings: landings, shoulders: shoulders);
}
