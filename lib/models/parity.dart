/// Name: Parity engine (foot assignment)
/// Description: A cost-minimising foot-parity solver ported from SMEditor
/// (tillvit/smeditor, files ParityInternals/ParityCost/ParityDataTypes/
/// StageLayouts). Replaces the old greedy [FootAssigner] heuristic.
///
/// Why a full engine and not a greedy pass: crossovers and footswitches can
/// only be read correctly with lookahead over a *physical* model of the pad.
/// A crossover is defined by the notes that follow it; a footswitch is a
/// repeated column danced with alternating feet. A per-note greedy solver
/// commits before it has seen the disambiguating notes, so it can't produce
/// either reliably. This solver instead:
///   1. models each foot as heel+toe on a coordinate pad (so "crossed over",
///      "facing", "bracket" are real geometric facts, not column heuristics),
///   2. scores every legal foot placement per row with a weighted cost model,
///   3. finds the minimum-cost path through the whole chart via a forward DP.
/// Crossovers/footswitches then *emerge* because they're cheaper than the
/// doublestep alternative — nothing hard-codes "insert a crossover here".
///
/// Internally feet are heel/toe (4 parts) because the cost functions need that
/// to keep brackets honest, but the public API folds back to plain L/R via
/// [ParityFoot], since the renderer only draws a left/right badge.
///
/// This is a batch analyser (compute once when a chart opens), so all of
/// SMEditor's incremental-recompute / edge-caching / web-worker machinery is
/// deliberately dropped.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/steps_model.dart';

/// Public foot result: left or right. (Heel/toe is an internal detail.)
enum ParityFoot { left, right }

// ---------------------------------------------------------------------------
// Foot parts (internal). Index values matter: they index [_footColumns].
// ---------------------------------------------------------------------------

/// A foot *part*. NONE is the absence of a foot; each real foot is a heel and a
/// toe so a single arrow uses the heel and a bracket uses heel+toe.
class _Foot {
  static const int none = 0;
  static const int leftHeel = 1;
  static const int leftToe = 2;
  static const int rightHeel = 3;
  static const int rightToe = 4;

  /// The parts that can actually be placed on an arrow (NONE excluded).
  static const List<int> all = [leftHeel, leftToe, rightHeel, rightToe];

  /// The other part of the same physical foot (heel<->toe), NONE for NONE.
  static const List<int> otherPart = [none, leftToe, leftHeel, rightToe, rightHeel];

  static bool isLeft(int f) => f == leftHeel || f == leftToe;

  static ParityFoot toParityFoot(int f) =>
      isLeft(f) ? ParityFoot.left : ParityFoot.right;
}

// ---------------------------------------------------------------------------
// Cost weights. Read as a priority order (higher = more strongly avoided).
// Ported from SMEditor's DEFAULT_WEIGHTS; kept here so they're easy to tune.
// ---------------------------------------------------------------------------

class _Weights {
  static const double doublestep = 750;
  static const double bracketJack = 60;
  static const double jack = 40;
  static const double jump = 0;
  static const double slowBracket = 300;
  static const double twistedFoot = 100000;
  static const double xoBr = 200;
  static const double mine = 10000;
  static const double footswitch = 325;
  static const double missedFootswitch = 500;
  static const double facing = 3;
  static const double distance = 6;
  static const double spin = 3000;
  static const double sideswitch = 130;
  static const double startXo = 10000;
}

// ---------------------------------------------------------------------------
// Stage geometry.
// ---------------------------------------------------------------------------

class _StagePoint {
  final double x;
  final double y;
  const _StagePoint(this.x, this.y);
}

/// The physical pad: each column is a coordinate, so body rotation / crossovers
/// / bracket-reach become real geometry rather than column-index heuristics.
class _StageLayout {
  final List<_StagePoint> layout;
  final List<int> sideArrows;

  const _StageLayout(this.layout, this.sideArrows);

  int get columnCount => layout.length;

  /// dance-single: L(-1,0) D(0,-1) U(0,1) R(1,0). Side panels are L and R.
  static const _StageLayout singles = _StageLayout(
    [
      _StagePoint(-1, 0), // Left
      _StagePoint(0, -1), // Down
      _StagePoint(0, 1), // Up
      _StagePoint(1, 0), // Right
    ],
    [0, 3],
  );

