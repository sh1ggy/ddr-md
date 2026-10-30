/// Name: EditionMotion
/// Parent: JacketEdition
/// Description: One frame-coalesced light source, with no widget rebuilds.
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/painting.dart';

class EditionMotion extends ChangeNotifier {
  EditionMotion(TickerProvider vsync) {
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
  Offset? _pending;
  // Where the pointer last was, which the light eases towards while held.
  Offset _aim = rest;
  bool _held = false;
  Duration _last = Duration.zero;
  double time = 0;
  bool get running => _ticker.isActive;

  void configure(bool enabled, {Offset? frozenLight}) {
    if (!enabled) {
      _ticker.stop();
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
    }
  }

  void point(Offset local, Size size) {
    if (!running || size.isEmpty) return;
    _held = true;
    _pending = Offset((local.dx / size.width).clamp(0, 1),
        (local.dy / size.height).clamp(0, 1));
  }

  void release() => _held = false;

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
    // The light and tilt ease to the pointer and back, so a pointer
    // arriving over the card never snaps it.
    final target = _held
        ? _aim
        : Offset(.5 + math.sin(time / 1.7 + _phase.dx) * .35,
            .5 + math.sin(time / 2.3 + _phase.dy) * .3);
    light = Offset.lerp(light, target, .3)!;
    tilt = Offset.lerp(
        tilt,
        _held ? Offset((light.dx - .5) * 2, (light.dy - .5) * 2) : Offset.zero,
        .22)!;
    if (tilt.distance < .001) tilt = Offset.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
