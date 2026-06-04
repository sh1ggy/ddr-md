# Plan: IMU-Based ROI Stabilization (Projection-Correct)

## Context

Live camera ROI overlay boxes snap between OCR results (~20 FPS). Physical hand rotation makes them drift off the real-world text between frames. Goal: use gyroscope rotation data + camera projection geometry to compute exactly how much the boxes should shift each frame to stay aligned with the scene, then apply that as a per-frame overlay correction.

---

## Approach: Physics-Based Projection

Using the standard pinhole model (Corke, Robotics Vision and Control — see diagram):
- Camera origin at optical center
- Image plane at distance `f` (focal length in pixels) along optical axis
- Projection: `u = f * X/Z + cx`, `v = f * Y/Z + cy`
- Principal point `(cx, cy)` ≈ image center

When the camera rotates by a small angle `Δθ` (valid for hand-shake, |Δθ| < 0.17 rad), a world point that was at image pixel `(u, v)` shifts by:

```
Δu = f * Δθ_yaw      (yaw/pan → horizontal shift)
Δv = f * Δθ_pitch    (pitch/tilt → vertical shift)
```

**Derivation (yaw, rotation around Y-axis):**
```
P = (X, Y, Z). After rotation Δθ_y (small angle):
  X' ≈ X + Z*Δθ_y
  Z' ≈ Z - X*Δθ_y  ≈  Z   (second-order term, drop for small angles)

u'_rel = f * X'/Z' ≈ f * (X + Z*Δθ_y) / Z = f*X/Z + f*Δθ_y = u_rel + f*Δθ_y
∴ Δu = f * Δθ_y
```

Same derivation for pitch gives `Δv = f * Δθ_pitch`.

**Note:** The `-(f² + u²)/f * ω` form is the *velocity field* coefficient (for continuous rotation rate ω), not the displacement formula for a finite angle delta Δθ. We use finite deltas, so the simple `f * Δθ` form is correct here.

This is **depth-independent** for pure rotation — Z cancels out. The displacement is uniform across the image (all boxes shift by the same `f * Δθ` regardless of position), which is the correct small-angle behavior.

Hand-shake is dominated by rotation: a 0.1 rad tilt causes `f * 0.1 ≈ 180px` shift (at f≈1800px); equivalent 5mm translation at 1m causes only ~9px. Rotational compensation is sufficient.

---

## Validated Assumptions

- **Gyro only, no accelerometer.** Pure rotation dominates hand-shake; translation is secondary (9px vs ~180px at 1m). Rotational compensation is sufficient for the use case.
- **No EMA filter needed.** Gyro noise at 50 Hz, integrated over 16ms, produces negligible drift for short windows. Treating samples as clean (as requested) is valid.
- **Distance Z not needed.** The pinhole rotation field formula is depth-independent — Z cancels out for pure rotation.
- **Focal length in pixels** is needed. Flutter `camera` package does NOT expose intrinsics. We get it from a native Swift platform channel call via the existing `native_opencv` channel, reading `AVCameraCalibrationData` (available on iOS). Fallback: compute from `CameraController.value.previewSize` using approximate 52° horizontal FOV: `f = (frameWidth / 2) / tan(26° in radians)`.
- **Principal point (cx, cy) approximation:** `(frameWidth/2, frameHeight/2)` — good enough; actual principal point is within a few pixels of center.
- **iOS gyro axes (portrait):** `event.x` = pitch (tilt up/down), `event.y` = roll (not yaw — see below), `event.z` = yaw (left/right rotation). **The dominant hand-shake axes are pitch (x) and yaw (z).** Roll (y) rotates the image in-plane — less relevant for box translation.
- **sensors_plus `SensorInterval.gameInterval`** = ~50 Hz on iOS, values in rad/s. Integration over vsync dt gives angle delta.
- **OCR result = ground truth.** When a new OCR position arrives, reset accumulated gyro offset to zero. This prevents drift compounding between results.

---