  /// dance-double: two panels laid side by side on the x axis.
  static const _StageLayout doubles = _StageLayout(
    [
      _StagePoint(-2.5, 0), // P1 Left
      _StagePoint(-1.5, -1), // P1 Down
      _StagePoint(-1.5, 1), // P1 Up
      _StagePoint(-0.5, 0), // P1 Right
      _StagePoint(0.5, 0), // P2 Left
      _StagePoint(1.5, -1), // P2 Down
      _StagePoint(1.5, 1), // P2 Up
      _StagePoint(2.5, 0), // P2 Right
    ],
    [0, 3, 4, 7],
  );

  double distanceSq(int a, int b) {
    final p1 = layout[a];
    final p2 = layout[b];
    final dx = p1.x - p2.x;
    final dy = p1.y - p2.y;
    return dx * dx + dy * dy;
  }

  double distanceSqPoints(_Point p1, _Point p2) {
    final dx = p1.x - p2.x;
    final dy = p1.y - p2.y;
    return dx * dx + dy * dy;
  }

  /// Two columns are bracketable iff they are adjacent (squared distance <= 2),
  /// e.g. an L-shaped pair — never two panels across the pad.
  bool bracketCheck(int a, int b) => distanceSq(a, b) <= 2;

  /// The position of a foot given its heel/toe columns (midpoint, or the single
  /// occupied column, or origin if the foot isn't placed).
  _Point averagePoint(int heel, int toe) {
    if (heel == -1 && toe == -1) return const _Point(0, 0);
    if (heel == -1) return _Point(layout[toe].x, layout[toe].y);
    if (toe == -1) return _Point(layout[heel].x, layout[heel].y);
    return _Point(
      (layout[heel].x + layout[toe].x) / 2,
      (layout[heel].y + layout[toe].y) / 2,
    );
  }
}

class _Point {
  final double x;
  final double y;
  const _Point(this.x, this.y);
}

/// Signed body angle from the vector between the two feet and the +x axis.
/// Used to distinguish a legal crossover from a full spin.
double _playerAngle(_Point left, _Point right) {
  final x1 = right.x - left.x;
  final y1 = right.y - left.y;
  // det/dot against (1,0).
  return math.atan2(-y1, x1);
}

bool _doFeetOverlap(int oldHeel, int oldToe, int newHeel, int newToe) {
  if (oldHeel != -1 && (oldHeel == newHeel || oldHeel == newToe)) return true;
  if (oldToe != -1 && (oldToe == newHeel || oldToe == newToe)) return true;
  return false;
}

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

// ---------------------------------------------------------------------------
// Rows & states.
// ---------------------------------------------------------------------------

/// All notes sharing a timestamp, plus which columns carry active holds/mines.
class _Row {
  final List<StepNote?> notes; // by column
  final List<bool> holds; // column has an active hold spanning this row
  final Set<int> holdTails; // columns whose hold ends on this row
  final List<bool> mines; // column has a mine to avoid on this row
  final double second;
  final double beat;

  _Row({
    required this.notes,
    required this.holds,
    required this.holdTails,
    required this.mines,
    required this.second,
    required this.beat,
  });
}

/// One candidate foot placement for a row: where each foot part landed.
class _State {
  /// action[col] = foot part actively stepping this column this row (NONE if
  /// the column isn't stepped by this action).
  final List<int> action;

  /// combinedColumns[col] = foot part occupying the column, including feet that
  /// stayed put from the previous state (used for switch/jack detection).
  final List<int> combinedColumns;

  /// footColumns[part] = column that foot part currently rests on (-1 if none).
  final List<int> footColumns; // length 5, indexed by _Foot part

  final Set<int> movedFeet;
  final Set<int> holdFeet;
  int? frontFoot;
  final double second;
  final double beat;

  _State({
    required this.action,
    required this.combinedColumns,
    required this.footColumns,
    required this.movedFeet,
    required this.holdFeet,
    required this.frontFoot,
    required this.second,
    required this.beat,
  });

  int get leftHeel => footColumns[_Foot.leftHeel];
  int get leftToe => footColumns[_Foot.leftToe];
  int get rightHeel => footColumns[_Foot.rightHeel];
  int get rightToe => footColumns[_Foot.rightToe];
}

