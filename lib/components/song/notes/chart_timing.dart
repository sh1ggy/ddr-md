/// Name: ChartTiming
/// Parent: ChartScroller
/// Description: The second<->beat curve a chart scrolls by. Extracted from
/// chart_scroller.dart so the timing math can be unit-tested directly rather
/// than through a mounted widget.
library;

import 'package:ddr_md/components/song_json.dart';

/// Maps wall-clock seconds to chart beats so the field can scroll beat-locked
/// (true DDR): arrows are spaced by beat, so a BPM rise speeds them up and a
/// stop freezes the field. Built once per chart from the note stream's exact
/// (second, beat) anchors plus the explicit stop intervals.
///
/// The curve is piecewise-linear in (second, beat): between anchors the BPM is
/// constant, so beat advances linearly with time; across a stop, beat is held
/// flat for the stop's duration. [beatAt] binary-searches the breakpoints.
class ChartTiming {
  // Parallel, strictly-increasing-in-second breakpoint arrays. `_beats` is
  // non-decreasing (flat across a stop). Beat is linearly interpolated between
  // consecutive breakpoints, and extrapolated past the ends at the adjacent
  // segment's slope so notes before the first / after the last anchor still map.
  final List<double> _seconds;
  final List<double> _beats;

  // Cumulative stop-seconds absorbed at or before each breakpoint: the running
  // total of flat (beat-held) time up to `_seconds[i]`. Lets the paused/scroll
  // view give stops real vertical extent (a note past a stop is pushed down by
  // the stop's duration) even though beat-locked scrolling collapses them to a
  // line. Parallel to `_seconds`/`_beats`.
  final List<double> _stopAccum;

  const ChartTiming._(this._seconds, this._beats, this._stopAccum);

  /// Empty map — used when a chart carries no BPM data; the caller then draws in
  /// the plain constant-time mode instead of consulting this.
  static const ChartTiming empty = ChartTiming._([], [], []);

  bool get isEmpty => _seconds.isEmpty;

  /// Build the second→beat curve analytically from the chart's BPM segments and
  /// stops (both in real wall-clock seconds, stops already baked into the BPM
  /// segment seconds). Walks each constant-tempo segment, inserting any stop
  /// inside it as a flat (beat-held) interval, so BPM changes localize exactly
  /// where they occur and stops freeze for precisely their duration.
  factory ChartTiming.build(List<Bpm> bpms, List<Stop> stops) {
    if (bpms.isEmpty) return empty;
    // Stops sorted by start second; consumed in order as we sweep the timeline.
    final sortedStops = [...stops.where((s) => s.dur > 0)]
      ..sort((a, b) => a.st.compareTo(b.st));

    final seconds = <double>[];
    final beats = <double>[];
    final stopAccum = <double>[];
    double beat = 0; // musical beat accumulated so far
    double stopped = 0; // cumulative stop-seconds absorbed so far
    void add(double s, double b) {
      // Keep seconds strictly increasing; coincident points (a stop exactly on a
      // segment edge) collapse to one, preserving the later (post-event) beat.
      if (seconds.isNotEmpty && (s - seconds.last).abs() < 1e-6) {
        beats[beats.length - 1] = b;
        stopAccum[stopAccum.length - 1] = stopped;
        return;
      }
      seconds.add(s);
      beats.add(b);
      stopAccum.add(stopped);
    }

    int si = 0;
    for (final seg in bpms) {
      final bps = seg.val / 60.0; // beats per (musical) second at this tempo
      double cursor = seg.st; // real-second cursor inside this segment
      add(cursor, beat);
      // Fold in any stops that begin within this segment, in order.
      while (si < sortedStops.length && sortedStops[si].st < seg.ed - 1e-9) {
        final stop = sortedStops[si];
        if (stop.st >= cursor - 1e-9) {
          // Advance to the stop start, accruing beats over the moving time.
          beat += (stop.st - cursor) * bps;
          add(stop.st, beat);
          // The halt: real time advances by dur, beat stays flat. Record the
          // absorbed stop-time so the paused view can re-expand it vertically.
          stopped += stop.dur;
          add(stop.st + stop.dur, beat);
          cursor = stop.st + stop.dur;
        }
        si++;
      }
      // Remainder of the segment after the last contained stop.
      beat += (seg.ed - cursor) * bps;
      add(seg.ed, beat);
    }
    if (seconds.length < 2) return empty;
    return ChartTiming._(seconds, beats, stopAccum);
  }

