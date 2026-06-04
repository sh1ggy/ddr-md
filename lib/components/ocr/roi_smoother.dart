import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class RoiSmoother {
  // Critically damped spring: damping = 2*sqrt(stiffness) → ζ = 1, no overshoot.
  static const double _stiffness = 100.0;
  static const double _damping = 28.28; // 2 * sqrt(200)

  // Horizontal FOV approximation for iPhone wide camera.
  static const double _hFovDeg = 52.0;

  // Spring state — parallel lists, one entry per tracked ROI.
  List<Rect> _pos = [];
  List<Offset> _vel = [];
  List<Rect> _target = [];
  int? _targetDetailsIndex;
  int? get detailsIndex => _targetDetailsIndex;

  // Camera intrinsics in screen-pixel space (set from first processed frame).
  double _focalLengthPx = 0.0;

  // Accumulated gyro angle deltas (radians) since last update().
  // Each sample contributes event * samplePeriod so the accumulator is in rad.
  double _deltaThX = 0.0; // pitch (event.x)
  double _deltaThZ = 0.0; // yaw   (event.z)
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  void updateCameraParams(double screenSpaceFrameWidth) {
    _focalLengthPx =
        (screenSpaceFrameWidth / 2) / tan(_hFovDeg * pi / 360);
  }

  void startImu() {
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval, // ~50 Hz
    ).listen((event) {
      // Multiply rad/s by sample period to accumulate angle in radians.
      const double samplePeriod = 1.0 / 50.0;
      _deltaThX += event.x * samplePeriod; // pitch
      _deltaThZ += event.z * samplePeriod; // yaw
    });
  }

  void dispose() {
    _gyroSub?.cancel();
    _gyroSub = null;
  }

  void setTarget(List<Rect> newTarget, int? detailsIndex) {
    _targetDetailsIndex = detailsIndex;
    _target = newTarget;

    if (_target.length > _pos.length) {
      // Snap new rects directly to target — avoids slide-from-origin artifact.
      _pos = [..._pos, ..._target.sublist(_pos.length)];
      _vel = [
        ..._vel,
        ...List.filled(_target.length - _vel.length, Offset.zero)
      ];
    } else if (_target.length < _pos.length) {
      // Drop trailing rects immediately — stale boxes are misleading.
      _pos = _pos.sublist(0, _target.length);
      _vel = _vel.sublist(0, _target.length);
    }

    // OCR result is ground truth — reset accumulated IMU drift.
    _deltaThX = 0.0;
    _deltaThZ = 0.0;
  }

  List<Rect> update(Duration dt) {
    // Clamp to prevent spring blow-up on vsync spikes.
    final double dtSec = min(dt.inMicroseconds / 1e6, 0.05);

    // Advance critically damped spring for each rect toward its target.
    final int count = min(_pos.length, _target.length);
    for (int i = 0; i < count; i++) {
      final Rect cur = _pos[i];
      final Rect tgt = _target[i];
      Offset v = _vel[i];

      final Offset displacement = tgt.center - cur.center;
      final Offset accel = displacement * _stiffness - v * _damping;
      v = v + accel * dtSec;
      final Offset newCenter = cur.center + v * dtSec;

      // Spring the position; softly lerp the size toward the target.
      _pos[i] = Rect.fromCenter(
        center: newCenter,
        width: Rect.lerp(cur, tgt, 0.15)!.width,
        height: Rect.lerp(cur, tgt, 0.15)!.height,
      );
      _vel[i] = v;
    }

    // Pinhole model small-angle displacement (Corke, Robotics Vision & Control):
    //   Δu = f * Δθ_yaw     (depth-independent for pure rotation)
    //   Δv = f * Δθ_pitch
    if (_focalLengthPx == 0.0) return List.of(_pos);

    final double du = _focalLengthPx * _deltaThZ; // yaw  → horizontal
    final double dv = _focalLengthPx * _deltaThX; // pitch → vertical
    _deltaThX = 0.0;
    _deltaThZ = 0.0;

    return _pos.map((r) => r.translate(du, dv)).toList();
  }

  void reset() {
    _pos = [];
    _vel = [];
    _target = [];
    _targetDetailsIndex = null;
    _deltaThX = 0.0;
    _deltaThZ = 0.0;
    _focalLengthPx = 0.0;
  }
}
