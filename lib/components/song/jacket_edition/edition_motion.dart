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
  Offset light = const Offset(.35, .3);
  Offset? _pending;
  bool _held = false;
  Duration _last = Duration.zero;
  double time = 0;
  bool get running => _ticker.isActive;

  void configure(bool enabled, {Offset? frozenLight}) {
    if (!enabled) {
      _ticker.stop();
      _pending = null;
      _held = false;
      final next = frozenLight ?? const Offset(.35, .3);
      if (light != next || time != 0) {
        light = next;
        time = 0;
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
        elapsed - _last < const Duration(microseconds: 33333)) {
      return;
    }
    _last = elapsed;
    time = elapsed.inMicroseconds / 1e6;
    light = _pending ??
        (_held
            ? light
            : Offset(.5 + math.sin(time / 1.7) * .35,
                .5 + math.sin(time / 2.3) * .3));
    _pending = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
