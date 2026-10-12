/// Name: PadDancer
/// Parent: ChartScroller
/// Description: Easter egg. A low-poly dancer on a cabinet pad behind the
/// arrows, hanging on to the back bar and stepping the chart. It reads the same
/// parity stances as [DancingFeet], so the body can never contradict the L/R
/// badges; what the solve doesn't say (foot arcs, hips, knees, arms) is filled
/// in every frame. Triple-tap the dancing-feet pad to toggle it.
///
/// No 3D engine: a few hundred flat-shaded quads, depth-sorted on the CPU and
/// drawn with one [Canvas.drawVertices] call.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'chart_models.dart';
import 'dancing_feet.dart' show stepTurn;
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// World units are metres: x to the player's right, y up, z toward the screen.
const double _u = 0.2794; // one panel
const double _padY = 0.15; // top of the pad
const double _stageDepth = 1.085;
const double _stageFront = 1.5 * _u + 0.035;
const double _stageBack = _stageFront - _stageDepth;
const double _thigh = 0.44, _shin = 0.43, _upperArm = 0.30, _foreArm = 0.30;
// Rail centreline dimensions; the padded outside top is 1.09 m above the
// floor and the outside width is 0.456 m. Geometry notes kept locally.
const double _barTubeRadius = 0.021;
const double _barPaddingRadius = 0.032;
const double _barY = 1.09 - _barPaddingRadius;
const double _barHalfWidth = 0.196;
const double _barBendRadius = 0.125;
const double _gripHalfWidth = 0.055;
const double _barZ = _stageBack + 0.085;

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

/// Arrow outline in half-panel units, pointing up: tip, right wing, shaft
/// right, shaft bottom right, shaft bottom left, shaft left, left wing.
const List<(double, double)> _arrow = [
  (0, 0.9),
  (0.78, 0.08),
  (0.32, 0.08),
  (0.32, -0.8),
  (-0.32, -0.8),
  (-0.32, 0.08),
  (-0.78, 0.08),
];

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
const _Rgb _skin = (184, 190, 202);
const _Rgb _shoe = (244, 244, 246);
const _Rgb _padBase = (34, 32, 40);
const _Rgb _panelArrow = (48, 46, 58);
const _Rgb _panelPlate = (78, 76, 88);
const _Rgb _panelCentre = (62, 60, 72);
const _Rgb _arrowIdle = (96, 92, 112);
const _Rgb _chrome = (170, 172, 184);
const _Rgb _white = (255, 255, 255);
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

/// A foot arriving somewhere: a step, or a move the solve made without one.
class _Step {
  const _Step(
      this.t, this.x, this.z, this.bracketYaw, this.holdEnd, this.stepped);
  final double t;
  final double x, z; // panel units
  final double? bracketYaw; // heel-to-toe heading when bracketing
  final double holdEnd; // the foot stays down until here
  final bool stepped;
}

/// The stances reworked into what the body needs: per-foot step events, the
/// body's turn at each stance, and when each panel was hit. Built once per
/// solve and kept with the motion state carried between frames.
class _Track {
  _Track(this.stances, List<StepNote> notes, this.columnCount) {
    final layout = columnCount > 4 ? _doubles : _singles;
    times = [for (final s in stances) s.second];

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
      String? prevKey;
      for (final s in stances) {
        final heel = foot == ParityFoot.left ? s.leftHeel : s.rightHeel;
        final toe = foot == ParityFoot.left ? s.leftToe : s.rightToe;
        final cols = [if (heel != -1) heel, if (toe != -1) toe];
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
        if (cols.length == 2 && cols[0] != cols[1]) {
          final a = layout[cols[0]], b = layout[cols[1]];
          x = (a.$1 + b.$1) / 2;
          z = (a.$2 + b.$2) / 2;
          bracketYaw = math.atan2(b.$1 - a.$1, b.$2 - a.$2);
        } else {
          x = layout[cols[0]].$1;
          z = layout[cols[0]].$2;
        }
        var holdEnd = s.second;
        for (final c in hit) {
          final e = holdEnds[s.second]?[c];
          if (e != null && e > holdEnd) holdEnd = e;
        }
        out.add(_Step(s.second, x, z, bracketYaw, holdEnd, hit.isNotEmpty));
      }
    }