/// Facts derived from an initial→result transition, shared by the cost fns.
class _Placement {
  final _Point previousLeftPos;
  final _Point previousRightPos;
  final _Point leftPos;
  final _Point rightPos;
  final bool leftBracket;
  final bool rightBracket;
  final bool previousJumped;
  final bool jumped;
  final bool leftJack;
  final bool rightJack;
  final bool leftDoubleStep;
  final bool rightDoubleStep;
  final _State initial;
  final _State result;

  _Placement({
    required this.previousLeftPos,
    required this.previousRightPos,
    required this.leftPos,
    required this.rightPos,
    required this.leftBracket,
    required this.rightBracket,
    required this.previousJumped,
    required this.jumped,
    required this.leftJack,
    required this.rightJack,
    required this.leftDoubleStep,
    required this.rightDoubleStep,
    required this.initial,
    required this.result,
  });
}

// ---------------------------------------------------------------------------
// The engine.
// ---------------------------------------------------------------------------

class _ParityEngine {
  final _StageLayout layout;

  _ParityEngine(this.layout);

  /// Build rows by grouping notes on the same (rounded) second. Holds are
  /// tracked so a foot may legally "double step" while the other foot holds.
  List<_Row> _buildRows(List<StepNote> notes) {
    // Group non-mine notes and mines separately by time key.
    final groups = <double, List<StepNote>>{};
    final mineGroups = <double, List<StepNote>>{};
    for (final n in notes) {
      final key = (n.second * 1000).roundToDouble() / 1000;
      if (n.type == StepType.mine) {
        (mineGroups[key] ??= []).add(n);
      } else {
        (groups[key] ??= []).add(n);
      }
    }
    final times = groups.keys.toList()..sort();

    final rows = <_Row>[];
    for (final t in times) {
      final groupNotes = groups[t]!;
      final rowNotes = List<StepNote?>.filled(layout.columnCount, null);
      final holds = List<bool>.filled(layout.columnCount, false);
      final holdTails = <int>{};
      final mines = List<bool>.filled(layout.columnCount, false);

      double second = t;
      double beat = groupNotes.first.beat;
      for (final n in groupNotes) {
        if (n.col < 0 || n.col >= layout.columnCount) continue;
        rowNotes[n.col] = n;
        second = n.second;
        beat = n.beat;
      }

      // A hold/roll is "active" across every row whose time falls within its
      // span; its tail row is where it ends.
      for (final n in notes) {
        if (!n.isHold) continue;
        if (n.col < 0 || n.col >= layout.columnCount) continue;
        final start = n.second;
        final end = n.endSecond ?? n.second;
        // Active if this row is at/after the head and strictly before the tail;
        // the head row itself is a normal tap so we only mark rows *after* it.
        if (t > start + _secondEps && t < end - _secondEps) {
          holds[n.col] = true;
        }
        if ((t - end).abs() < _secondEps) {
          holdTails.add(n.col);
          holds[n.col] = true;
        }
      }

      // Mines landing on this row's time.
      final mg = mineGroups[t];
      if (mg != null) {
        for (final m in mg) {
          if (m.col >= 0 && m.col < layout.columnCount) mines[m.col] = true;
        }
      }

      rows.add(_Row(
        notes: rowNotes,
        holds: holds,
        holdTails: holdTails,
        mines: mines,
        second: second,
        beat: beat,
      ));
    }
    return rows;
  }

  static const double _secondEps = 0.0005;

  /// Enumerate every legal assignment of foot parts to the stepped columns of a
  /// row, pruned by bracket geometry and heel/toe validity.
  List<List<int>> _generateActions(_Row row) {
    final results = <List<int>>[];
    final columns = List<int>.filled(layout.columnCount, _Foot.none);

    void recurse(int col) {
      if (col >= layout.columnCount) {
        int lh = -1, lt = -1, rh = -1, rt = -1;
        for (int i = 0; i < columns.length; i++) {
          switch (columns[i]) {
            case _Foot.leftHeel:
              lh = i;
              break;
            case _Foot.leftToe:
              lt = i;
              break;
            case _Foot.rightHeel:
              rh = i;
              break;
            case _Foot.rightToe:
              rt = i;
              break;
          }
        }
        // A toe with no heel of the same foot is invalid.
        if ((lh == -1 && lt != -1) || (rh == -1 && rt != -1)) return;
        // Both parts of a foot must be bracketable (adjacent).
        if (lh != -1 && lt != -1 && !layout.bracketCheck(lh, lt)) return;
        if (rh != -1 && rt != -1 && !layout.bracketCheck(rh, rt)) return;
        results.add(List<int>.of(columns));
        return;
      }
      final active = row.notes[col] != null || row.holds[col];
      if (!active) {
        recurse(col + 1);
        return;
      }
      for (final foot in _Foot.all) {
        if (columns.contains(foot)) continue;
        columns[col] = foot;
        recurse(col + 1);
        columns[col] = _Foot.none;
      }
    }

    recurse(0);
    return results;
  }

