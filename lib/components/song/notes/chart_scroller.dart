/// Name: ChartScroller
/// Parent: ChartPreviewPage
/// Description: A scrolling step-chart preview. Reads a difficulty's note
/// stream (from assets/steps/<name>.json) and animates the arrows flowing up
/// toward the receptors, the way they appear in-game. Playback is driven by
/// wall-clock seconds carried on each note, so BPM changes, stops and hold
/// lengths render at true speed without reconstructing the timing grid.
/// Notes are drawn by a pluggable [Noteskin] (vector by default; official DDR
/// World sprites when dropped into assets/noteskin/).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// DDR "TURN" appearance modifier: a column permutation applied to the notes
/// while the receptors/panels stay in their fixed L-D-U-R positions. Matches the
/// DDR World option list — MIRROR is a 180° turn, LEFT/RIGHT are 90° turns.
/// (https://p.eagate.573.jp/game/ddr/ddrworld/howto/option_list.html)
enum _Turn { off, mirror, left, right }

/// Column map for [turn] over a [columnCount]-wide field: `map[oldCol]` is the
/// column the note now appears in. Receptors are unaffected. The single-panel
/// turns follow the standard StepMania tables (L D U R = 0 1 2 3):
///   MIRROR L↔R, U↔D  ·  LEFT (90° CCW) L→D→R→U→L  ·  RIGHT (90° CW) L→U→R→D→L.
/// For doubles, MIRROR reverses the whole 8-panel row; LEFT/RIGHT turn each pad
/// half on its own, which keeps the per-foot motion intact.
List<int> _turnColumnMap(_Turn turn, int columnCount) {
  if (turn == _Turn.off) {
    return [for (int c = 0; c < columnCount; c++) c];
  }
  // Per-4-panel single turns, as offsets within a pad (L D U R = 0 1 2 3).
  const single = {
    _Turn.mirror: [3, 2, 1, 0],
    _Turn.left: [1, 3, 0, 2],
    _Turn.right: [2, 0, 3, 1],
  };
  if (columnCount == 4) return single[turn]!;
  if (columnCount == 8) {
    if (turn == _Turn.mirror) {
      return [for (int c = 7; c >= 0; c--) c]; // full 180° across both pads
    }
    final pad = single[turn]!;
    // Apply the single turn independently to each 4-panel half.
    return [for (final c in pad) c, for (final c in pad) c + 4];
  }
  // Unknown width: identity (no turn) rather than risk an out-of-range map.
  return [for (int c = 0; c < columnCount; c++) c];
}

/// A row of simultaneous mines spanning most/all columns — a DDR shock arrow,
/// which is drawn as a single bar per lane rather than individual mines.
class _ShockRow {
  final double second;
  final Set<int> cols;
  const _ShockRow(this.second, this.cols);
}

class _MinimapSegment {
  final Color color;
  final double weight;
  const _MinimapSegment(this.color, this.weight);
}

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

/// A tempo change at [second], to [bpm]. Only real transitions are kept (the
/// song's opening BPM is not a "change"), so the field isn't cluttered with a
/// marker at t=0 on every chart.
class _BpmMarker {
  final double second;
  final int bpm;
  const _BpmMarker(this.second, this.bpm);
}

/// A stop of [dur] seconds starting at [second]. Rendered as a band spanning its
/// duration on the scroll field so its length reads at a glance.
class _StopMarker {
  final double second;
  final double dur;
  const _StopMarker(this.second, this.dur);
}

class _MinimapBucket {
  final double level;
  final List<_MinimapSegment> segments;
  final double holdLevel;
  final bool hasShock;
  const _MinimapBucket({
    required this.level,
    required this.segments,
    required this.holdLevel,
    required this.hasShock,
  });
}

class ChartScroller extends StatefulWidget {
  const ChartScroller({
    super.key,
    required this.steps,
    required this.mode,
    required this.songLength,
    required this.chartBpm,
    this.bpms = const [],
    this.stops = const [],
    this.showFootGuide = false,
    this.headerBuilder,
  });

  final ChartSteps steps;
  final Modes mode;

  /// Optional floating header (title / back / actions) laid over the top of the
  /// full-bleed field. Shown and hidden together with the transport controls.
  /// The settings shade is opened by the scroller's own left-edge pull-tab, so
  /// the header carries no settings affordance.
  final Widget Function(BuildContext context)? headerBuilder;

  /// Timing markers, in seconds (from [Chart]). [bpms] carry a [Bpm.st] start
  /// second and target [Bpm.val]; [stops] carry a [Stop.st] start and [Stop.dur]
  /// duration. Both live on the same seconds axis the note stream scrolls on, so
  /// they render at true position without any extra timing reconstruction.
  final List<Bpm> bpms;
  final List<Stop> stops;

  /// Overlay an L/R parity guide on each arrow (best-effort, computed on load).
  final bool showFootGuide;

  /// Song length in seconds; bounds the scrub slider and the auto-stop point.
  final double songLength;

  /// Dominant chart BPM used to convert a DDR read-speed target into the
  /// nearest x-mod for the preview.
  final int chartBpm;

  @override
  State<ChartScroller> createState() => _ChartScrollerState();
}