  /// Cumulative stop-seconds absorbed at or before wall-clock [second]: the
  /// total flat (beat-held) time up to that point. Within a stop it grows
  /// linearly to the stop's full duration, so differencing this across two
  /// seconds yields the stop-time strictly between them — what the paused view
  /// uses to give stops real vertical height while beat-locked scroll collapses
  /// them. Extrapolates flat past the ends (no stops outside the timeline).
  double stopSecondsAt(double second) {
    final n = _seconds.length;
    if (n == 0) return 0;
    if (second <= _seconds.first) return _stopAccum.first;
    if (second >= _seconds.last) return _stopAccum.last;
    int lo = 0, hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_seconds[mid] <= second) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final ds = _seconds[lo + 1] - _seconds[lo];
    if (ds.abs() < 1e-9) return _stopAccum[lo + 1];
    final f = (second - _seconds[lo]) / ds;
    return _stopAccum[lo] + f * (_stopAccum[lo + 1] - _stopAccum[lo]);
  }

  /// Beat at wall-clock [second], interpolating between breakpoints and
  /// extrapolating at the end slopes so out-of-range seconds still map linearly.
  double beatAt(double second) {
    final n = _seconds.length;
    if (n == 0) return second;
    if (second <= _seconds.first) {
      return _extrapolate(second, 0, 1, fallbackSlope: _slope(0, 1));
    }
    if (second >= _seconds.last) {
      return _extrapolate(second, n - 2, n - 1, fallbackSlope: _slope(n - 2, n - 1));
    }
    // Binary search for the segment [lo, lo+1] containing `second`.
    int lo = 0, hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_seconds[mid] <= second) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return _interp(second, lo, lo + 1);
  }

  /// Largest wall-clock second at or below [beat] — the inverse of [beatAt],
  /// resolving a stop (many seconds share one beat) to the stop's END so it
  /// serves as a conservative lower cull bound for the visible window.
  double secondAt(double beat) {
    final n = _beats.length;
    if (n == 0) return beat;
    if (beat <= _beats.first) {
      final s = _slope(0, 1);
      return s.abs() < 1e-9 ? _seconds.first : _seconds.first + (beat - _beats.first) / s;
    }
    if (beat >= _beats.last) {
      final s = _slope(n - 2, n - 1);
      return s.abs() < 1e-9 ? _seconds.last : _seconds.last + (beat - _beats.last) / s;
    }
    // Upper-bound search: last index whose beat <= target (beats non-decreasing).
    int lo = 0, hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_beats[mid] <= beat) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final db = _beats[lo + 1] - _beats[lo];
    if (db.abs() < 1e-9) return _seconds[lo + 1];
    final f = (beat - _beats[lo]) / db;
    return _seconds[lo] + f * (_seconds[lo + 1] - _seconds[lo]);
  }

  double _slope(int i, int j) {
    final ds = _seconds[j] - _seconds[i];
    if (ds.abs() < 1e-9) return 0;
    return (_beats[j] - _beats[i]) / ds;
  }

  double _interp(double second, int i, int j) {
    final ds = _seconds[j] - _seconds[i];
    if (ds.abs() < 1e-9) return _beats[i];
    final f = (second - _seconds[i]) / ds;
    return _beats[i] + f * (_beats[j] - _beats[i]);
  }

  double _extrapolate(double second, int i, int j,
          {required double fallbackSlope}) =>
      _beats[i] + (second - _seconds[i]) * fallbackSlope;
}