  /// Apply an action to a parent state to produce the resulting state (feet not
  /// moved this row carry over their previous column).
  _State _initResultState(_State initial, _Row row, List<int> action) {
    final footColumns = List<int>.filled(5, -1);
    final combined = List<int>.filled(layout.columnCount, _Foot.none);
    final moved = <int>{};
    final held = <int>{};

    for (int i = 0; i < layout.columnCount; i++) {
      final a = action[i];
      if (a == _Foot.none) continue;
      footColumns[a] = i;
      combined[i] = a;
      if (!row.holds[i]) {
        moved.add(a);
      } else if (initial.combinedColumns[i] != a) {
        moved.add(a);
      }
      if (row.holds[i]) held.add(a);
    }

    // Carry over feet that didn't step this row.
    void carry(int heel, int toe) {
      if (footColumns[heel] != -1) return;
      footColumns[heel] = initial.footColumns[heel];
      footColumns[toe] = initial.footColumns[toe];
      final hc = footColumns[heel];
      final tc = footColumns[toe];
      if (hc != -1 && combined[hc] == _Foot.none) combined[hc] = heel;
      if (tc != -1 && combined[tc] == _Foot.none) combined[tc] = toe;
    }

    carry(_Foot.leftHeel, _Foot.leftToe);
    carry(_Foot.rightHeel, _Foot.rightToe);

    final leftPos = layout.averagePoint(
        footColumns[_Foot.leftHeel], footColumns[_Foot.leftToe]);
    final rightPos = layout.averagePoint(
        footColumns[_Foot.rightHeel], footColumns[_Foot.rightToe]);

    int? frontFoot;
    if (leftPos.y > rightPos.y) {
      frontFoot = _Foot.leftHeel;
    } else if (rightPos.y > leftPos.y) {
      frontFoot = _Foot.rightHeel;
    } else {
      frontFoot = initial.frontFoot;
    }

    return _State(
      action: action,
      combinedColumns: combined,
      footColumns: footColumns,
      movedFeet: moved,
      holdFeet: held,
      frontFoot: frontFoot,
      second: row.second,
      beat: row.beat,
    );
  }

  _Placement _placement(_State initial, _State result, _Row? lastRow, _Row row) {
    final prevNonHeld = List<bool>.filled(5, false);
    final nonHeld = List<bool>.filled(5, false);
    for (int i = 0; i < layout.columnCount; i++) {
      if (lastRow != null &&
          !lastRow.holds[i] &&
          initial.action[i] != _Foot.none) {
        prevNonHeld[initial.action[i]] = true;
      }
      if (!row.holds[i] && result.action[i] != _Foot.none) {
        nonHeld[result.action[i]] = true;
      }
    }

    final prevMovedLeft = prevNonHeld[_Foot.leftHeel] || prevNonHeld[_Foot.leftToe];
    final prevMovedRight =
        prevNonHeld[_Foot.rightHeel] || prevNonHeld[_Foot.rightToe];
    final movedLeft = nonHeld[_Foot.leftHeel] || nonHeld[_Foot.leftToe];
    final movedRight = nonHeld[_Foot.rightHeel] || nonHeld[_Foot.rightToe];

    final leftBracket = nonHeld[_Foot.leftHeel] && nonHeld[_Foot.leftToe];
    final rightBracket = nonHeld[_Foot.rightHeel] && nonHeld[_Foot.rightToe];

    final previousJumped =
        prevNonHeld[_Foot.leftHeel] && prevNonHeld[_Foot.rightHeel];
    final jumped = nonHeld[_Foot.leftHeel] && nonHeld[_Foot.rightHeel];

    final leftJack = !jumped &&
        _doFeetOverlap(
            initial.leftHeel, initial.leftToe, result.leftHeel, result.leftToe) &&
        prevMovedLeft &&
        movedLeft;
    final rightJack = !jumped &&
        _doFeetOverlap(initial.rightHeel, initial.rightToe, result.rightHeel,
            result.rightToe) &&
        prevMovedRight &&
        movedRight;

    final leftDoubleStep =
        prevMovedLeft && movedLeft && !jumped && !leftJack && !previousJumped;
    final rightDoubleStep =
        prevMovedRight && movedRight && !jumped && !rightJack && !previousJumped;

    return _Placement(
      previousLeftPos:
          layout.averagePoint(initial.leftHeel, initial.leftToe),
      previousRightPos:
          layout.averagePoint(initial.rightHeel, initial.rightToe),
      leftPos: layout.averagePoint(result.leftHeel, result.leftToe),
      rightPos: layout.averagePoint(result.rightHeel, result.rightToe),
      leftBracket: leftBracket,
      rightBracket: rightBracket,
      previousJumped: previousJumped,
      jumped: jumped,
      leftJack: leftJack,
      rightJack: rightJack,
      leftDoubleStep: leftDoubleStep,
      rightDoubleStep: rightDoubleStep,
      initial: initial,
      result: result,
    );
  }

