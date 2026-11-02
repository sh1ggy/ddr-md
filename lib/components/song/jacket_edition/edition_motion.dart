/// Name: EditionMotion
/// Parent: JacketEdition
/// Description: One frame-coalesced light source, with no widget rebuilds.
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/painting.dart';

class EditionMotion extends ChangeNotifier {
  EditionMotion(TickerProvider vsync, {Stream<GyroscopeEvent>? gyroscope})
      : _gyroscope = gyroscope {
    _ticker = vsync.createTicker(_tick);
  }
  late final Ticker _ticker;
  // Where the light rests while still; the idle drift starts from here, so
  // the sheen never jumps when motion starts.
  static const rest = Offset(.35, .3);
  static final _phase =
      Offset(math.asin((rest.dx - .5) / .35), math.asin((rest.dy - .5) / .3));
  Offset light = rest;
  Offset tilt = Offset.zero;
  final Stream<GyroscopeEvent>? _gyroscope;
  StreamSubscription<GyroscopeEvent>? _sensor;
  DateTime? _sampleTime;
  Offset _rotation = Offset.zero;
  bool _sensorActive = false;
  Offset? _pending;
  // The light follows the device rotation, eased on display frames.
  Offset _aim = rest;
  bool _held = false;
  Duration _last = Duration.zero;
  double time = 0;
  bool get running => _ticker.isActive;

  void configure(bool enabled, {Offset? frozenLight}) {
    if (!enabled) {
      _ticker.stop();
      _stopSensor();
      _pending = null;
      _held = false;
      final next = frozenLight ?? rest;
      if (light != next || time != 0 || tilt != Offset.zero) {
        light = next;
        time = 0;
        tilt = Offset.zero;
        notifyListeners();
      }
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
      _startSensor();
    }
  }

  void _startSensor() {
    if (_gyroscope == null &&
        (kIsWeb ||
            !const [TargetPlatform.android, TargetPlatform.iOS]
                .contains(defaultTargetPlatform))) {
      return;
    }
    _sensorActive = true;
    _sensor = (_gyroscope ??
            gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval))
        .listen(_rotate,
            onError: (Object _) => _resetSensor(),
            onDone: _resetSensor,
            cancelOnError: true);
  }

  void _resetSensor() {
    _sampleTime = null;
    _rotation = Offset.zero;
    _held = false;
    _pending = null;
    _sensorActive = false;
  }

  void _stopSensor() {
    _sensor?.cancel();
    _sensor = null;
    _resetSensor();
  }

  void _rotate(GyroscopeEvent event) {
    if (!running || !_sensorActive) return;
    final previous = _sampleTime;
    _sampleTime = event.timestamp;
    if (previous == null) return;
    final dt = event.timestamp.difference(previous).inMicroseconds / 1e6;
    // Ignore gaps after a suspended sensor rather than jumping on resume.
    if (dt <= 0 || dt > .2 || !event.x.isFinite || !event.y.isFinite) return;
    double rate(double value) => value.abs() < .01 ? 0 : value;
    _rotation += Offset(rate(event.y), rate(event.x)) * dt;
    _held = true;
    _pending = Offset((.5 + _rotation.dx / 1.1).clamp(0, 1),
        (.5 + _rotation.dy / 1.1).clamp(0, 1));
  }

  void _tick(Duration elapsed) {
    // Input follows display vsync; decorative movement invalidates at 30 fps.
    if (_pending == null &&
        !_held &&
        elapsed > Duration.zero &&
        elapsed - _last < const Duration(microseconds: 33333)) {
      return;
    }
    _last = elapsed;
    time = elapsed.inMicroseconds / 1e6;
    _aim = _pending ?? _aim;
    _pending = null;
    // The light and tilt ease towards device rotation without snapping.
    final target = _held
        ? _aim
        : Offset(.5 + math.sin(time / 1.7 + _phase.dx) * .35,
            .5 + math.sin(time / 2.3 + _phase.dy) * .3);
    light = Offset.lerp(light, target, .3)!;
    tilt = Offset.lerp(
        tilt,
        _held ? Offset((_aim.dx - .5) * 2, (_aim.dy - .5) * 2) : Offset.zero,
        .22)!;
    if (tilt.distance < .001) tilt = Offset.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopSensor();
    _ticker.dispose();
    super.dispose();
  }
}