    for (int c = 0; c < columnCount; c++) {
      hitTimes.add([]);
      hitLeft.add([]);
      holds.add([]);
    }
    for (final s in stances) {
      final lefts = s.columnsFor(ParityFoot.left);
      for (final c in s.stepped) {
        if (c >= columnCount) continue;
        hitTimes[c].add(s.second);
        hitLeft[c].add(lefts.contains(c));
      }
    }
    for (final n in notes) {
      if (n.isHold && n.endSecond != null && n.col < columnCount) {
        holds[n.col].add((n.second, n.endSecond!));
      }
    }

    final cx = columnCount > 4
        ? (left.isNotEmpty && left.first.x > 0 ? 1.5 : -1.5)
        : 0.0;
    restLeft = _Step(-1e9, cx - 0.42, 0, null, -1e9, false);
    restRight = _Step(-1e9, cx + 0.42, 0, null, -1e9, false);
  }

  final List<ParityStance> stances;
  final int columnCount;
  late final List<double> times;
  final List<double> turns = [];
  final List<_Step> left = [], right = [];
  final List<List<double>> hitTimes = [];
  final List<List<bool>> hitLeft = [];
  final List<List<(double, double)>> holds = [];
  late final _Step restLeft, restRight;

  // Motion carried between frames.
  double yaw = 0;
  double camX = 0;
  double? lastT;

  /// How lit a panel is at [t], and by which foot (null = nobody yet).
  (double, bool?) light(int col, double t) {
    final ts = hitTimes[col];
    final i = _upper(ts, t) - 1;
    if (i < 0) return (0, null);
    var v = 0.0;
    final age = t - ts[i];
    if (age < 0.5) v = math.exp(-age * 8);
    for (final h in holds[col]) {
      if (h.$1 <= t && t < h.$2) v = math.max(v, 0.75);
    }
    return (v, hitLeft[col][i]);
  }
}

/// One foot at a moment: planted on its last panel, or partway along the arc
/// that lands it on the next note.
class _FootAt {
  double x = 0, z = 0, h = 0, air = 0, e = 0, tilt = 0, landAge = 0;
  double? yawA, yawB;
  bool stepped = false, bracket = false;
}

_FootAt _footAt(List<_Step> ev, _Step rest, double t) {
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
    ..yawA = cur.bracketYaw
    ..yawB = cur.bracketYaw
    ..landAge = t - cur.t
    ..stepped = cur.stepped
    ..bracket = cur.bracketYaw != null;
  if (next == null) return f;
  final dx = next.x - cur.x, dz = next.z - cur.z;
  final d = math.sqrt(dx * dx + dz * dz);
  // Off the panel no earlier than the hold under it lets go, and only for as
  // long as the reach needs: a jack is a quick tap, a crossover a long swing.
  final free = math.max(cur.holdEnd, cur.t + 0.04);
  final airT = math.min(
      (0.11 + 0.08 * d).clamp(0.11, 0.3), math.max(0.03, next.t - free));
  final lift = math.max(free, next.t - airT);
  if (t < lift) return f;
  final s = ((t - lift) / math.max(1e-3, next.t - lift)).clamp(0.0, 1.0);
  final e = _smooth(s), arc = math.sin(math.pi * s);
  return f
    ..x = _lerp(cur.x, next.x, e)
    ..z = _lerp(cur.z, next.z, e)
    ..h = (d < 0.01 ? 0.035 : (0.05 + 0.06 * d).clamp(0.05, 0.2)) * arc
    ..air = arc
    ..e = e
    ..yawB = next.bracketYaw
    ..tilt = arc * (d < 0.01 ? 0.15 : 0.4)
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
  _Camera(this.eye, _V target, this.cx, this.cy, this.focal)
      : f = (target - eye).unit {
    r = _up.cross(f).unit;
    u = f.cross(r);
  }
  final _V eye, f;
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
  final int layer; // 1 pad, 2 everything standing on it
  final List<(List<_V>, _Rgb)>? decals; // triangles drawn on top of this face
}

class _Scene {
  _Scene(this.cam) {
    light = (cam.f * -0.55 + const _V(0.35, 0.9, 0.1)).unit;
  }
  final _Camera cam;
  late final _V light;
  final List<_Face> faces = [];