  // --- cost functions (ported from ParityCost.ts) ---

  double _cost(_State initial, _State result, List<_Row> rows, int rowIndex) {
    final lastRow = rowIndex > 0 ? rows[rowIndex - 1] : null;
    final row = rows[rowIndex];
    double elapsed = result.second - initial.second;
    if (rowIndex == 0) elapsed = 0.1;
    if (elapsed <= 0) elapsed = _secondEps;

    final d = _placement(initial, result, lastRow, row);
    double total = 0;

    // MINE: stepping on a mined column.
    for (int i = 0; i < layout.columnCount; i++) {
      if (d.result.combinedColumns[i] != _Foot.none && row.mines[i]) {
        total += _Weights.mine;
        break;
      }
    }

    // START_XO: don't begin the chart crossed over.
    if (rowIndex == 0 && d.rightPos.x < d.leftPos.x) {
      total += _Weights.startXo;
    }

    // BRACKETJACK
    if (!d.jumped &&
        ((d.leftJack && d.leftBracket) || (d.rightJack && d.rightBracket))) {
      total += _Weights.bracketJack;
    }

    // XO_BR: bracketing while crossed over.
    final crossedOver = d.rightPos.x < d.leftPos.x;
    if (d.leftBracket && crossedOver) total += _Weights.xoBr;
    if (d.rightBracket && crossedOver) total += _Weights.xoBr;

    // DOUBLESTEP
    if (d.leftDoubleStep || d.rightDoubleStep) {
      total += _doublestepCost(d, lastRow, row, elapsed);
    }

    // JUMP
    if (d.jumped) total += _Weights.jump / elapsed;

    // SLOW_BRACKET
    if (elapsed > 0.15 &&
        (d.leftBracket || d.rightBracket) &&
        !d.jumped) {
      total += math.min(0.5, elapsed - 0.15) * _Weights.slowBracket;
    }

    // TWISTED_FOOT: toe behind heel (foot rotated backwards) — near-impossible.
    if (_twisted(d.result.rightHeel, d.result.rightToe) ||
        _twisted(d.result.leftHeel, d.result.leftToe)) {
      total += _Weights.twistedFoot;
    }

    // FACING: facing backwards, ramps sharply (^7.2) so deep crossovers cost
    // more but are still cheaper than a doublestep.
    total += _facingCost(d);

    // SPIN
    total += _spinCost(d);

    // FOOTSWITCH: only slow footswitches are penalised.
    total += _slowFootswitchCost(d, row, elapsed);

    // SIDESWITCH
    total += _sideswitchCost(d);

    // MISSED_FOOTSWITCH: a jack where a mine indicated a switch.
    if ((d.leftJack || d.rightJack) && _rowHasMine(row)) {
      total += _Weights.missedFootswitch;
    }

    // JACK: same foot same arrow, penalised when fast.
    if (elapsed < 0.125 &&
        (d.leftJack || d.rightJack) &&
        !d.previousJumped) {
      total += (1 / elapsed - 1 / 0.125) * _Weights.jack;
    }

    // DISTANCE: moving a foot far in little time.
    total += _distanceCost(d, elapsed);

    return total;
  }

  bool _twisted(int heel, int toe) {
    if (heel == -1 || toe == -1) return false;
    return layout.layout[toe].y < layout.layout[heel].y;
  }

  bool _rowHasMine(_Row row) {
    for (final m in row.mines) {
      if (m) return true;
    }
    return false;
  }