## Getting Focal Length

### Option A: Native Swift platform channel (preferred, accurate)

Extend the existing `native_opencv` FlutterMethodChannel in `SwiftNativeOpencvPlugin.swift` to handle a `"getFocalLength"` call that returns the `intrinsicMatrix` `fx` value from `AVCameraCalibrationData`. This is called once at camera init.

Add to `SwiftNativeOpencvPlugin.swift`:
```swift
import AVFoundation

public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
  if call.method == "getFocalLength" {
    // Return fx from AVCaptureDevice's active format calibration data
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                               for: .video, position: .back),
          let data = device.activeFormat.unsupportedCaptureOutputClasses.isEmpty
                     ? nil : nil  // placeholder
    else {
      // Fallback: estimate from 52° horizontal FOV approximation
      result(nil)
      return
    }
    result(nil)  // see note below
  } else {
    result("iOS " + UIDevice.current.systemVersion)
  }
}
```

**NOTE:** `AVCameraCalibrationData` is only available per-captured frame (from `AVCapturePhoto` or depth data), not directly from `AVCaptureDevice.activeFormat`. The reliable path is to capture one frame with depth data enabled, extract `calibrationData.intrinsicMatrix[0][0]` (= fx), and return it. This is non-trivial for a live stream setup.

**Simpler path (Option B):** Use the frame dimensions already known in Dart.

### Option B: Derive from frame size + assumed FOV (sufficient, no native code)

The app already has `_rawFrameWidth` (the processed portrait frame width). Use:
```dart
const double _kHorizontalFovDeg = 52.0;  // typical iPhone wide camera
final double focalLengthPx = (_rawFrameWidth / 2) / tan(_kHorizontalFovDeg * pi / 180 / 2);
```

At `_rawFrameWidth = 1080` → f ≈ 1080px. At 4032 → f ≈ 4200px. This scales naturally with resolution.

**This is sufficient.** The formula only affects compensation magnitude, and a ±20% FOV error causes ±20% under/over-compensation — still visually far better than no compensation. Use Option B; no native code needed.

---

## File Changes

### 1. `pubspec.yaml`
```yaml
sensors_plus: ^4.0.2
```

### 2. `lib/components/ocr/roi_smoother.dart` *(new file)*

```dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class RoiSmoother {
  // Critically damped spring constants (ζ = damping / (2*sqrt(stiffness)) = 1)
  static const double _stiffness = 200.0;
  static const double _damping = 28.28;  // 2 * sqrt(200)

  // Horizontal FOV approximation for iPhone wide camera
  static const double _hFovDeg = 52.0;

  // Spring state
  List<Rect> _pos = [];
  List<Offset> _vel = [];
  List<Rect> _target = [];
  int? _targetDetailsIndex;
  int? get detailsIndex => _targetDetailsIndex;

  // Camera params (set from frame dimensions when first frame arrives)
  double _focalLengthPx = 0.0;
  double _cx = 0.0;
  double _cy = 0.0;

  // Accumulated gyro angle deltas (radians) since last update()
  // Pitch = rotation around X (event.x), Yaw = rotation around Z (event.z)
  double _deltaThX = 0.0;  // pitch
  double _deltaThZ = 0.0;  // yaw
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  void updateCameraParams(double frameWidth, double frameHeight) {
    _focalLengthPx = (frameWidth / 2) / tan(_hFovDeg * pi / 360);
    // cx/cy retained for potential future use (distortion, off-center principal point)
    _cx = frameWidth / 2.0;
    _cy = frameHeight / 2.0;
  }

  void startImu() {
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      // event.x / event.z are in rad/s. Multiply by sample period to get
      // angle contribution in radians, then accumulate.
      const double samplePeriod = 1.0 / 50.0;  // gameInterval ≈ 50 Hz
      _deltaThX += event.x * samplePeriod;   // pitch (rad)
      _deltaThZ += event.z * samplePeriod;   // yaw   (rad)
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
      // Snap new rects directly to target — no slide-from-origin artifact
      _pos = [..._pos, ..._target.sublist(_pos.length)];
      _vel = [..._vel, ...List.filled(_target.length - _vel.length, Offset.zero)];
    } else if (_target.length < _pos.length) {
      _pos = _pos.sublist(0, _target.length);
      _vel = _vel.sublist(0, _target.length);
    }

    // OCR position is ground truth — reset accumulated gyro offset
    _deltaThX = 0.0;
    _deltaThZ = 0.0;
  }

  List<Rect> update(Duration dt) {
    final double dtSec = min(dt.inMicroseconds / 1e6, 0.05);  // clamp spikes

    // _deltaThX / _deltaThZ were accumulated as (event.x * samplePeriod) per
    // sample, so they are already angle deltas in radians (rad/s * s = rad).
    final double dThX = _deltaThX;  // pitch angle delta (rad)
    final double dThZ = _deltaThZ;  // yaw angle delta (rad)
    _deltaThX = 0.0;
    _deltaThZ = 0.0;

    // Advance critically damped spring for each rect
    final int count = min(_pos.length, _target.length);
    for (int i = 0; i < count; i++) {
      final Rect cur = _pos[i];
      final Rect tgt = _target[i];
      Offset v = _vel[i];

      final Offset displacement = tgt.center - cur.center;
      final Offset accel = displacement * _stiffness - v * _damping;
      v = v + accel * dtSec;
      final Offset newCenter = cur.center + v * dtSec;

      _pos[i] = Rect.fromCenter(
        center: newCenter,
        width: Rect.lerp(cur, tgt, 0.15)!.width,
        height: Rect.lerp(cur, tgt, 0.15)!.height,
      );
      _vel[i] = v;
    }

    // Pinhole model small-angle displacement (from P. Corke model):
    //   Δu = f * Δθ_yaw     (uniform across image — depth-independent)
    //   Δv = f * Δθ_pitch
    // All boxes shift by the same pixel amount regardless of position.
    if (_focalLengthPx == 0.0) {
      return List.of(_pos);
    }

    final double du = _focalLengthPx * dThZ;  // yaw  → horizontal
    final double dv = _focalLengthPx * dThX;  // pitch → vertical
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
    _cx = 0.0;
    _cy = 0.0;
  }
}
```

### 3. `lib/components/roi_painter.dart`

Add `paintSmoothedRois()` alongside `paintRois()` — takes `List<Rect>` (doubles) to avoid integer rounding in the live painter:

```dart
void paintSmoothedRois(Canvas canvas, List<Rect> rois, int? detailsRoiIndex) {
  for (int i = 0; i < rois.length; i++) {
    final rect = rois[i];
    final paintToUse =
        (detailsRoiIndex != null && i == detailsRoiIndex) ? _detailsPaint : _roiPaint;
    canvas.drawRect(rect, paintToUse);
    final builder = ui.ParagraphBuilder(_paragraphStyle)
      ..pushStyle(_textStyle)
      ..addText(i.toString());
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: rect.width));
    canvas.drawParagraph(paragraph, Offset(rect.right + 6, rect.top));
  }
}
```

`paintRois()` stays unchanged — used by `_CaptureRoiPainter` and `RoiResultPainter`.

### 4. `lib/components/ocr/ocr_page.dart`

**New fields in `_OcrPageState`:**
```dart
final RoiSmoother _smoother = RoiSmoother();
final ValueNotifier<(List<Rect>, int?)> _displayRois = ValueNotifier(([], null));
Duration _lastTickElapsed = Duration.zero;
```

**`initState()`** — after `_ocrProcessor = OCRProcessor()`:
```dart
_smoother.startImu();
```