  _Rgb _shade(_Rgb c, _V n, double depth, bool emissive) {
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

  void quad(List<_V> p, _V n, _Rgb c,
      {int layer = 2, bool emissive = false, List<(List<_V>, _Rgb)>? decals}) {
    final centre = (p[0] + p[2]) * 0.5;
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
    faces.add(
        _Face(pts, depth, _argb(_shade(c, n, depth, emissive)), layer, decals));
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
      tri(p[0], p[1], p[2], f.color);
      tri(p[0], p[2], p[3], f.color);
      for (final (world, rgb) in f.decals ?? const <(List<_V>, _Rgb)>[]) {
        final col = _argb(_shade(rgb, _up, f.depth, true));
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
  late final _V pelvis, chest, head;
  final Map<ParityFoot, ({_V centre, _V side, _V up, _V fwd, double len})>
      shoes = {};
  final Map<ParityFoot, _FootAt> feet = {};
  final Map<ParityFoot, ({_V hip, _V knee, _V ankle})> legs = {};
  final Map<ParityFoot, ({_V shoulder, _V elbow, _V hand})> arms = {};
}

_Pose _pose(_Track tr, double t) {
  final pose = _Pose(tr.yaw);
  final yaw = tr.yaw, fwd = _fwdOf(yaw), side = _rightOf(yaw);
  final ankles = <ParityFoot, _V>{};
  for (final foot in ParityFoot.values) {
    final isLeft = foot == ParityFoot.left;
    final f = _footAt(
        isLeft ? tr.left : tr.right, isLeft ? tr.restLeft : tr.restRight, t);
    final splay = yaw + (isLeft ? -0.16 : 0.16);
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
      len: f.bracket ? 0.16 : 0.135,
    );
    ankles[foot] = centre + shoeF * -0.07 + shoeU * 0.045;
  }
  final fl = pose.feet[ParityFoot.left]!, fr = pose.feet[ParityFoot.right]!;
  final ankL = ankles[ParityFoot.left]!, ankR = ankles[ParityFoot.right]!;

  // Hips ride over whichever foot is carrying the weight, and sit back toward
  // the bar the player is holding.
  final w = 0.5 + 0.28 * (fl.air - fr.air);
  var px = _lerp(ankL.x, ankR.x, w) - fwd.x * 0.05;
  var pz = _lerp(ankL.z, ankR.z, w) - fwd.z * 0.05;
  final dl = _landDip(fl), dr = _landDip(fr);
  final dip = 0.03 * math.max(dl, dr) + 0.02 * math.min(dl, dr);
  final jump =
      math.min(fl.air, fr.air) > 0.2 ? math.min(fl.h, fr.h) * 0.9 : 0.0;
  var py = _padY + 0.88 - dip + jump;
  // Never higher than both legs can reach, so the feet stay on the pad.
  const reach = (_thigh + _shin) * 0.985;
  for (final (a, sgn) in [(ankL, -1.0), (ankR, 1.0)]) {
    final hx = px + side.x * 0.095 * sgn, hz = pz + side.z * 0.095 * sgn;
    final hd = math.sqrt((hx - a.x) * (hx - a.x) + (hz - a.z) * (hz - a.z));
    py = math.min(py, a.y + math.sqrt(math.max(0.01, reach * reach - hd * hd)));
  }
  final pelvis = _V(px, py, pz);
  pose.pelvis = pelvis;

  for (final (foot, sgn) in [
    (ParityFoot.left, -1.0),
    (ParityFoot.right, 1.0)
  ]) {
    final hip = pelvis + side * (0.095 * sgn);
    final pole = (fwd + pose.shoes[foot]!.fwd * 0.6 + side * (0.15 * sgn)).unit;
    final (knee, ankle) = _ik(hip, ankles[foot]!, _thigh, _shin, pole);
    pose.legs[foot] = (hip: hip, knee: knee, ankle: ankle);
  }

  // Upper body turns a little less than the hips, and leans back further the
  // further the pelvis is from the bar, so the hands can keep hold of it.
  final torsoYaw = (yaw * 0.55).clamp(-0.45, 0.45);
  final tf = _fwdOf(torsoYaw), ts = _rightOf(torsoYaw);
  final fromBar = pz - _barZ;
  final lean = -0.08 - (fromBar - 0.45).clamp(0.0, 0.5) * 0.45 + dip * 0.4;
  var chest = pelvis + tf * lean + _V(0, 0.46 - dip * 0.4, 0);
  // Grips belong to the stage, not the moving pelvis. On doubles the player
  // holds the inner side of each bar; neither hand slides during a transfer.
  final gripWidth =
      tr.columnCount > 4 ? 1.5 * _u - _gripHalfWidth : _gripHalfWidth;
  _V grip(double sign) => _V(gripWidth * sign, _barY, _barZ);
  const armReach = (_upperArm + _foreArm) * 0.97;
  // Lean the shoulders into the reachable intersection of both arm chains.
  // The feet and hips remain driven by the solve, while the hands stay planted.
  for (var pass = 0; pass < 12; pass++) {
    for (final sign in [-1.0, 1.0]) {
      final shoulder = chest + ts * (0.2 * sign) + const _V(0, 0.06, 0);
      final delta = shoulder - grip(sign);
      if (delta.length > armReach) {
        chest = chest - delta.unit * (delta.length - armReach);
      }
    }
  }
  pose.chest = chest;
  pose.head = chest + tf * 0.02 + const _V(0, 0.27, 0);
  for (final (foot, sgn) in [
    (ParityFoot.left, -1.0),
    (ParityFoot.right, 1.0)
  ]) {
    final shoulder = chest + ts * (0.2 * sgn) + const _V(0, 0.06, 0);
    final target = grip(sgn);
    final pole = (tf * -0.4 + ts * (0.7 * sgn) + const _V(0, -0.3, 0)).unit;
    final (elbow, _) = _ik(shoulder, target, _upperArm, _foreArm, pole);
    pose.arms[foot] = (shoulder: shoulder, elbow: elbow, hand: target);
  }
  return pose;
}

void _buildPad(_Scene s, _Track tr, double t, double pcx, int base) {
  s.box(_V(pcx * _u, _padY / 2, (_stageFront + _stageBack) / 2), _xAxis, _up,
      _zAxis, 1.5 * _u + 0.035, _padY / 2, _stageDepth / 2, _padBase,
      layer: 1);
  const y = _padY + 0.002;
  for (int gx = -1; gx <= 1; gx++) {
    for (int gz = -1; gz <= 1; gz++) {
      final x0 = (pcx + gx - 0.5) * _u + 0.012,
          x1 = (pcx + gx + 0.5) * _u - 0.012;
      final z0 = (gz - 0.5) * _u + 0.012, z1 = (gz + 0.5) * _u - 0.012;
      final pts = [_V(x0, y, z0), _V(x0, y, z1), _V(x1, y, z1), _V(x1, y, z0)];
      final panel = switch ((gx, gz)) {
        (-1, 0) => 0,
        (0, -1) => 1,
        (0, 1) => 2,
        (1, 0) => 3,
        _ => -1,
      };
      if (panel < 0) {
        s.quad(pts, _up, gx == 0 && gz == 0 ? _panelCentre : _panelPlate,
            layer: 1);
        continue;
      }
      final (v, isLeft) = tr.light(base + panel, t);
      final fc = isLeft == null ? _white : (isLeft ? _leftC : _rightC);
      s.quad(pts, _up, _mix(_panelArrow, fc, v * 0.45),
          layer: 1,
          emissive: v > 0.02,
          decals: [
            (
              _arrowTris((pcx + gx) * _u, gz * _u, _arrowTurn[panel], _u * 0.4,
                  y + 0.001),
              _mix(_arrowIdle, _mix(fc, _white, 0.25), v),
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
  // Head, then the shaft as two triangles.
  return [p[0], p[1], p[6], p[2], p[3], p[4], p[2], p[4], p[5]];
}

void _buildBar(_Scene s, _Track tr) {
  for (final centre in tr.columnCount > 4 ? [-1.5 * _u, 1.5 * _u] : [0.0]) {
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

void _buildDancer(_Scene s, _Pose p) {
  final fwd = _fwdOf(p.yaw), side = _rightOf(p.yaw);
  final torsoYaw = (p.yaw * 0.55).clamp(-0.45, 0.45);
  final tf = _fwdOf(torsoYaw), ts = _rightOf(torsoYaw);
  for (final foot in ParityFoot.values) {
    final shoe = p.shoes[foot]!, f = p.feet[foot]!;
    final leg = p.legs[foot]!, arm = p.arms[foot]!;
    s.box(shoe.centre, shoe.side, shoe.up, shoe.fwd, 0.05, 0.035, shoe.len,
        _shoe);
    // Soles in the foot's colour, flaring as it lands.
    final glow = f.stepped && f.landAge < 0.2 ? 1 - f.landAge / 0.2 : 0.0;
    s.box(
        shoe.centre + shoe.up * -0.033,
        shoe.side,
        shoe.up,
        shoe.fwd,
        0.053,
        0.008,
        shoe.len + 0.004,
        _mix(foot == ParityFoot.left ? _leftC : _rightC, _white, glow * 0.5),
        emissive: true);
    s.limb(leg.hip, leg.knee, 0.068, 0.072, _pants, fwd);
    s.limb(leg.knee, leg.ankle, 0.056, 0.06, _pants, fwd);
    s.limb(arm.shoulder, arm.elbow, 0.046, 0.046, _jacket, tf);
    s.limb(arm.elbow, arm.hand, 0.036, 0.036, _skin, tf);
    s.box(arm.hand, _xAxis, _up, _zAxis, 0.035, 0.035, 0.035, _skin);
  }
  s.rings(
      p.pelvis,
      side,
      _up,
      fwd,
      [
        (-0.08, 0.10, 0.08),
        (0.0, 0.145, 0.10),
        (0.08, 0.13, 0.09),
      ],
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
        (0.04, 0.13, 0.09),
        (height * 0.4, 0.135, 0.095),
        (height * 0.8, 0.18, 0.11),
        (height, 0.19, 0.105),
        (height + 0.085, 0.13, 0.08),
        (height + 0.10, 0.035, 0.035),
      ],
      _jacket);
  s.tube(p.chest + const _V(0, 0.11, 0), p.head + const _V(0, -0.09, 0), 0.035,
      _skin);
  final hf = _fwdOf(p.yaw * 0.25), hs = _rightOf(p.yaw * 0.25);
  s.rings(
      p.head,
      hs,
      _up,
      hf,
      [
        (-0.105, 0.035, 0.05),
        (-0.075, 0.067, 0.075),
        (0.0, 0.085, 0.095),
        (0.065, 0.08, 0.09),
        (0.10, 0.025, 0.03),
        (0.105, 0.001, 0.001),
      ],
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
  }) : super(repaint: playhead);

  /// The solve's stances and the notes it was solved on (turned), for holds.
  final List<ParityStance> stances;
  final List<StepNote> notes;
  final ValueListenable<double> playhead;
  final int columnCount;
  final double visualOffset;

  static _Track? _cache;

  _Track get _track {
    final c = _cache;
    if (c != null &&
        identical(c.stances, stances) &&
        c.columnCount == columnCount) {
      return c;
    }
    return _cache = _Track(stances, notes, columnCount);
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
    final i = _upper(tr.times, t + 0.05) - 1;
    final turn = i >= 0 ? tr.turns[i] : 0.0;
    final last = tr.lastT;
    final dt = last == null ? -1.0 : t - last;
    final snap = dt < 0 || dt > 0.3;
    tr.yaw = snap ? turn : tr.yaw + (turn - tr.yaw) * (1 - math.exp(-dt * 12));
    tr.lastT = t;

    final pose = _pose(tr, t);
    final follow = pose.pelvis.x * (columnCount > 4 ? 0.8 : 0.5);
    tr.camX = snap ? follow : tr.camX + (follow - tr.camX) * 0.08;

    const dist = 3.4, pitch = 0.40;
    final target = _V(tr.camX, 0.88, 0);
    final eye = target + _V(0, math.sin(pitch), -math.cos(pitch)) * dist;
    // Fit the stage's width on a portrait phone; the height on anything wider.
    final sceneW = columnCount > 4 ? 2.6 : 2.0;
    final focal = math.min(size.height / (2 * math.tan(21 * math.pi / 180)),
        size.width * dist / sceneW);
    final cam = _Camera(eye, target, size.width / 2, size.height * 0.56, focal);

    final chest = cam.project(pose.chest);
    if (chest != null) {
      final r = 1.4 / chest.$3 * focal;
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

    final scene = _Scene(cam);
    if (columnCount > 4) {
      _buildPad(scene, tr, t, -1.5, 0);
      _buildPad(scene, tr, t, 1.5, 4);
    } else {
      _buildPad(scene, tr, t, 0, 0);
    }
    _buildBar(scene, tr);
    _buildDancer(scene, pose);
    scene.draw(canvas);
  }

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
      old.columnCount != columnCount ||
      old.visualOffset != visualOffset ||
      old.playhead != playhead;
}