  double _doublestepCost(
      _Placement d, _Row? lastRow, _Row row, double elapsed) {
    // Allowed to double step if a hold lets the other foot stay planted.
    for (int i = 0; i < layout.columnCount; i++) {
      final lastHold = lastRow != null && lastRow.holds[i];
      if ((lastHold && !(lastRow.holdTails.contains(i))) || row.holds[i]) {
        return 0;
      }
    }
    // Allowed if stepping onto a mine (you'd rather double step than eat it).
    if (d.leftDoubleStep) {
      final lh = d.initial.footColumns[_Foot.leftHeel];
      final lt = d.initial.footColumns[_Foot.leftToe];
      if ((lh != -1 && row.mines[lh]) || (lt != -1 && row.mines[lt])) return 0;
    }
    if (d.rightDoubleStep) {
      final rh = d.initial.footColumns[_Foot.rightHeel];
      final rt = d.initial.footColumns[_Foot.rightToe];
      if ((rh != -1 && row.mines[rh]) || (rt != -1 && row.mines[rt])) return 0;
    }
    return _Weights.doublestep / _clamp(elapsed * 4, 0.3, 1);
  }

  double _facingCost(_Placement d) {
    double dx = d.rightPos.x - d.leftPos.x;
    final dy = d.rightPos.y - d.leftPos.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist == 0) return 0;
    dx /= dist;
    final heelFacing = dx;
    final penalty = math.pow(-math.min(heelFacing, 0.0), 7.2) * 200;
    if (penalty > 0) return penalty * _Weights.facing;
    return 0;
  }

  double _spinCost(_Placement d) {
    double prev = _playerAngle(d.previousLeftPos, d.previousRightPos);
    double angle = _playerAngle(d.leftPos, d.rightPos);
    if (angle.abs() < math.pi / 2 || prev.abs() < math.pi / 2) return 0;
    if (angle < 0) angle += math.pi * 2;
    if (prev < 0) prev += math.pi * 2;
    if (angle == prev) return 0;
    final crosses = (prev <= math.pi && angle >= math.pi) ||
        (prev >= math.pi && angle <= math.pi);
    if (crosses && d.initial.frontFoot != d.result.frontFoot) {
      return _Weights.spin;
    }
    return 0;
  }

  double _slowFootswitchCost(_Placement d, _Row row, double elapsed) {
    if (elapsed < 0.2 || elapsed >= 0.4) return 0;
    if (d.jumped) return 0;
    if (_rowHasMine(row)) return 0;
    double cost = 0;
    for (final foot in d.result.movedFeet) {
      final col = d.result.footColumns[foot];
      if (col == -1) continue;
      final prev = d.initial.combinedColumns[col];
      if (prev == _Foot.none) continue;
      if (prev == foot || prev == _Foot.otherPart[foot]) continue;
      cost += ((elapsed - 0.2) / elapsed) * _Weights.footswitch;
    }
    return cost;
  }

  double _sideswitchCost(_Placement d) {
    if (d.jumped) return 0;
    double cost = 0;
    for (final col in layout.sideArrows) {
      final act = d.result.action[col];
      if (act == _Foot.none) continue;
      final prev = d.initial.combinedColumns[col];
      if (prev == _Foot.none) continue;
      if (prev == act || prev == _Foot.otherPart[act]) continue;
      cost += _Weights.sideswitch;
    }
    return cost;
  }

  double _distanceCost(_Placement d, double elapsed) {
    double cost = 0;
    for (final foot in [_Foot.leftHeel, _Foot.rightHeel]) {
      if (!d.result.movedFeet.contains(foot)) continue;
      final initialPos =
          foot == _Foot.leftHeel ? d.previousLeftPos : d.previousRightPos;
      final resultPos = foot == _Foot.leftHeel ? d.leftPos : d.rightPos;
      final isBracketing =
          foot == _Foot.leftHeel ? d.leftBracket : d.rightBracket;
      if (isBracketing) {
        final initialHeel = d.initial.footColumns[foot];
        final initialToe = d.initial.footColumns[_Foot.otherPart[foot]];
        final resultHeel = d.result.footColumns[foot];
        var resultToe = d.result.footColumns[_Foot.otherPart[foot]];
        if (resultToe == -1) resultToe = resultHeel;
        if (initialHeel != -1 &&
            (initialHeel == resultHeel || initialHeel == resultToe)) {
          continue;
        }
        if (initialToe != -1 &&
            (initialToe == resultHeel || initialToe == resultToe)) {
          continue;
        }
      }
      double e = elapsed;
      if (d.previousJumped && !d.jumped && e < 0.25) {
        e = math.pow(e, 1.5).toDouble();
      }
      cost += math.sqrt(layout.distanceSqPoints(initialPos, resultPos)) *
          _Weights.distance /
          e;
    }
    return cost;
  }

  // --- forward DP over the state graph ---

  /// Returns, per row index, the chosen [_State] on the minimum-cost path.
  List<_State> solve(List<_Row> rows) {
    if (rows.isEmpty) return const [];

    final startState = _State(
      action: List<int>.filled(layout.columnCount, _Foot.none),
      combinedColumns: List<int>.filled(layout.columnCount, _Foot.none),
      footColumns: List<int>.filled(5, -1),
      movedFeet: {},
      holdFeet: {},
      frontFoot: null,
      second: rows.first.second - 0.1,
      beat: 0,
    );

    // Cache action permutations by which columns are active (identical rows
    // share the same permutation set).
    final permCache = <String, List<List<int>>>{};
    List<List<int>> actionsFor(_Row row) {
      final sb = StringBuffer();
      for (int i = 0; i < layout.columnCount; i++) {
        if (row.notes[i] != null || row.holds[i]) sb.write(i);
        sb.write('|');
      }
      return permCache[sb.toString()] ??= _generateActions(row);
    }

    // Layer 0: states reachable from the (single) start state.
    var prevLayer = <_State>[startState];
    var prevCost = <double>[0];
    // Backpointers: layers[rowIndex][stateIndex] -> index in previous layer.
    final back = <List<int>>[];
    final layers = <List<_State>>[];

    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];
      final actions = actionsFor(row);
      final curStates = <_State>[];
      final curCost = <double>[];
      final curBack = <int>[];

      // If a row somehow has no legal action, keep feet where they were.
      final effectiveActions = actions.isEmpty
          ? <List<int>>[List<int>.filled(layout.columnCount, _Foot.none)]
          : actions;

      for (final action in effectiveActions) {
        double best = double.infinity;
        int bestPrev = 0;
        _State? bestResult;
        for (int p = 0; p < prevLayer.length; p++) {
          final result = _initResultState(prevLayer[p], row, action);
          final edge = _cost(prevLayer[p], result, rows, r);
          final c = prevCost[p] + edge;
          if (c < best) {
            best = c;
            bestPrev = p;
            bestResult = result;
          }
        }
        curStates.add(bestResult!);
        curCost.add(best);
        curBack.add(bestPrev);
      }

      layers.add(curStates);
      back.add(curBack);
      prevLayer = curStates;
      prevCost = curCost;
    }

    // Pick the cheapest terminal state and walk backpointers.
    int bestIdx = 0;
    double bestVal = double.infinity;
    for (int i = 0; i < prevCost.length; i++) {
      if (prevCost[i] < bestVal) {
        bestVal = prevCost[i];
        bestIdx = i;
      }
    }

    final chosen = List<_State?>.filled(rows.length, null);
    int idx = bestIdx;
    for (int r = rows.length - 1; r >= 0; r--) {
      chosen[r] = layers[r][idx];
      idx = back[r][idx];
    }
    return chosen.map((s) => s!).toList();
  }

  /// Full pipeline: notes -> per-note L/R foot assignment.
  Map<StepNote, ParityFoot> assign(List<StepNote> notes) {
    final result = <StepNote, ParityFoot>{};
    final rows = _buildRows(notes);
    if (rows.isEmpty) return result;
    final states = solve(rows);
    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];
      final state = states[r];
      for (int col = 0; col < layout.columnCount; col++) {
        final note = row.notes[col];
        if (note == null) continue;
        final foot = state.combinedColumns[col];
        if (foot == _Foot.none) continue;
        result[note] = _Foot.toParityFoot(foot);
      }
    }
    return result;
  }
}

/// Entry point: assign a left/right foot to every non-mine note using the
/// cost-minimising parity engine.
Map<StepNote, ParityFoot> assignParity(List<StepNote> notes, Modes mode) {
  final layout =
      mode == Modes.doubles ? _StageLayout.doubles : _StageLayout.singles;
  return _ParityEngine(layout).assign(notes);
}