class _ChartScrollerState extends State<ChartScroller>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // Virtual playhead in seconds. Notes at this second sit on the receptor line.
  double _second = 0;
  bool _playing = false;

  // Whether the floating controls (header + transport) are shown. The field is
  // full-bleed underneath; hiding the controls hands the whole screen to the
  // chart. Toggled by a small always-visible handle, never by tapping the field
  // (that stays play/pause).
  bool _controlsVisible = true;

  // Whether the top settings shade (chart-viewing modifiers) is pulled down.
  // Opened from the left-edge pull-tab; auto-closed when playback starts, and
  // never shown while playing (it's a paused-browsing surface).
  bool _shadeOpen = false;

  // Scroll rate multiplier (visual speed-mod feel). 1.0 = default spacing.
  double _rate = 1.0;
  int _modIndex = 3; // 1.0x in constants.mods

  // Pinch-to-zoom: a purely visual multiplier on the vertical note spacing,
  // independent of the read-speed mod. <1 zooms OUT (compresses more beats into
  // the viewport so you can study long chunks at once); zooming in beyond 1x is
  // disallowed since READ SPEED already covers that. It scales
  // [_pxPerBeat]/[_pxPerSecond] on top of [_rate], so the whole render — the
  // cull window, CONSTANT, markers, foot paths — stretches with it for free and
  // the READ SPEED number the user dialled in is left untouched. Reset to 1.0
  // whenever a new chart loads (a study lens, not a persisted setting).
  static const double _minZoom = 0.25;
  static const double _maxZoom = 1.0;
  double _zoom = 1.0;
  // Zoom captured at the start of a pinch, so mid-gesture updates scale from the
  // level the fingers landed on rather than compounding each frame.
  double _pinchStartZoom = 1.0;

  // DDR CONSTANT modifier: fade arrows in a fixed wall-clock time before they
  // reach the receptor, independent of BPM/read speed. Off by default (NORMAL).
  // [_constantMs] is the display time in ms (100–3000, snapped to 10ms); it's
  // handed to the painter only while [_constantOn]. Persisted across previews.
  static const double _constantMinMs = 100;
  static const double _constantMaxMs = 3000;
  static const double _constantStepMs = 10;
  static const double _constantDefaultMs = 1000;
  bool _constantOn = false;
  double _constantMs = _constantDefaultMs;

  // DDR TURN modifier: permutes which panel each note lands on (receptors stay
  // put). OFF by default; persisted across previews. See [_Turn].
  _Turn _turn = _Turn.off;

  // Playback-rate multiplier: how fast the chart plays back in wall-clock time.
  // 1.0 = true speed; <1 slows the song, >1 speeds it up. Independent of the
  // read-speed (note-spacing) mod above.
  double _playbackRate = 1.0;
  static const double _minPlaybackRate = 0.25;
  static const double _maxPlaybackRate = 1.0;

  // Tap-and-hold fast-forward: while the finger is held down on the field
  // without dragging, playback temporarily doubles. Releasing (or the hold
  // losing the gesture arena to a drag) restores the rate that was active
  // before the hold started, not a hardcoded 1.0 — so it composes with the
  // song-speed control instead of clobbering it.
  static const double _holdSpeedMultiplier = 2.0;
  static const double _maxHoldPlaybackRate = 2.0;
  double? _preHoldPlaybackRate;
  bool _holdFastForward = false;

  // Notes that are part of a shock row are drawn as bars, not mines, so the
  // painter skips them and draws [_shocks] instead.
  final Set<StepNote> _shockNotes = {};
  final List<_ShockRow> _shocks = [];

  // Tempo-change and stop markers, in chart seconds, built once from the chart's
  // timing so the field and minimap can show where the song shifts speed / halts.
  List<_BpmMarker> _bpmMarkers = const [];
  List<_StopMarker> _stopMarkers = const [];

  // Second→beat map for beat-locked scrolling: arrows are spaced by beat, so
  // BPM changes speed the field up/down and stops freeze it. Empty when the
  // chart carries no BPM data, in which case the field scrolls by constant time.
  ChartTiming _timing = ChartTiming.empty;

  // Best-effort L/R foot parity for the current chart, computed once on load
  // (client-side, so the heuristic is tunable without regenerating assets).
  Map<StepNote, Foot> _feet = const {};

  // Real DDR World sprites when bundled (assets/noteskin/), else vector. The
  // sprite skin loads asynchronously; until then (or if absent) we draw vector.
  Noteskin _skin = const VectorNoteskin();

  // Note-density histogram with per-bucket rhythm-color composition for the
  // scrub minimap, built once from the chart so seeking shows both intensity
  // and the kinds of notes waiting there.
  List<_MinimapBucket> _minimap = const [];

  // Pixels a note travels per second of chart time, before [_rate]. Tuned so a
  // typical stream sits at DDR World-ish spacing (arrows fairly close together)
  // rather than sparse; the speed slider scales this either way.
  static const double _basePxPerSecond = 200;

  double get _pxPerSecond => _basePxPerSecond * _rate * _zoom;

  // Beat-locked spacing: pixels per chart beat. In DDR the scroll VELOCITY is the
  // read speed (BPM × mod), so faster songs fly and slower ones crawl at the same
  // x-mod. A beat spans 60/localBpm seconds, so to make velocity = localBpm × rate
  // px/s the per-beat pixels must be (localBpm × rate) × (60/localBpm) = 60 × rate
  // — chart- and tempo-independent. This is why a note's on-screen speed then
  // tracks the LOCAL tempo (via [ChartTiming]'s slope), not the dominant BPM: a
  // 360-BPM stretch scrolls twice as fast as a 180-BPM one at the same read speed.
  //
  // Anchoring instead to the dominant BPM (the old behaviour) collapsed every
  // chart to _basePxPerSecond × rate px/s at its dominant tempo, so a 360-BPM song
  // crept by at the same pixels/second as a 120-BPM one — the read speed became a
  // pure spacing knob with no bearing on actual vertical velocity.
  static const double _pxPerReadSpeedUnit = 1.0;
  double get _pxPerBeat => _pxPerReadSpeedUnit * _rate * 60.0 * _zoom;

  int get _effectiveChartBpm => widget.chartBpm > 0 ? widget.chartBpm : constants.songBpm;
  int get _currentReadSpeed => (_effectiveChartBpm * _rate).round();

  // BPM of the tempo section under the playhead — NOT the dominant chart BPM.
  // Looked up on the raw [Bpm] segments rather than [ChartTiming]'s slope, which
  // flattens to zero inside a stop and would read "BPM 0" mid-halt instead of
  // the enclosing tempo. Charts without segments fall back to the dominant BPM.
  int get _localBpm {
    final bpms = widget.bpms;
    if (bpms.isEmpty) return _effectiveChartBpm;
    // Last segment whose start is at or before the playhead (segments sorted).
    int lo = 0, hi = bpms.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (bpms[mid].st <= _second) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return bpms[lo].val;
  }

  // Receptor-to-bottom-edge run of the field in px at zoom 1, captured each
  // build from the layout. This is the distance an arrow is visible for when
  // nothing hides it, which is what converts CONSTANT's wall-clock window into
  // an equivalent read speed. Zero until first layout.
  double _receptorRunPx = 0;

  // CONSTANT expressed as a read speed: the read speed whose full-field travel
  // time equals the CONSTANT window. Velocity at read speed R is
  // R × [_pxPerReadSpeedUnit] px/s (see [_pxPerBeat]), so R = 1000·H / (unit·ms)
  // for a run of H px. Deliberately ignores [_zoom] — like the READ SPEED knob,
  // this describes the dialled-in setting, not the temporary study lens.
  // Null when CONSTANT is off or the field hasn't laid out yet.
  int? get _constantReadSpeed {
    final c = _effectiveConstantMs;
    if (c == null || _receptorRunPx <= 0) return null;
    return (1000.0 * _receptorRunPx / (_pxPerReadSpeedUnit * c)).round();
  }

  // Read speed the CURRENT tempo section actually reads at. Without CONSTANT
  // this is just localBpm × mod. With CONSTANT it's the max of that and the
  // window's equivalent read speed: CONSTANT only hides arrows still beyond its
  // window, so slow sections are clamped up to a uniform read while sections
  // already faster than the window pass through unchanged.
  int get _liveReadSpeed {
    final local = _localBpm * _rate;
    final rc = _constantReadSpeed;
    return math.max(local, (rc ?? 0).toDouble()).round();
  }

  // Whether the CONSTANT window (not the section's own tempo) is what bounds
  // the live read speed — i.e. CONSTANT is actively hiding arrows here.
  bool get _constantBinds {
    final rc = _constantReadSpeed;
    return rc != null && rc > _localBpm * _rate;
  }

  double get _endSecond =>
      widget.songLength > 0 ? widget.songLength : _lastNoteSecond();

  double _lastNoteSecond() {
    if (widget.steps.notes.isEmpty) return 0;
    final n = widget.steps.notes.last;
    return (n.endSecond ?? n.second) + 1;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _syncRateToSavedReadSpeed();
    _loadConstant();
    _loadTurn();
    _detectShocks();
    _assignFeet();
    _buildTimingMarkers();
    _buildDensity();
    // Prefer real DDR World sprites if they're bundled; repaint once loaded.
    SpriteNoteskin.tryLoad().then((skin) {
      if (skin != null && mounted) setState(() => _skin = skin);
    });
  }

  @override
  void didUpdateWidget(ChartScroller old) {
    super.didUpdateWidget(old);
    // Switching difficulty/mode restarts the preview from the top.
    if (old.steps != widget.steps ||
        old.mode != widget.mode ||
        old.bpms != widget.bpms ||
        old.stops != widget.stops) {
      _pause();
      _detectShocks();
      _assignFeet();
      _buildTimingMarkers();
      _buildDensity();
      setState(() {
        _second = 0;
        _zoom = 1.0; // the study lens is per-chart; snap back on a new chart
      });
    }
    if (old.chartBpm != widget.chartBpm) {
      _syncRateToSavedReadSpeed();
    }
  }

  void _syncRateToSavedReadSpeed() {
    final saved = Settings.getInt(Settings.chosenReadSpeedKey);
    final desired = saved > 0 ? saved : constants.chosenReadSpeed;
    final nextIndex = findNearestReadSpeed(
      _effectiveChartBpm,
      constants.mods,
      desired,
    );
    _modIndex = nextIndex.clamp(0, constants.mods.length - 1);
    _rate = constants.mods[_modIndex];
  }

  // Restore the CONSTANT modifier from settings. A saved ms of 0 means "never
  // set", so fall back to the DDR default; the on/off flag is stored as 0/1
  // (the Settings API has no bool getter).
  void _loadConstant() {
    final savedMs = Settings.getInt(Settings.constantMsKey);
    _constantMs = savedMs > 0
        ? savedMs.toDouble().clamp(_constantMinMs, _constantMaxMs)
        : _constantDefaultMs;
    _constantOn = Settings.getInt(Settings.constantOnKey) == 1;
  }

  // The ms value handed to the painter: null (NORMAL, arrows always visible)
  // unless the modifier is switched on.
  double? get _effectiveConstantMs => _constantOn ? _constantMs : null;

  // Restore the TURN modifier from settings (0=OFF,1=MIRROR,2=LEFT,3=RIGHT).
  void _loadTurn() {
    final saved = Settings.getInt(Settings.chartPreviewTurnKey);
    _turn = (saved >= 0 && saved < _Turn.values.length)
        ? _Turn.values[saved]
        : _Turn.off;
  }

  // The column permutation handed to the painter for the current turn + mode.
  List<int> get _colMap => _turnColumnMap(
        _turn,
        widget.mode == Modes.singles ? kSingleDirs.length : kDoubleDirs.length,
      );

  // Select a TURN modifier; tapping the active one turns it OFF (except MIRROR,
  // which is its own toggle). Persisted so it carries across previews.
  void _setTurn(_Turn turn) {
    HapticFeedback.selectionClick();
    final next = _turn == turn ? _Turn.off : turn;
    setState(() => _turn = next);
    Settings.setInt(Settings.chartPreviewTurnKey, next.index);
    _flashScrubOverlay(_turnLabel(next), "TURN");
  }

  String _turnLabel(_Turn turn) => switch (turn) {
        _Turn.off => "OFF",
        _Turn.mirror => "MIRROR",
        _Turn.left => "LEFT",
        _Turn.right => "RIGHT",
      };

  // Tap the CONSTANT chip to switch the modifier on/off (no separate switch).
  void _toggleConstant() {
    HapticFeedback.selectionClick();
    setState(() => _constantOn = !_constantOn);
    Settings.setInt(Settings.constantOnKey, _constantOn ? 1 : 0);
    _flashScrubOverlay(
      _constantOn ? "${_constantMs.round()}ms" : "OFF",
      _constantCaption,
    );
  }

  // Overlay caption for CONSTANT flashes: carries the window's equivalent read
  // speed (see [_constantReadSpeed]) so dialling a wall-clock time immediately
  // reads in the unit players actually think in.
  String get _constantCaption {
    final eq = _constantReadSpeed;
    return eq != null ? "CONSTANT ≈ C$eq" : "CONSTANT";
  }

  // Drag horizontally on the CONSTANT chip to sweep the display time, snapped to
  // the 10ms grid. Mirrors the song-speed pane's drag feel; fires a detent
  // haptic each time the value crosses a step. Dragging implicitly turns the
  // modifier on so the change is visible while adjusting.
  void _onConstantDrag(double dx) {
    final next = (_constantMs + dx / 260 * (_constantMaxMs - _constantMinMs))
        .clamp(_constantMinMs, _constantMaxMs);
    final snapped =
        ((next / _constantStepMs).round() * _constantStepMs).toDouble();
    final changed = snapped != _constantMs;
    if (!changed && _constantOn) return;
    setState(() {
      _constantMs = snapped;
      _constantOn = true;
    });
    if (changed) HapticFeedback.selectionClick();
    Settings.setInt(Settings.constantMsKey, snapped.round());
    Settings.setInt(Settings.constantOnKey, 1);
    _flashScrubOverlay("${snapped.round()}ms", _constantCaption);
  }

  static const List<Color> _minimapPalette = [
    QuantColors.quarter,
    QuantColors.eighth,
    QuantColors.twelfth,
    QuantColors.sixteenth,
    QuantColors.twentyfourth,
    QuantColors.thirtysecond,
    QuantColors.other,
  ];

  int _quantBucketForBeat(double beat) {
    final color = QuantColors.forBeat(beat);
    for (int i = 0; i < _minimapPalette.length; i++) {
      if (_minimapPalette[i] == color) return i;
    }
    return _minimapPalette.length - 1;
  }

  // Bucket notes into ~200 columns by time, counting arrows per bucket and
  // keeping the quant-colour mix so the minimap previews both density and feel.
  void _buildDensity() {
    const buckets = 200;
    final end = _endSecond;
    final counts = List<double>.filled(buckets, 0);
    final holdCounts = List<double>.filled(buckets, 0);
    final shockFlags = List<bool>.filled(buckets, false);
    final colorCounts = List.generate(
      buckets,
      (_) => List<int>.filled(_minimapPalette.length, 0),
    );
    if (end > 0) {
      for (final n in widget.steps.notes) {
        if (n.type == StepType.mine) continue; // shocks handled separately below
        final b = ((n.second / end) * buckets).floor().clamp(0, buckets - 1);
        counts[b] += 1;
        colorCounts[b][_quantBucketForBeat(n.beat)] += 1;
        if (n.isHold) {
          final endSecond = n.endSecond ?? n.second;
          final endBucket =
              ((endSecond / end) * buckets).floor().clamp(0, buckets - 1);
          for (int i = b; i <= endBucket; i++) {
            holdCounts[i] += 1;
          }
        }
      }
      for (final shock in _shocks) {
        final b =
            ((shock.second / end) * buckets).floor().clamp(0, buckets - 1);
        shockFlags[b] = true;
      }
    }
    final peak = counts.fold<double>(0, (m, v) => v > m ? v : m);
    final holdPeak = holdCounts.fold<double>(0, (m, v) => v > m ? v : m);
    _minimap = List<_MinimapBucket>.generate(buckets, (i) {
      final total = counts[i];
      final segments = <_MinimapSegment>[];
      if (total > 0) {
        for (int j = 0; j < _minimapPalette.length; j++) {
          final count = colorCounts[i][j];
          if (count == 0) continue;
          segments.add(_MinimapSegment(_minimapPalette[j], count / total));
        }
      }
      return _MinimapBucket(
        level: peak > 0 ? total / peak : 0,
        segments: segments,
        holdLevel: holdPeak > 0 ? holdCounts[i] / holdPeak : 0,
        hasShock: shockFlags[i],
      );
    });
  }

  void _assignFeet() {
    _feet = FootAssigner.assign(widget.steps.notes, widget.mode);
  }

  // Distil the chart's BPM segments and stops into render-ready markers on the
  // seconds axis. A BPM segment is only a "change" when its value differs from
  // the one before it, so the leading segment (and any coalesced duplicates)
  // don't plant a redundant marker at the start of the field.
  void _buildTimingMarkers() {
    final bpm = <_BpmMarker>[];
    int? prev;
    for (final b in widget.bpms) {
      final v = b.val;
      if (prev != null && v != prev) {
        bpm.add(_BpmMarker(b.st, v));
      }
      prev = v;
    }
    _bpmMarkers = bpm;
    _stopMarkers = [
      for (final s in widget.stops)
        if (s.dur > 0) _StopMarker(s.st, s.dur),
    ];
    _timing = ChartTiming.build(widget.bpms, widget.stops);
  }

  // Normalise marker seconds to 0..1 across the chart's length for the minimap.
  List<double> _markerFractions(Iterable<double> seconds) {
    final end = _endSecond;
    if (end <= 0) return const [];
    return [
      for (final s in seconds) (s / end).clamp(0.0, 1.0),
    ];
  }

  // Group mines by (rounded) second; any group covering 3+ columns is a shock
  // row. Cheap one-pass grouping done once per chart load.
  void _detectShocks() {
    _shockNotes.clear();
    _shocks.clear();
    final Map<int, List<StepNote>> byTime = {};
    for (final n in widget.steps.notes) {
      if (n.type != StepType.mine) continue;
      final key = (n.second * 1000).round();
      (byTime[key] ??= []).add(n);
    }
    byTime.forEach((_, mines) {
      if (mines.length >= 3) {
        _shocks.add(_ShockRow(mines.first.second, {for (final m in mines) m.col}));
        _shockNotes.addAll(mines);
      }
    });
  }

  // Momentum for drag-flings: seconds-of-chart per real second, decaying by
  // [_flingDecay] each real second until it dies out. Separate from playback.
  double _flingVel = 0;
  static const double _flingDecay = 2.6; // higher = stops sooner
  static const double _flingMin = 0.02; // velocity below which we settle

  // Tap feedback: briefly flash play/pause icon like video players, but subtle.
  IconData? _tapOverlayIcon;
  bool _showTapOverlay = false;
  Timer? _tapOverlayTimer;

  // Scrub feedback: a large centred value that flashes while horizontally
  // scrubbing a control (song speed / read speed), fading out shortly after the
  // gesture settles so the change reads at a glance without watching the pane.
  String? _scrubOverlayLabel;
  String? _scrubOverlayCaption;
  bool _showScrubOverlay = false;
  Timer? _scrubOverlayTimer;

  // Double-tap seek feedback: a YouTube-style flash on the side of the field
  // that was tapped, showing the skip direction and amount. `_seekOverlayLeft`
  // picks which half lights up; re-tapping the same side while the flash is
  // still up restarts the timer so rapid double-taps keep it lit.
  bool _showSeekOverlay = false;
  bool _seekOverlayLeft = false;
  Timer? _seekOverlayTimer;

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;

    setState(() {
      if (_playing) {
        _second += dt * _playbackRate;
      } else if (_flingVel != 0) {
        // Inertial scrub: advance by the current velocity, then decay it.
        _second += _flingVel * dt;
        _flingVel *= math.exp(-_flingDecay * dt);
        if (_flingVel.abs() < _flingMin) {
          _flingVel = 0;
          _stopTickerIfIdle();
        }
      }
      if (_second >= _endSecond) {
        _second = _endSecond;
        _flingVel = 0;
        _pause();
        _stopTickerIfIdle();
      } else if (_second <= 0) {
        _second = 0;
        _flingVel = 0;
        _stopTickerIfIdle();
      }
    });
  }

  // The ticker runs whenever there's motion (playback OR a live fling). Stop it
  // when neither is active to avoid needless repaints.
  void _stopTickerIfIdle() {
    if (!_playing && _flingVel == 0 && _ticker.isTicking) _ticker.stop();
  }

  void _ensureTicking() {
    if (!_ticker.isTicking) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _play() {
    if (_playing) return;
    if (_second >= _endSecond) _second = 0;
    _flingVel = 0;
    _ensureTicking();
    // The settings shade is a paused-browsing surface — starting playback tucks
    // it away so it never overlays the running chart.
    setState(() {
      _playing = true;
      _shadeOpen = false;
    });
  }

  void _toggleShade() {
    HapticFeedback.selectionClick();
    // Opening the shade pauses playback so the modifiers are adjusted against a
    // still field, matching the arcade's option screen.
    if (!_shadeOpen) _pause();
    setState(() => _shadeOpen = !_shadeOpen);
  }

  void _pause() {
    if (!_playing) return;
    setState(() => _playing = false);
    _stopTickerIfIdle();
  }

  void _flashTapOverlay(bool playing) {
    _tapOverlayTimer?.cancel();
    setState(() {
      _tapOverlayIcon = playing ? Icons.play_arrow : Icons.pause;
      _showTapOverlay = true;
    });
    _tapOverlayTimer = Timer(const Duration(milliseconds: 360), () {
      if (!mounted) return;
      setState(() => _showTapOverlay = false);
    });
  }

  // Flash the big centred scrub value. Kept up while the drag is live (each
  // update re-arms the timer), then fades a short beat after the finger lifts.
  void _flashScrubOverlay(String label, String caption) {
    _scrubOverlayTimer?.cancel();
    setState(() {
      _scrubOverlayLabel = label;
      _scrubOverlayCaption = caption;
      _showScrubOverlay = true;
    });
    _scrubOverlayTimer = Timer(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      setState(() => _showScrubOverlay = false);
    });
  }

  void _togglePlay({bool showOverlay = false}) {
    HapticFeedback.selectionClick();
    final willPlay = !_playing;
    _playing ? _pause() : _play();
    if (showOverlay) _flashTapOverlay(willPlay);
  }

  static const double _seekStepSeconds = 5.0;

  // Double-tap seek: jump ±5s and flash an indicator on the tapped side. Works
  // whether paused or playing — seeking while playing just relocates the
  // playhead and playback continues from there.
  void _seek(bool forward) {
    HapticFeedback.mediumImpact();
    final delta = forward ? _seekStepSeconds : -_seekStepSeconds;
    setState(() => _second = (_second + delta).clamp(0.0, _endSecond));
    _flashSeekOverlay(!forward);
  }

  void _flashSeekOverlay(bool left) {
    _seekOverlayTimer?.cancel();
    setState(() {
      _seekOverlayLeft = left;
      _showSeekOverlay = true;
    });
    _seekOverlayTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() => _showSeekOverlay = false);
    });
  }

  // Tap-and-hold fast-forward: doubles playback rate for as long as the finger
  // stays down without turning into a drag. `_preHoldPlaybackRate` remembers
  // the rate to restore, since the song-speed control may have already set it
  // away from 1.0. Holding while paused starts playback for the duration of
  // the hold; `_resumeFromHold` tracks that so releasing returns to paused
  // rather than leaving playback running.
  bool _resumeFromHold = false;

  void _onHoldSpeedStart() {
    if (_holdFastForward) return;
    _preHoldPlaybackRate = _playbackRate;
    HapticFeedback.mediumImpact();
    setState(() {
      _holdFastForward = true;
      _playbackRate = (_playbackRate * _holdSpeedMultiplier)
          .clamp(_minPlaybackRate, _maxHoldPlaybackRate);
    });
    if (!_playing) {
      _resumeFromHold = true;
      _play();
    }
  }

  void _onHoldSpeedEnd() {
    if (!_holdFastForward) return;
    final restore = _preHoldPlaybackRate ?? 1.0;
    _preHoldPlaybackRate = null;
    setState(() {
      _holdFastForward = false;
      _playbackRate = restore;
    });
    if (_resumeFromHold) {
      _resumeFromHold = false;
      _pause();
    }
  }

  void _stepReadSpeed(int delta) {
    final newIndex = _modIndex + delta;
    if (newIndex < 0 || newIndex >= constants.mods.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _modIndex = newIndex;
      _rate = constants.mods[_modIndex];
    });
    _flashScrubOverlay("$_currentReadSpeed", "READ SPEED");
  }

  // Drag on the read-speed pane: horizontal movement steps through the mod list.
  // Accumulate sub-step pixels so a slow drag still lands on each mod in turn.
  double _readSpeedDragAccum = 0;
  static const double _pxPerReadSpeedStep = 22;

  void _onReadSpeedDrag(double dx) {
    _readSpeedDragAccum += dx;
    while (_readSpeedDragAccum.abs() >= _pxPerReadSpeedStep) {
      final dir = _readSpeedDragAccum > 0 ? 1 : -1;
      _readSpeedDragAccum -= dir * _pxPerReadSpeedStep;
      final next = _modIndex + dir;
      if (next < 0 || next >= constants.mods.length) {
        _readSpeedDragAccum = 0;
        break;
      }
      _stepReadSpeed(dir);
    }
  }

  // Drag on the song-speed pane: horizontal movement scales the playback rate.
  // Fire a detent haptic each time the rate crosses one of the 0.05× steps the
  // value snaps to on-screen, so the sweep ticks under the finger.
  void _onPlaybackRateDrag(double dx) {
    final next = (_playbackRate + dx / 260)
        .clamp(_minPlaybackRate, _maxPlaybackRate);
    if (next == _playbackRate) return;
    final crossedStep =
        (next * 20).round() != (_playbackRate * 20).round();
    setState(() => _playbackRate = next);
    if (crossedStep) HapticFeedback.selectionClick();
    _flashScrubOverlay("${next.toStringAsFixed(2)}×", "SONG SPEED");
  }

  void _resetPlaybackRate() {
    if (_playbackRate == 1.0) return;
    HapticFeedback.selectionClick();
    setState(() => _playbackRate = 1.0);
  }

  // --- drag-to-scrub with momentum ---

  // Whole-beat index of the playhead at the last scrub tick, so a manual
  // vertical scrub can fire one detent haptic per beat crossed as notes pass the
  // receptor — the field feels "notched" to the rhythm instead of glassy.
  int? _lastScrubBeat;

  int _beatIndexAt(double second) {
    final beat = _timing.isEmpty
        ? second * _effectiveChartBpm / 60.0
        : _timing.beatAt(second);
    return beat.floor();
  }

  // Convert a vertical pixel distance to chart-seconds at the playhead, so a
  // drag/fling moves the field by exactly the pixels the finger travelled. In
  // beat-locked mode a pixel is a fixed slice of a beat, stretching/compressing
  // with the local tempo. Scrubbing always happens paused, where stops are given
  // real vertical extent ([expandStops] in the painter), so we invert that SAME
  // combined mapping here — otherwise a pixel over a stop would map to ~0 seconds
  // and the finger would slide across the (now visible) stop band without moving
  // the playhead through it.
  double _pxToSeconds(double px) {
    if (_timing.isEmpty) return px / _pxPerSecond;
    // Combined on-screen pixel offset from the playhead for a note at second t:
    // beat-distance plus the re-expanded stop-time between them.
    final baseBeat = _timing.beatAt(_second);
    final baseStop = _timing.stopSecondsAt(_second);
    double offsetPx(double t) =>
        (_timing.beatAt(t) - baseBeat) * _pxPerBeat +
        (_timing.stopSecondsAt(t) - baseStop) * _pxPerSecond;

    // offsetPx is monotone non-decreasing in t; binary-search the second whose
    // combined offset matches `px`. Bracket with a generous beat-only estimate
    // (which ignores stop pixels, so it always over-reaches in seconds), padded.
    final rough = _timing.secondAt(baseBeat + px / _pxPerBeat) - _second;
    double lo = math.min(0.0, rough) - 0.5;
    double hi = math.max(0.0, rough) + 0.5;
    for (int i = 0; i < 40; i++) {
      final mid = (lo + hi) / 2;
      if (offsetPx(_second + mid) < px) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  // --- unified scale gesture (pan + pinch on the field) ---
  //
  // A single ScaleGestureRecognizer handles all field drags because Flutter
  // forbids a pinch recognizer from coexisting with the pan/drag recognizers in
  // one detector. With one finger down it behaves exactly like the old
  // vertical-scrub / horizontal-song-speed drags; with two it becomes
  // pinch-to-zoom on the vertical note spacing. The mode is decided on the first
  // move of the gesture and held for its duration so a scrub never mutates into
  // a zoom (or vice-versa) mid-drag.
  static const int _gestureNone = 0;
  static const int _gestureScrub = 1;
  static const int _gestureSpeed = 2;
  static const int _gestureZoom = 3;
  int _gestureMode = _gestureNone;
  Offset _lastScaleFocal = Offset.zero;

  void _onScaleStart(ScaleStartDetails d) {
    _gestureMode = _gestureNone; // decided on first movement
    _lastScaleFocal = d.localFocalPoint;
    _pinchStartZoom = _zoom;
    if (d.pointerCount >= 2) {
      // Two fingers land at once: it's a pinch from the outset.
      _gestureMode = _gestureZoom;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // Promote to a pinch the moment a second finger joins, even mid-drag.
    if (d.pointerCount >= 2 && _gestureMode != _gestureZoom) {
      _gestureMode = _gestureZoom;
      _pinchStartZoom = _zoom;
    }

    if (_gestureMode == _gestureZoom) {
      _applyPinchZoom(d.scale);
      _lastScaleFocal = d.localFocalPoint;
      return;
    }

    final delta = d.localFocalPoint - _lastScaleFocal;
    _lastScaleFocal = d.localFocalPoint;

    // First single-finger movement picks the axis: a steeper move scrubs the
    // field, a flatter one drives song speed — and that choice sticks.
    if (_gestureMode == _gestureNone) {
      if (delta == Offset.zero) return;
      _gestureMode =
          delta.dy.abs() >= delta.dx.abs() ? _gestureScrub : _gestureSpeed;
      if (_gestureMode == _gestureScrub) _onScrubStart();
    }

    if (_gestureMode == _gestureScrub) {
      _onScrubMove(delta.dy);
    } else if (_gestureMode == _gestureSpeed) {
      _onPlaybackRateDrag(delta.dx);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_gestureMode == _gestureScrub) {
      // Coast a fling from the release velocity, as the old vertical drag did.
      final vPx = d.velocity.pixelsPerSecond.dy;
      _flingVel = -_pxToSeconds(vPx);
      if (_flingVel.abs() < _flingMin) {
        _flingVel = 0;
      } else {
        _ensureTicking();
      }
    }
    _gestureMode = _gestureNone;
  }

  // Map a live pinch scale (1.0 at gesture start) onto the zoom multiplier,
  // anchored to the level the fingers landed on. Pinching apart zooms in (denser
  // spacing), together zooms out (see more chart). Flashes the current factor.
  void _applyPinchZoom(double scale) {
    final next = (_pinchStartZoom * scale).clamp(_minZoom, _maxZoom);
    if (next == _zoom) return;
    setState(() => _zoom = next);
    _flashScrubOverlay("${next.toStringAsFixed(2)}×", "ZOOM");
  }

  // Single-finger vertical scrub, split out of the old onVerticalDrag* so the
  // unified scale handler can drive the same beat-detented scrubbing.
  void _onScrubStart() {
    _pause();
    _flingVel = 0;
    _lastScrubBeat = _beatIndexAt(_second);
  }

  void _onScrubMove(double dy) {
    setState(() {
      _second = (_second - _pxToSeconds(dy)).clamp(0.0, _endSecond);
    });
    final beat = _beatIndexAt(_second);
    if (_lastScrubBeat != null && beat != _lastScrubBeat) {
      HapticFeedback.selectionClick();
    }
    _lastScrubBeat = beat;
  }

  @override
  void dispose() {
    _tapOverlayTimer?.cancel();
    _scrubOverlayTimer?.cancel();
    _seekOverlayTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _toggleControls() {
    HapticFeedback.selectionClick();
    setState(() => _controlsVisible = !_controlsVisible);
  }

  @override
  Widget build(BuildContext context) {
    final dirs = widget.mode == Modes.singles ? kSingleDirs : kDoubleDirs;
    return LayoutBuilder(builder: (context, constraints) {
      final topInset = MediaQuery.of(context).padding.top;
      // Refresh the receptor→bottom run for the CONSTANT ⇄ read-speed
      // conversion. Plain assignment: a size change already rebuilds via
      // LayoutBuilder, so no setState needed.
      _receptorRunPx =
          constraints.maxHeight - _ChartPainter._receptorBase - topInset;
      return Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed scrolling field. Tap = play/pause, 1-finger drag = scrub
          // (vertical) / song speed (horizontal), 2-finger pinch = zoom the note
          // spacing, double-tap left/right = seek ±5s, press-and-hold = 2x speed.
          // A single scale recognizer owns pan AND pinch because Flutter won't let
          // a pinch coexist with separate pan/drag recognizers on one detector.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _togglePlay(showOverlay: true),
            onDoubleTapDown: (d) =>
                _seek(d.localPosition.dx >= constraints.maxWidth / 2),
            onLongPressStart: (_) => _onHoldSpeedStart(),
            onLongPressEnd: (_) => _onHoldSpeedEnd(),
            onLongPressCancel: _onHoldSpeedEnd,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _ChartPainter(
                    notes: widget.steps.notes,
                    shockNotes: _shockNotes,
                    shocks: _shocks,
                    bpmMarkers: _bpmMarkers,
                    stopMarkers: _stopMarkers,
                    feet: widget.showFootGuide ? _feet : const {},
                    dirs: dirs,
                    colMap: _colMap,
                    second: _second,
                    pxPerSecond: _pxPerSecond,
                    pxPerBeat: _pxPerBeat,
                    timing: _timing,
                    columnCount: dirs.length,
                    skin: _skin,
                    playing: _playing,
                    zoom: _zoom,
                    constantMs: _effectiveConstantMs,
                    topInset: MediaQuery.of(context).padding.top,
                  ),
                  size: Size.infinite,
                ),
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showTapOverlay ? 1 : 0,
                    duration: const Duration(milliseconds: 130),
                    child: Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.26),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _tapOverlayIcon,
                          color: Colors.white.withValues(alpha: 0.88),
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ),
                // Double-tap seek flash: lights up the tapped half of the field
                // with a skip icon + "±5s", YouTube-style.
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showSeekOverlay ? 1 : 0,
                    duration: const Duration(milliseconds: 100),
                    child: Align(
                      alignment: _seekOverlayLeft
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: 0.42,
                        heightFactor: 1,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.horizontal(
                              left: _seekOverlayLeft
                                  ? Radius.zero
                                  : const Radius.circular(80),
                              right: _seekOverlayLeft
                                  ? const Radius.circular(80)
                                  : Radius.zero,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _seekOverlayLeft
                                    ? Icons.fast_rewind_rounded
                                    : Icons.fast_forward_rounded,
                                color: Colors.white.withValues(alpha: 0.9),
                                size: 30,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _seekOverlayLeft
                                    ? "-${_seekStepSeconds.toInt()}s"
                                    : "+${_seekStepSeconds.toInt()}s",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white.withValues(alpha: 0.92),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Big centred value while horizontally scrubbing a control, so
                // the change reads on the field without watching the pane.
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showScrubOverlay ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.34),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _scrubOverlayCaption ?? "",
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.0,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _scrubOverlayLabel ?? "",
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: Colors.white.withValues(alpha: 0.92),
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Persistent badge while press-and-hold fast-forward is active,
                // so the 2x state reads at a glance for as long as it's held.
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _holdFastForward ? 1 : 0,
                    duration: const Duration(milliseconds: 100),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: MediaQuery.of(context).padding.top + 12,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fast_forward_rounded,
                                  color: Colors.white.withValues(alpha: 0.92),
                                  size: 16),
                              const SizedBox(width: 4),
                              Text(
                                "${_holdSpeedMultiplier.toInt()}x",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white.withValues(alpha: 0.92),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Floating header, slides up out of view when controls are hidden.
          if (widget.headerBuilder != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedSlide(
                  offset: _controlsVisible ? Offset.zero : const Offset(0, -1),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: widget.headerBuilder!(context),
                  ),
                ),
              ),
            ),

          // Settings shade: a top "pull-down" sheet of chart-viewing modifiers,
          // hidden by default behind the left-edge pull-tab. Kept out of the
          // way (unlike an always-on strip) so it has room to grow to the full
          // DDR option set; force-closed while playing since it's a browsing
          // surface, and tapping the scrim behind it dismisses it.
          _buildSettingsShade(context),

          // Bottom controls, pinned to the bottom edge. The density scrubber
          // stays visible even in "fullscreen" (controls hidden) — only the
          // transport pane above it slides down out of view. Laid out bottom-up
          // so the scrubber holds its position while the transport collapses.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Always-visible tempo readout: the BPM of the section under
                    // the playhead and the read speed it actually scrolls at
                    // (CONSTANT-aware). Centred over the bottom controls and kept
                    // on screen in fullscreen too — the one place the current
                    // tempo stays legible once its BPM marker has scrolled past.
                    // IgnorePointer so taps fall through to the field below.
                    IgnorePointer(
                      child: _TempoBadge(
                        bpm: _localBpm,
                        readSpeed: _liveReadSpeed,
                        constantBound: _constantBinds,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Transport (times, read/song speed): hides with the controls.
                    IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.bottomCenter,
                        child: AnimatedSlide(
                          offset:
                              _controlsVisible ? Offset.zero : const Offset(0, 1),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: _controlsVisible
                                ? _buildTransport(context)
                                : const SizedBox(width: double.infinity),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Density scrubber: always visible, even in fullscreen.
                    _buildScrubBar(context),
                  ],
                ),
              ),
            ),
          ),

          // Always-visible handle to show/hide the controls: a small tab pinned
          // to the right edge. Its chevron points the way the controls will
          // move (up-into-view vs down-out-of-view).
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: _EdgeTab(
                leftEdge: false,
                icon: _controlsVisible
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_up,
                onTap: _toggleControls,
              ),
            ),
          ),

          // The settings-shade handle: the left-edge mirror of the controls
          // tab, replacing the old gear tucked in the header's corner. Its
          // chevron points the way the shade will move (down-into-view when
          // closed, up-out-of-view when open). Tapping it mid-play pauses
          // first — the shade is a paused-browsing surface (see [_toggleShade]).
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: _EdgeTab(
                leftEdge: true,
                icon: _shadeOpen && !_playing
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                onTap: _toggleShade,
              ),
            ),
          ),
        ],
      );
    });
  }

  // The density scrubber track — always shown, even when the transport is
  // hidden in fullscreen. Its own rounded surface so it reads as a control
  // when it stands alone under the collapsed transport. The elapsed/total time
  // labels sit directly above it (not the read/song-speed row) since they
  // describe the same seconds axis the scrubber seeks on.
  Widget _buildScrubBar(BuildContext context) {
    final progress = _endSecond <= 0
        ? 0.0
        : (_second / _endSecond).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmtTime(_second),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              Text(
                _fmtTime(_endSecond),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            color: Colors.black.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _DensityScrubBar(
              buckets: _minimap,
              progress: progress,
              accent: Theme.of(context).colorScheme.primary,
              bpmFractions: _markerFractions(_bpmMarkers.map((m) => m.second)),
              stopFractions:
                  _markerFractions(_stopMarkers.map((m) => m.second)),
              onSeek: (frac) {
                _pause();
                final next = (frac * _endSecond).clamp(0.0, _endSecond);
                // Detent per whole second dragged across, so the minimap seek
                // ticks under the finger without firing on every sub-pixel move.
                if (next.floor() != _second.floor()) {
                  HapticFeedback.selectionClick();
                }
                setState(() => _second = next);
              },
            ),
          ),
        ),
      ],
    );
  }

  // The settings shade: a top "pull-down" sheet of chart-viewing modifiers,
  // hidden behind the left-edge pull-tab until opened. A tap-scrim behind it dismisses
  // it; the sheet itself is a scrollable column of titled sections so it has room
  // to grow toward the full DDR option set (arrows, lane, scroll, assist …).
  // Never shown while playing — [_play] force-closes it.
  Widget _buildSettingsShade(BuildContext context) {
    final open = _shadeOpen && !_playing;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !open,
        child: Stack(
          children: [
            // Dimming scrim: tap anywhere outside the sheet to close.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleShade,
              child: AnimatedOpacity(
                opacity: open ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Container(color: Colors.black.withValues(alpha: 0.45)),
              ),
            ),
            // The sheet, pinned to the top and sliding down into view.
            Align(
              alignment: Alignment.topCenter,
              child: AnimatedSlide(
                offset: open ? Offset.zero : const Offset(0, -1),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: open ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: _SettingsShade(
                    onClose: _toggleShade,
                    sections: _buildShadeSections(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The modifier sections shown in the shade. Only the Arrows section (CONSTANT)
  // is wired for now; the rest are placeholders reserving their place so the
  // shade already reads as the full options screen and new controls slot in
  // without a layout rethink. Mirrors the DDR World option categories.
  List<_ShadeSection> _buildShadeSections(BuildContext context) {
    return [
      _ShadeSection(
        title: "ARROWS",
        // Tiled: CONSTANT spans the full top row; below it a row split three
        // ways — MIRROR (flip L↔R), LEFT and RIGHT turns — mirroring DDR World's
        // appearance options.
        content: Column(
          children: [
            _ConstantChip(
              on: _constantOn,
              ms: _constantMs,
              equivalentReadSpeed: _constantReadSpeed,
              onTap: _toggleConstant,
              onDrag: _onConstantDrag,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TurnTile(
                    label: "MIRROR",
                    // DDR's MIRROR glyph is an up/down arrow pair (180° flip);
                    // swap_vert conveys the same reflected-pair idea.
                    icon: Icons.swap_vert,
                    selected: _turn == _Turn.mirror,
                    onTap: () => _setTurn(_Turn.mirror),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TurnTile(
                    label: "LEFT",
                    icon: Icons.rotate_left,
                    selected: _turn == _Turn.left,
                    onTap: () => _setTurn(_Turn.left),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TurnTile(
                    label: "RIGHT",
                    icon: Icons.rotate_right,
                    selected: _turn == _Turn.right,
                    onTap: () => _setTurn(_Turn.right),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildTransport(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(
                  child: _ReadSpeedPane(
                    readSpeed: _currentReadSpeed,
                    canDecrement: _modIndex > 0,
                    canIncrement: _modIndex < constants.mods.length - 1,
                    onStep: _stepReadSpeed,
                    onDrag: _onReadSpeedDrag,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SongSpeedPane(
                    rate: _playbackRate,
                    onDrag: _onPlaybackRateDrag,
                    onReset: _resetPlaybackRate,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Always-visible pill showing the tempo section under the playhead: its BPM
/// and the read speed it actually reads at. The READ value is CONSTANT-aware —
/// when the CONSTANT window is what bounds visibility in this section (hiding
/// arrows a fixed wall-clock time out), the value takes a "C" prefix and shows
/// the window's equivalent read speed; in sections already faster than the
/// window (where CONSTANT hides nothing) the prefix drops and the plain
/// localBpm × mod value shows through. Styled after the fast-forward badge so
/// the floating overlays read as one family.
class _TempoBadge extends StatelessWidget {
  const _TempoBadge({
    required this.bpm,
    required this.readSpeed,
    required this.constantBound,
  });

  final int bpm;
  final int readSpeed;
  final bool constantBound;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.92),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          stat("BPM", "$bpm"),
          Container(
            width: 1,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: Colors.white.withValues(alpha: 0.22),
          ),
          stat("READ", constantBound ? "C$readSpeed" : "$readSpeed"),
        ],
      ),
    );
  }
}

/// Left half of the control row: the DDR read speed (derived from the chart's
/// BPM × the current x-mod). Drag horizontally to sweep through mods, or tap the
/// ∓ ends to nudge by one step (~±10 read speed).
class _ReadSpeedPane extends StatelessWidget {
  const _ReadSpeedPane({
    required this.readSpeed,
    required this.canDecrement,
    required this.canIncrement,
    required this.onStep,
    required this.onDrag,
  });

  final int readSpeed;
  final bool canDecrement;
  final bool canIncrement;
  final void Function(int delta) onStep;
  final void Function(double dx) onDrag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ControlPane(
      onDragUpdate: (d) => onDrag(d.primaryDelta ?? 0),
      child: Row(
        children: [
          _EdgeButton(
            label: "−10",
            enabled: canDecrement,
            onTap: () => onStep(-1),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "READ SPEED",
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Text(
                  "$readSpeed",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          _EdgeButton(
            label: "+10",
            enabled: canIncrement,
            onTap: () => onStep(1),
          ),
        ],
      ),
    );
  }
}

/// Right half of the control row: playback speed (how fast the chart plays in
/// real time). Drag horizontally to speed up / slow down; tap to reset to 1.0×.
class _SongSpeedPane extends StatelessWidget {
  const _SongSpeedPane({
    required this.rate,
    required this.onDrag,
    required this.onReset,
  });

  final double rate;
  final void Function(double dx) onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ControlPane(
      onTap: onReset,
      onDragUpdate: (d) => onDrag(d.primaryDelta ?? 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "SONG SPEED",
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          Text(
            "${rate.toStringAsFixed(2)}×",
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared framing for the two control panes: a rounded, tappable/draggable
/// surface with a horizontal-drag gesture and a subtle grab cursor.
class _ControlPane extends StatelessWidget {
  const _ControlPane({
    required this.child,
    required this.onDragUpdate,
    this.onTap,
  });

  final Widget child;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onHorizontalDragUpdate: onDragUpdate,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// One titled group of modifier controls inside the settings shade. [content] is
/// the section's laid-out body (tiles/rows).
class _ShadeSection {
  final String title;
  final Widget? content;
  const _ShadeSection({
    required this.title,
    this.content,
  });
}

/// The pull-down settings sheet: a rounded top panel carrying a grab-handle, a
/// title row with a close button, and a scrollable list of [_ShadeSection]s.
/// Height-capped so it never covers the whole field, and its body scrolls when
/// the option set outgrows the cap.
class _SettingsShade extends StatelessWidget {
  const _SettingsShade({
    required this.onClose,
    required this.sections,
  });

  final VoidCallback onClose;
  final List<_ShadeSection> sections;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Neutral surface matching the bottom transport, not the accent. The shade
    // reads as the same material as the rest of the chrome — a slightly raised,
    // opaque panel — instead of a purple sheet.
    final onSurface = scheme.onSurface;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: media.size.height * 0.66),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.98),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(20)),
        border: Border(
          bottom: BorderSide(
            color: onSurface.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title row: a settings glyph, "VIEW OPTIONS", and a close button.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                children: [
                  Icon(Icons.tune,
                      size: 18, color: onSurface.withValues(alpha: 0.85)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "VIEW OPTIONS",
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        color: onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close,
                        color: onSurface.withValues(alpha: 0.7), size: 20),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in sections) _sectionBlock(s, onSurface),
                  ],
                ),
              ),
            ),
            // Grab-handle at the very bottom edge, echoing a pull-down shade.
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionBlock(_ShadeSection s, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.title,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 8),
          if (s.content != null) s.content!,
        ],
      ),
    );
  }
}

/// Neutral fill/border/foreground for a shade control, keyed on whether it's
/// active. Kept deliberately monochrome (theme surface + onSurface tints) so the
/// shade reads as the same material as the bottom config, never a purple accent.
({Color fill, Color border, Color fg, Color fgMuted}) _tileColors(
    ColorScheme scheme, bool active) {
  final onSurface = scheme.onSurface;
  return active
      ? (
          fill: onSurface.withValues(alpha: 0.14),
          border: onSurface.withValues(alpha: 0.45),
          fg: onSurface,
          fgMuted: onSurface.withValues(alpha: 0.7),
        )
      : (
          fill: onSurface.withValues(alpha: 0.05),
          border: onSurface.withValues(alpha: 0.12),
          fg: onSurface.withValues(alpha: 0.85),
          fgMuted: onSurface.withValues(alpha: 0.55),
        );
}

/// The CONSTANT-modifier tile: the full-width top row of the ARROWS section.
/// Tap toggles the modifier on/off (no separate switch); dragging horizontally
/// sweeps the display time. Styled neutrally like the rest of the shade — when
/// on it reads a touch brighter and shows the current ms, off it reads "OFF".
class _ConstantChip extends StatelessWidget {
  const _ConstantChip({
    required this.on,
    required this.ms,
    required this.equivalentReadSpeed,
    required this.onTap,
    required this.onDrag,
  });

  final bool on;
  final double ms;

  /// The read speed whose full-field travel time equals the window — what the
  /// chart "reads at" everywhere the window binds. Null when off or unknown
  /// (field not laid out); shown muted next to the ms value.
  final int? equivalentReadSpeed;

  final VoidCallback onTap;
  final void Function(double dx) onDrag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _tileColors(scheme, on);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onHorizontalDragUpdate: (d) => onDrag(d.primaryDelta ?? 0),
        child: Container(
          width: double.infinity,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border, width: 1),
          ),
          child: Row(
            children: [
              // CONSTANT = a fixed arrow display *time*, so a stopwatch reads
              // the concept better than a generic clock. DDR World has no
              // CONSTANT glyph (it's not one of the option-icon categories), so
              // the closest conceptual Material icon stands in here.
              Icon(Icons.timer_outlined, size: 16, color: c.fgMuted),
              const SizedBox(width: 8),
              Text(
                "CONSTANT",
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: c.fgMuted,
                ),
              ),
              const Spacer(),
              if (on && equivalentReadSpeed != null) ...[
                Text(
                  "≈ C$equivalentReadSpeed",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.fgMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                on ? "${ms.round()}ms" : "OFF",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: c.fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single TURN tile (MIRROR / LEFT / RIGHT) in the split second row of the
/// ARROWS section. Neutral like [_ConstantChip]; the selected turn reads a touch
/// brighter with a stronger border. Tapping the active one turns it off (handled
/// by the caller).
class _TurnTile extends StatelessWidget {
  const _TurnTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;

  // A conceptual Material glyph standing in for DDR's turn icon: swap_vert for
  // MIRROR's up/down flip pair, rotate_left/right for the 90° turns. Keeps the
  // shade free of copyrighted arcade art while reading the same at a glance.
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _tileColors(scheme, selected);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: c.fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: c.fg),
            const SizedBox(height: 4),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
                color: c.fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small always-visible pull-tab pinned to a screen edge, vertically centred
/// so it never collides with the full-width header or transport. Two mirrored
/// instances exist: the RIGHT tab shows/hides the floating controls, the LEFT
/// tab pulls the settings shade down/up. [leftEdge] flips the shape so the
/// rounded corners always face away from the edge the tab hangs off.
class _EdgeTab extends StatelessWidget {
  const _EdgeTab({
    required this.leftEdge,
    required this.icon,
    required this.onTap,
  });

  final bool leftEdge;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.horizontal(
            left: leftEdge ? Radius.zero : const Radius.circular(12),
            right: leftEdge ? const Radius.circular(12) : Radius.zero,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.9),
          size: 22,
        ),
      ),
    );
  }
}

/// A tappable ∓ end-cap inside the read-speed pane. Dimmed when its step would
/// run off the end of the mod list.
class _EdgeButton extends StatelessWidget {
  const _EdgeButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: double.infinity,
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: enabled
                ? scheme.onSurface.withValues(alpha: 0.85)
                : scheme.onSurface.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}

String _fmtTime(double s) {
  final m = (s ~/ 60).toString();
  final sec = (s % 60).floor().toString().padLeft(2, '0');
  return "$m:$sec";
}

// A compact seconds label for a stop's duration, e.g. "0.16s".
String _fmtDur(double s) => "${s.toStringAsFixed(2)}s";

/// A scrub bar whose track is a note-density minimap of the whole chart (busy
/// sections show taller bars), with a played/unplayed split and a draggable
/// playhead. Tap or drag anywhere to seek. [progress] and [onSeek] are 0..1.
class _DensityScrubBar extends StatelessWidget {
  const _DensityScrubBar({
    required this.buckets,
    required this.progress,
    required this.accent,
    required this.bpmFractions,
    required this.stopFractions,
    required this.onSeek,
  });

  final List<_MinimapBucket> buckets;
  final double progress;
  final Color accent;

  /// 0..1 positions of BPM-change and stop markers along the track.
  final List<double> bpmFractions;
  final List<double> stopFractions;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      void seekAt(double dx) =>
          onSeek((dx / constraints.maxWidth).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => seekAt(d.localPosition.dx),
        onHorizontalDragStart: (d) => seekAt(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(
            height: 40,
            child: CustomPaint(
              painter: _DensityPainter(
                buckets: buckets,
                progress: progress,
                accent: accent,
                bpmFractions: bpmFractions,
                stopFractions: stopFractions,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      );
    });
  }
}

class _DensityPainter extends CustomPainter {
  _DensityPainter({
    required this.buckets,
    required this.progress,
    required this.accent,
    required this.bpmFractions,
    required this.stopFractions,
  });

  final List<_MinimapBucket> buckets;
  final double progress;
  final Color accent;
  final List<double> bpmFractions;
  final List<double> stopFractions;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final maxBar = size.height * 0.42;
    final playedX = (size.width * progress).clamp(0.0, size.width).toDouble();

    if (buckets.isEmpty) {
      // Fallback: a plain rounded track.
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, midY - 2.5, size.width, 5),
              const Radius.circular(3)),
          Paint()..color = Colors.white24);
    } else {
      final barW = size.width / buckets.length;
      for (int i = 0; i < buckets.length; i++) {
        final x = i * barW;
        final bucket = buckets[i];
        // Minimum stub so silent gaps still read as a track.
        final h = (0.10 + 0.90 * bucket.level) * maxBar;
        final played = x < playedX;
        final rect = Rect.fromLTWH(x, midY - h, barW + 0.6, h * 2);
        if (bucket.holdLevel > 0) {
          final holdH = (0.16 + 0.34 * bucket.holdLevel) * size.height;
          final holdRect = Rect.fromLTWH(
            rect.left,
            midY - holdH / 2,
            rect.width,
            holdH,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(holdRect, const Radius.circular(1.2)),
            Paint()
              ..color = played
                  ? const Color(0xFF39C46B).withValues(alpha: 0.36)
                  : const Color(0xFF39C46B).withValues(alpha: 0.18),
          );
        }
        if (bucket.segments.isEmpty) {
          canvas.drawRect(
            rect,
            Paint()..color = played ? accent : accent.withValues(alpha: 0.28),
          );
        } else {
          double top = rect.top;
          for (final segment in bucket.segments) {
            final segH = rect.height * segment.weight;
            final segRect = Rect.fromLTWH(rect.left, top, rect.width, segH);
            canvas.drawRect(
              segRect,
              Paint()
                ..color = played
                    ? segment.color
                    : segment.color.withValues(alpha: 0.34),
            );
            top += segH;
          }
        }
        if (bucket.hasShock) {
          final shockRect = Rect.fromLTWH(
            rect.left,
            rect.top - 2,
            rect.width,
            4,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(shockRect, const Radius.circular(1.2)),
            Paint()
              ..color = played
                  ? const Color(0xFF79E7FF).withValues(alpha: 0.95)
                  : const Color(0xFF79E7FF).withValues(alpha: 0.55),
          );
        }
      }
    }

    // Timing ticks: stops along the bottom edge, BPM changes along the top, so
    // both are locatable when seeking without colliding with each other.
    void drawTicks(List<double> fractions, Color color, bool atTop) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.5;
      final y0 = atTop ? 0.0 : size.height - 6;
      final y1 = atTop ? 6.0 : size.height;
      for (final f in fractions) {
        final x = (size.width * f).clamp(0.0, size.width).toDouble();
        canvas.drawLine(Offset(x, y0), Offset(x, y1), paint);
      }
    }

    drawTicks(bpmFractions, const Color(0xFF8AB4FF).withValues(alpha: 0.9), true);
    drawTicks(stopFractions, const Color(0xFFFFB454).withValues(alpha: 0.9), false);

    // Playhead: vertical needle plus a layered knob for stronger visibility.
    canvas.drawRect(
      Rect.fromLTWH(playedX - 1, 0, 2, size.height),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.drawCircle(
      Offset(playedX, midY),
      10,
      Paint()..color = accent.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      Offset(playedX, midY),
      6,
      Paint()..color = accent,
    );
    canvas.drawCircle(
      Offset(playedX, midY),
      2.4,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(playedX, midY),
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(_DensityPainter old) =>
      old.progress != progress ||
      old.buckets != buckets ||
      old.accent != accent ||
      old.bpmFractions != bpmFractions ||
      old.stopFractions != stopFractions;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.notes,
    required this.shockNotes,
    required this.shocks,
    required this.bpmMarkers,
    required this.stopMarkers,
    required this.feet,
    required this.dirs,
    required this.colMap,
    required this.second,
    required this.pxPerSecond,
    required this.pxPerBeat,
    required this.timing,
    required this.columnCount,
    required this.skin,
    required this.playing,
    this.zoom = 1.0,
    this.constantMs,
    this.topInset = 0,
  });

  final List<StepNote> notes;
  final Set<StepNote> shockNotes;
  final List<_ShockRow> shocks;
  final List<_BpmMarker> bpmMarkers;
  final List<_StopMarker> stopMarkers;
  final Map<StepNote, Foot> feet;
  final List<NoteDir> dirs;

  // DDR TURN permutation: `colMap[originalCol]` is the column the note is drawn
  // in (and the glyph orientation it takes). Receptors/lanes stay in their fixed
  // positions, so a turn only moves the notes. Identity when TURN is OFF.
  final List<int> colMap;

  final double second;
  final double pxPerSecond;

  // Beat-locked scroll: [pxPerBeat] is the pixels-per-beat spacing and [timing]
  // maps a note's second to its beat. When [timing] is empty the painter falls
  // back to [pxPerSecond] constant-time scrolling (charts with no BPM data).
  final double pxPerBeat;
  final ChartTiming timing;

  final int columnCount;
  final Noteskin skin;
  final bool playing;

  // Pinch-to-zoom factor. Applied to the horizontal field geometry (arrow size
  // and lane spacing) so that zooming out shrinks the arrows in step with the
  // vertical compression already baked into [pxPerBeat]/[pxPerSecond]. The result
  // is a uniform "map zoom": at <1 the field pulls in from both edges and the
  // arrows get smaller, so more of the chart is legibly on screen instead of the
  // notes just piling together.
  final double zoom;

  // DDR CONSTANT modifier: when non-null, every arrow is only visible for this
  // many milliseconds of WALL-CLOCK time before it reaches the receptor,
  // regardless of BPM or read speed — a note is invisible until it is this far
  // (in real seconds) from the line, then appears at full opacity and travels
  // the rest of the way solid. Null = NORMAL (arrows always visible). The window
  // is keyed on real seconds-to-receptor, not beat distance, so its span in
  // pixels/beats stretches and compresses with the local tempo, exactly as
  // in-game. See [_constantHides].
  final double? constantMs;

  // Top safe-area inset (status bar / notch). The field is full-bleed, so the
  // receptor line is pushed down by this much to clear the system chrome.
  final double topInset;

  // Whether the note at chart-second [t] is hidden by the CONSTANT modifier: a
  // hard visibility gate, not a fade. False when CONSTANT is off, or the note is
  // within its display window (or at/past the receptor); true when it's still
  // beyond the window. This matches the arcade, where CONSTANT is part of the
  // same appearance/cover machinery as HIDDEN/SUDDEN (ddr::player::Option, the
  // `display_type` family in gamemdx.dll) — the arrow snaps to full opacity the
  // instant it enters its fixed display time, rather than ramping in. Driven by
  // real seconds-to-receptor (`t - second`), so the window is a fixed wall-clock
  // time no matter the tempo. For a held note whose head has already reached the
  // line, [t] should be the head's own second (<= playhead), yielding false.
  bool _constantHides(double t) {
    final c = constantMs;
    if (c == null) return false;
    final timeToReceptor = t - second;
    if (timeToReceptor <= 0) return false; // at or past the line
    return timeToReceptor >= c / 1000.0; // beyond the fixed display window
  }

  // Receptors sit near the TOP; arrows scroll up into them. Notes are drawn
  // ON TOP OF (z-above) the receptors so an arrow reaching the line covers it.
  // [_receptorBase] is the gap below the (inset-adjusted) top edge.
  static const double _receptorBase = 56;
  double get _receptorTop => _receptorBase + topInset;
  static const double _laneTighten = 0.92;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);

    final laneW = size.width / columnCount;
    // Pinch zoom pulls the lanes in toward the field's centre (and shrinks the
    // arrows below), so zooming out narrows the field AND the glyphs uniformly —
    // the "map zoom" that actually fits more chart, rather than only tightening
    // the vertical gaps (which just stacks the arrows on top of each other).
    final laneStride = laneW * _laneTighten * zoom;
    final fieldLeft = (size.width - laneStride * columnCount) / 2;
    // DDR World arrows fill nearly the whole lane (the atlas glyph is ~0.94 of
    // its cell). No small upper clamp — arrows scale with the lane so they read
    // at the arcade's size instead of shrinking on wide fields. Zoom shrinks them
    // in lockstep with the lane stride so their proportion within a lane holds.
    final arrowSize = laneW * 0.92 * zoom;

    double laneCenterX(int col) => fieldLeft + laneStride * col + laneStride / 2;

    // TURN modifier: a note originally in column `c` is drawn in `turned(c)`,
    // taking that panel's glyph orientation. Bounds-guarded so a mismatched map
    // (e.g. mode/width change mid-frame) falls back to the note's own column.
    int turned(int c) =>
        (c >= 0 && c < colMap.length) ? colMap[c] : c;

    // Beat-locked scroll (true DDR): a note's screen position is its beat
    // distance from the playhead's beat, so BPM changes speed the field up/down
    // and stops freeze it. Charts without BPM data (empty [timing]) fall back to
    // the original constant-time scroll so they still render.
    final bool beatLocked = !timing.isEmpty;
    final double currentBeat = beatLocked ? timing.beatAt(second) : 0;
    // While playing, the field is strictly beat-locked (stops freeze it to a
    // line). While paused/scrolling we re-expand each stop to real pixels — a
    // note past a stop is pushed further down by the stop's duration — so the
    // halt reads as a physical gap you can scroll through instead of a collapsed
    // seam. This deliberately shifts the layout between play and scroll.
    final bool expandStops = beatLocked && !playing;
    final double currentStop =
        expandStops ? timing.stopSecondsAt(second) : 0;
    double yFor(double t) {
      if (!beatLocked) return _receptorTop + (t - second) * pxPerSecond;
      var y = _receptorTop + (timing.beatAt(t) - currentBeat) * pxPerBeat;
      if (expandStops) {
        y += (timing.stopSecondsAt(t) - currentStop) * pxPerSecond;
      }
      return y;
    }

    _paintLanes(canvas, size, fieldLeft, laneStride, _receptorTop);

    // Visible window's far edge, in seconds. Notes draw on-screen until they
    // align with the receptor, then disappear immediately. Holds are the
    // exception: a held head stays pinned to the receptor while the body drains.
    final double maxT = beatLocked
        ? timing.secondAt(
                currentBeat + (size.height - _receptorTop) / pxPerBeat) +
            1
        : second + ((size.height - _receptorTop) / pxPerSecond) + 1;

    // Receptors FIRST (behind the notes) so an arrow at the line covers its
    // receptacle rather than being hidden by it.
    // Receptors only pulse while playing; static (dim, steady) when paused. The
    // pulse rides the beat (freezing on stops, quickening with the tempo) when
    // beat-locked, else falls back to a fixed half-second cadence.
    final glow = playing
        ? 1.0 - ((beatLocked ? currentBeat : second * 2) % 1.0)
        : 0.0;
    for (int c = 0; c < columnCount; c++) {
      skin.paintReceptor(
          canvas, laneCenterX(c), _receptorTop, arrowSize, dirs[c], glow * 0.9);
    }

    // Clip only the far top of the field (above where a note centred on the
    // receptor would reach), so a note sitting ON the receptor draws in full
    // (z-above it) while notes that have scrolled well past are hidden.
    final clipTop = _receptorTop - arrowSize / 2 - 2;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, clipTop, size.width, size.height - clipTop));

    // 0) Timing markers (BPM changes and stops), base layer: lines/bands drawn
    // first inside the clip so notes, holds and foot paths render on top. Their
    // pill labels come later (after the notes) so they stay legible.
    _paintTimingMarkers(canvas, size, yFor, maxT, beatLocked, expandStops,
        labels: false);

    // 1) Freeze/hold bodies (behind arrowheads). While a hold is being held its
    // head has reached the receptor, so clamp the head to the line; the body
    // then shrinks upward into it and vanishes at the tail.
    for (final n in notes) {
      if (!n.isHold) continue;
      final endS = n.endSecond ?? n.second;
      if (endS < second || n.second > maxT) continue;
      // A freeze appears as one piece under CONSTANT, keyed on its head's second
      // — until the head enters its display window the whole body is hidden.
      if (_constantHides(n.second)) continue;
      final headY =
          n.second >= second ? yFor(n.second) : _receptorTop.toDouble();
      final col = turned(n.col);
      skin.paintHoldBody(canvas, laneCenterX(col), headY, yFor(endS),
          arrowSize, dirs[col], n.type == StepType.roll);
      skin.paintHoldTail(canvas, laneCenterX(col), yFor(endS), arrowSize,
          dirs[col], n.type == StepType.roll);
    }

    // 1.5) Foot-flow paths: connect each note to the previous note struck by the
    // same foot, so the chart's left/right movement reads as two flowing lines.
    if (feet.isNotEmpty) {
      _paintFootPaths(canvas, laneCenterX, yFor, arrowSize, second, maxT);
    }

    // 2) Shock rows: a light-blue arrow in every lit lane linked by electricity,
    // spanning the whole row (also vanishes once hit).
    for (final s in shocks) {
      if (s.second < second || s.second > maxT) continue;
      if (_constantHides(s.second)) continue; // hidden by CONSTANT
      final y = yFor(s.second);
      final lanes = [
        for (final c in s.cols) (laneCenterX(turned(c)), dirs[turned(c)]),
      ];
      skin.paintShock(canvas, lanes, y, arrowSize);
    }

    // 3) Taps, mines (non-shock), and hold heads — drawn last so they sit above
    // the receptors. A held freeze keeps its head pinned to the receptor line.
    for (final n in notes) {
      final endS = n.endSecond ?? n.second;
      final held = n.isHold && n.second < second && endS >= second;
      if (!held && (n.second < second || n.second > maxT)) {
        continue;
      }
      // A held head sits on the receptor, so treat it as fully arrived rather
      // than re-gating it; otherwise CONSTANT hides it until it enters its window.
      if (!held && _constantHides(n.second)) continue;
      final col = turned(n.col);
      final x = laneCenterX(col);
      final y = held ? _receptorTop.toDouble() : yFor(n.second);
      if (n.type == StepType.mine) {
        if (shockNotes.contains(n)) continue; // drawn in the shock pass
        skin.paintMine(canvas, x, y, arrowSize);
      } else {
        skin.paintArrow(canvas, x, y, arrowSize, dirs[col], n.beat);
        final foot = feet[n];
        if (foot != null) _paintFootBadge(canvas, x, y, arrowSize, foot);
      }
    }

    // 4) Timing-marker labels, top layer: drawn last so the STOP/BPM pills sit
    // above the note stream instead of being buried under passing arrows.
    _paintTimingMarkers(canvas, size, yFor, maxT, beatLocked, expandStops,
        labels: true);

    canvas.restore(); // end note clip
  }

  // A small L/R parity badge centred on the arrow. Left = warm, right = cool,
  // so the two feet read apart at a glance without a legend.
  static const Color _leftFootColor = Color(0xFFFF5D73);
  static const Color _rightFootColor = Color(0xFF3FA9FF);

  // Connect each note to the previous note struck by the same foot, drawing two
  // flowing polylines (one per foot) so the chart's movement pattern reads at a
  // glance. Drawn behind the arrowheads. Held notes anchor to the receptor while
  // active, matching where their head is actually drawn.
  void _paintFootPaths(
    Canvas canvas,
    double Function(int) laneCenterX,
    double Function(double) yFor,
    double arrowSize,
    double second,
    double maxT,
  ) {
    // On-screen anchor for a note: pinned to the receptor while a hold is held,
    // else its scrolling position.
    Offset anchor(StepNote n) {
      final endS = n.endSecond ?? n.second;
      final held = n.isHold && n.second < second && endS >= second;
      final y = held ? _receptorTop.toDouble() : yFor(n.second);
      final col = (n.col >= 0 && n.col < colMap.length) ? colMap[n.col] : n.col;
      return Offset(laneCenterX(col), y);
    }

    // Whether a note contributes to the visible window (same test the arrow pass
    // uses), so path segments only exist where at least one endpoint is drawn.
    bool visible(StepNote n) {
      final endS = n.endSecond ?? n.second;
      final held = n.isHold && n.second < second && endS >= second;
      return held || (n.second >= second && n.second <= maxT);
    }

    final leftPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arrowSize * 0.10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _leftFootColor.withValues(alpha: 0.42);
    final rightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arrowSize * 0.10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _rightFootColor.withValues(alpha: 0.42);

    StepNote? prevLeft;
    StepNote? prevRight;
    for (final n in notes) {
      if (n.type == StepType.mine) continue;
      if (shockNotes.contains(n)) continue;
      final foot = feet[n];
      if (foot == null) continue;
      final prev = foot == Foot.left ? prevLeft : prevRight;
      // Draw a segment to the previous same-foot note when either endpoint is in
      // the visible window (so a segment scrolling in from below still shows).
      if (prev != null && (visible(prev) || visible(n))) {
        canvas.drawLine(
          anchor(prev),
          anchor(n),
          foot == Foot.left ? leftPaint : rightPaint,
        );
      }
      if (foot == Foot.left) {
        prevLeft = n;
      } else {
        prevRight = n;
      }
    }
  }

  // Colours for timing markers: stops read as a warm caution band, BPM changes
  // as a cool line, so the two never get confused with the arrow palette.
  static const Color _stopColor = Color(0xFFFFB454);
  static const Color _bpmColor = Color(0xFF8AB4FF);

  // Draw full-width markers for stops (a band spanning the halt's duration) and
  // BPM changes (a line + label), positioned on the same seconds axis the notes
  // scroll on. Only markers within the visible time window are drawn.
  // Draws timing markers in two z-layers. The lines/bands are the base layer
  // ([labels] = false), painted before the notes so arrows scroll over them; the
  // pill labels are the top layer ([labels] = true), painted after the notes so
  // they stay legible instead of being buried under a stream of arrows.
  void _paintTimingMarkers(
    Canvas canvas,
    Size size,
    double Function(double) yFor,
    double maxT,
    bool beatLocked,
    bool expandStops, {
    required bool labels,
  }) {
    // Stops. Beat-locked while PLAYING, a stop occupies zero beat-space (the
    // field freezes on it), so it draws as a single bold line carrying its
    // duration in the label. Paused/scrolling ([expandStops]) — and in the
    // constant-time fallback — the stop is given real vertical extent and draws
    // as a band spanning the halt so its length reads at a glance.
    for (final s in stopMarkers) {
      final endSec = s.second + s.dur;
      if (endSec < second || s.second > maxT) continue;
      if (beatLocked && !expandStops) {
        final y = yFor(s.second);
        if (labels) {
          _paintMarkerLabel(
              canvas, size, y, "STOP ${_fmtDur(s.dur)}", _stopColor,
              alignBottom: true);
        } else {
          canvas.drawLine(
            Offset(0, y),
            Offset(size.width, y),
            Paint()
              ..color = _stopColor.withValues(alpha: 0.85)
              ..strokeWidth = 2.5,
          );
        }
        continue;
      }
      final yTop = yFor(s.second);
      if (labels) {
        _paintMarkerLabel(canvas, size, yTop, "STOP", _stopColor,
            alignBottom: true);
        continue;
      }
      final yBot = yFor(endSec);
      final band = Rect.fromLTRB(0, yBot, size.width, yTop);
      canvas.drawRect(band, Paint()..color = _stopColor.withValues(alpha: 0.12));
      // Edges of the band, brighter, so even a near-instant stop stays visible.
      final edge = Paint()
        ..color = _stopColor.withValues(alpha: 0.7)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(0, yTop), Offset(size.width, yTop), edge);
      canvas.drawLine(Offset(0, yBot), Offset(size.width, yBot), edge);
    }

    // BPM changes: a thin cool line with the new tempo labelled at the edge.
    for (final b in bpmMarkers) {
      if (b.second < second || b.second > maxT) continue;
      final y = yFor(b.second);
      if (labels) {
        _paintMarkerLabel(canvas, size, y, "${b.bpm} BPM", _bpmColor);
      } else {
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = _bpmColor.withValues(alpha: 0.75)
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  // A small pill label pinned to the right edge of a marker line. [alignBottom]
  // seats it just below the line (used for a stop band's start) instead of above.
  void _paintMarkerLabel(
    Canvas canvas,
    Size size,
    double y,
    String text,
    Color color, {
    bool alignBottom = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const padX = 5.0;
    const padY = 3.0;
    const margin = 6.0;
    final boxW = tp.width + padX * 2;
    final boxH = tp.height + padY * 2;
    final left = size.width - boxW - margin;
    final top = alignBottom ? y + 2 : y - boxH - 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, boxW, boxH),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.black.withValues(alpha: 0.55));
    tp.paint(canvas, Offset(left + padX, top + padY));
  }

  void _paintFootBadge(
      Canvas canvas, double x, double y, double arrowSize, Foot foot) {
    final isLeft = foot == Foot.left;
    final r = arrowSize * 0.24;
    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: isLeft ? "L" : "R",
        style: TextStyle(
          color: isLeft ? _leftFootColor : _rightFootColor,
          fontSize: arrowSize * 0.34,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  void _paintBackground(Canvas canvas, Size size) {
    // Vertical stage gradient: darker at the bottom, lifting toward the
    // receptors so incoming notes read clearly.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF11151C),
            Color(0xFF080A0E),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  void _paintLanes(Canvas canvas, Size size, double fieldLeft,
      double laneStride, double receptorY) {
    // Subtle lane dividers, tracking the (zoom-scaled) field so they sit between
    // the lanes rather than drifting away from the arrows when zoomed out.
    final div = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (int c = 1; c < columnCount; c++) {
      final x = fieldLeft + laneStride * c;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), div);
    }
    // Receptor line highlight.
    final line = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 1));
    canvas.drawRect(
        Rect.fromLTWH(0, receptorY - 0.5, size.width, 1), line);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.second != second ||
      old.pxPerSecond != pxPerSecond ||
      old.pxPerBeat != pxPerBeat ||
      old.timing != timing ||
      old.notes != notes ||
      old.bpmMarkers != bpmMarkers ||
      old.stopMarkers != stopMarkers ||
      old.feet != feet ||
      old.columnCount != columnCount ||
      !listEquals(old.colMap, colMap) ||
      old.skin != skin ||
      old.playing != playing ||
      old.zoom != zoom ||
      old.constantMs != constantMs ||
      old.topInset != topInset;
}