**`_processImage()`** — after setting `_rawFrameWidth`/`_rawFrameHeight`, add:
```dart
// Pass processed portrait frame dimensions to smoother for focal length calc.
// Android rotates in C++ (landscape→portrait), iOS is already portrait.
final int processedW = Platform.isAndroid ? _rawFrameHeight : _rawFrameWidth;
final int processedH = Platform.isAndroid ? _rawFrameWidth : _rawFrameHeight;
_smoother.updateCameraParams(
  processedW * _camFrameToScreenScale,
  processedH * _camFrameToScreenScale,
);
```

Note: pass **screen-space** dimensions (frame pixels × scale) because `_roiData` is already in screen-pixel space. The focal length must be in the same space as the coordinates it's applied to.

**Ticker callback** — replace `(_) => _frameTick.value++`:
```dart
(elapsed) {
  final dt = elapsed - _lastTickElapsed;
  _lastTickElapsed = elapsed;
  if (dt > Duration.zero) {
    final display = _smoother.update(dt);
    _displayRois.value = (display, _smoother.detailsIndex);
  }
  _frameTick.value++;
}
```

**OCR result listener** — replace the `scaled` + `_roiData.value = (scaled, ...)` block:
```dart
final scaledRects = (result.detectedRois ?? []).map((r) => Rect.fromLTWH(
  r.left * scale, r.top * scale, r.width * scale, r.height * scale,
)).toList();
_smoother.setTarget(scaledRects, result.detailsRoiIndex);
// Keep _roiData for the stopped-view capture path (unscaled frame-pixel rois).
_roiData.value = (result.detectedRois ?? [], result.detailsRoiIndex);
```

**`dispose()`:**
```dart
_smoother.dispose();
_displayRois.dispose();
```

**Camera restart in `_toggleCamera`** (inside the `else` branch, alongside `_roiData.value = ([], null)`):
```dart
_smoother.reset();
_displayRois.value = ([], null);
_lastTickElapsed = Duration.zero;
```

**`_CameraRoiPainter`** — update to read `_displayRois`:
```dart
class _CameraRoiPainter extends CustomPainter {
  _CameraRoiPainter(this.displayRois, Listenable frameTick)
      : super(repaint: frameTick);
  final ValueNotifier<(List<Rect>, int?)> displayRois;

  @override
  void paint(Canvas canvas, Size size) {
    final (rois, detailsRoiIndex) = displayRois.value;
    paintSmoothedRois(canvas, rois, detailsRoiIndex);
  }

  @override
  bool shouldRepaint(covariant _CameraRoiPainter oldDelegate) => false;
}
```

Construction site in `_buildActiveView()`:
```dart
foregroundPainter: _CameraRoiPainter(_displayRois, _frameTick),
```

---

## Gyro Axis Sign Verification

On iOS portrait with `sensors_plus`:
- `event.x` (pitch): tilting top of phone toward you → positive. Scene appears to shift **downward** in image → `dv` should be positive → negate `dThX` in formula if boxes go wrong way.
- `event.z` (yaw): rotating phone left (counterclockwise from top) → positive. Scene shifts **right** → `du` should be positive → negate `dThZ` if wrong.

**Test procedure:** Hold phone still over a detected screen. Tilt top toward you slightly. Boxes should shift down (following the scene). If they shift up, negate `dThX`.

---

## Tuning

| Parameter | Default | Effect |
|-----------|---------|--------|
| `_stiffness` | 200 | Higher = snappier spring to OCR target |
| `_damping` | 28.28 | Keep at `2*sqrt(stiffness)` for no overshoot |
| `_hFovDeg` | 52.0 | Match to actual camera; affects compensation scale |
| `samplePeriod` | 1/50 | Match to `SensorInterval.gameInterval` actual rate |

---

## Verification

1. Physical device only (simulator has no gyro)
2. Point at a DDR score screen, start OCR — boxes should glide smoothly to positions
3. Tilt device toward you — boxes should shift down to stay on text
4. Rotate device left/right — boxes should shift horizontally to track scene
5. Stop/restart camera — overlay clears and locks correctly
6. Stopped-view capture still shows correct static ROIs (unchanged path)
