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

import 'chart_chrome.dart';
import 'chart_models.dart';
// Re-exported so callers keep importing the test handles from the preview's
// entry point rather than reaching into the split-out parts.
export 'chart_chrome.dart'
    show
        tempoBadgeKey,
        shadeTabKey,
        arcadeSyncTileKey,
        visualOffsetChipKey,
        audioOffsetChipKey;
import 'chart_painter.dart';
import 'chart_timing.dart';
import 'dancing_feet.dart';
import 'density_scrub_bar.dart';
import 'tick_clock.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// DDR "TURN" modifier: permutes the notes' columns while the receptors stay in
/// their fixed L-D-U-R positions. MIRROR is a 180° turn, LEFT/RIGHT are 90°.
enum _Turn { off, mirror, left, right }

/// `map[oldCol]` is the column the note now appears in. Doubles mirrors across
/// the whole 8-panel row but turns each pad half on its own, which keeps the
/// per-foot motion intact.
List<int> _turnColumnMap(_Turn turn, int columnCount) {
  if (turn == _Turn.off) {
    return [for (int c = 0; c < columnCount; c++) c];
  }
  // Offsets within one pad (L D U R = 0 1 2 3).
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

class ChartScroller extends StatefulWidget {
  const ChartScroller({
    super.key,
    required this.steps,
    required this.mode,
    required this.songLength,
    required this.chartBpm,
    this.minBpm = 0,
    this.maxBpm = 0,
    this.bpms = const [],
    this.stops = const [],
    this.sync,
    this.showFootGuide = false,
    this.showFootTrails = false,
    this.showDancingFeet = false,
    this.showMeasureLines = false,
    this.assistTickOn = false,
    this.arcadeQuantOn = false,
    this.onToggleMeasureLines,
    this.onToggleFootGuide,
    this.onToggleFootTrails,
    this.onToggleDancingFeet,
    this.onToggleAssistTick,
    this.onToggleArcadeQuant,
    this.headerBuilder,
  });

  final ChartSteps steps;
  final Modes mode;

  /// Optional floating header (title / back / actions) over the full-bleed
  /// field. Shown and hidden with the transport controls.
  final Widget Function(BuildContext context)? headerBuilder;

  /// Timing markers in seconds (from [Chart]) — the same seconds axis the note
  /// stream scrolls on, so they render at true position.
  final List<Bpm> bpms;
  final List<Stop> stops;

  /// The song's measured audio-vs-chart sync, reported under ARCADE SYNC so the
  /// dials are set against a known bias. Null when the song has no sync data.
  final Sync? sync;

  /// The chart's authored BPM extremes (`true_min`/`true_max`), bracketing
  /// [chartBpm]. 0 means "not supplied" — the note stream is the fallback.
  final int minBpm;
  final int maxBpm;

  /// Overlay an L/R parity guide on each arrow.
  final bool showFootGuide;

  /// Join each note to the previous one struck by the same foot. Same solve as
  /// [showFootGuide], toggled separately — the trails read with the badges off.
  final bool showFootTrails;

  /// Show the dancing-feet pad: a mini stage with both feet standing where the
  /// parity solve puts them at the playhead.
  final bool showDancingFeet;

  /// Rule the field into numbered 4-beat measures.
  final bool showMeasureLines;

  /// Play a short tick as each note row crosses the receptors during playback.
  final bool assistTickOn;

  /// Colour arrows with the cabinet's coarser quantisation palette. Mirrors
  /// [QuantColors.arcadeMode] so the tile and minimap repaint when it flips.
  final bool arcadeQuantOn;

  /// Toggle callbacks for the options above, wired into the settings shade.
  /// Null hides the tile.
  final VoidCallback? onToggleFootGuide;
  final VoidCallback? onToggleFootTrails;
  final VoidCallback? onToggleDancingFeet;
  final VoidCallback? onToggleAssistTick;
  final VoidCallback? onToggleMeasureLines;
  final VoidCallback? onToggleArcadeQuant;

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
  // A ValueNotifier so per-frame motion repaints only the listeners that ride
  // the playhead (canvas, minimap needle, HUD readouts) instead of rebuilding
  // the tree at 60+Hz; setState is reserved for real state flips.
  final ValueNotifier<double> _playhead = ValueNotifier(0);
  double get _second => _playhead.value;
  set _second(double v) => _playhead.value = v;
  bool _playing = false;

  // Whether the bottom transport pane (read/song speed) is shown, toggled by
  // the right-edge handle. The top header is NOT gated by this — it follows the
  // paused state, so the song title is always up while paused.
  bool _transportVisible = true;

  // Whether the top settings shade is pulled down. Auto-closed when playback
  // starts, and never shown while playing (it's a paused-browsing surface).
  bool _shadeOpen = false;

  // DDR WORLD SPEED TYPE: two independent speed values plus a type selector,
  // toggled by tapping the pane. Each type keeps its own dialled value, and all
  // three persist across previews.
  //
  // HI-SPEED — a raw multiplier in hundredths, 25–800 (x0.25–x8.00), dialled in
  // x0.05 steps (see [_snapHispeed]).
  // SCROLL SPEED (shown as REAL SPEED) — a target scroll rate, 10–1000 in steps
  // of 10, whose multiplier is derived per chart (see [_derivedHundredths]).
  bool _hispeedType = false;
  int _hispeedHundredths = 100;
  int _scrollSpeed = constants.chosenReadSpeed;

  static const int _hispeedMin = 25, _hispeedMax = 800, _hispeedStep = 5;
  static const int _scrollMin = 10, _scrollMax = 1000, _scrollStep = 10;

  // The effective multiplier for the active speed type.
  double get _rate => _activeHundredths / 100.0;

  int get _activeHundredths =>
      _hispeedType ? _hispeedHundredths : _derivedHundredths;

  // REAL SPEED's multiplier: round(scroll × 100 / divisorBpm), clamped to the
  // same 25–800 as HI-SPEED, x1.00 when the chart has no usable BPM.
  //
  // The divisor is the curated headline BPM, not the note stream's raw peak, so
  // a soflan spike reads genuinely faster than the headline section. See
  // [_scrollDivisorBpm].
  int get _derivedHundredths {
    final bpm = _scrollDivisorBpm;
    if (bpm <= 0) return 100;
    return ((_scrollSpeed * 100) / bpm).round().clamp(_hispeedMin, _hispeedMax);
  }

  // Minimum seconds a tempo must be held to count toward the headline BPM, so a
  // one-beat gimmick spike is excluded. 2s matches the cabinet's headline tempo
  // on the large majority of songs.
  static const double _sustainedBpmMinSeconds = 2.0;

  // The REAL SPEED divisor: the highest BPM the chart SUSTAINS for at least
  // [_sustainedBpmMinSeconds] — the fastest tempo you actually read at,
  // ignoring momentary soflan spikes. Falls back to dominant, then effective
  // BPM, when the stream carries no timed segments.
  //
  // Independent of [widget.maxBpm]/`true_max`, which stays the real unreported
  // peak and is deliberately not used as the divisor.
  int get _scrollDivisorBpm {
    var peak = 0;
    final held = <int, double>{};
    for (final b in widget.bpms) {
      if (b.val <= 0) continue;
      final dur = b.ed - b.st;
      if (dur <= 0) continue;
      held[b.val] = (held[b.val] ?? 0) + dur;
    }
    held.forEach((val, secs) {
      if (secs >= _sustainedBpmMinSeconds && val > peak) peak = val;
    });
    if (peak > 0) return peak;
    // No segment cleared the sustain threshold (very short chart, or no timing):
    // fall back to the dominant BPM, then the effective chart BPM.
    final dom = widget.chartBpm;
    return dom > 0 ? dom : _effectiveChartBpm;
  }

  // The chart's slow-end BPM — the low bound of the compact readout's span.
  // Prefers the authored `true_min` over scanning [widget.bpms], which only
  // carries the segments this difficulty plays through.
  int get _minChartBpm {
    var min = widget.minBpm;
    if (min <= 0) {
      for (final b in widget.bpms) {
        if (b.val > 0 && (min <= 0 || b.val < min)) min = b.val;
      }
    }
    return min > 0 ? min : _effectiveChartBpm;
  }

  // Pinch-to-zoom: a visual multiplier on note spacing, applied on top of
  // [_rate] so the whole render (cull window, CONSTANT, markers, foot paths)
  // stretches with it and the dialled READ SPEED is untouched. Zooming in past
  // 1x is disallowed since READ SPEED covers that. A study lens, not a
  // persisted setting — reset to 1.0 on each new chart.
  static const double _minZoom = 0.25;
  static const double _maxZoom = 1.0;
  double _zoom = 1.0;
  // Zoom at the start of a pinch, so updates scale from where the fingers
  // landed instead of compounding each frame.
  double _pinchStartZoom = 1.0;

  // DDR CONSTANT modifier: fade arrows in a fixed wall-clock time before they
  // reach the receptor, independent of BPM/read speed. Off by default (NORMAL).
  // [_constantMs] is the display time (100–3000ms, snapped to 10ms), handed to
  // the painter only while [_constantOn]. Persisted across previews.
  static const double _constantMinMs = 100;
  static const double _constantMaxMs = 3000;
  static const double _constantStepMs = 10;
  static const double _constantDefaultMs = 1000;
  bool _constantOn = false;
  double _constantMs = _constantDefaultMs;

  // DDR TURN modifier: permutes which panel each note lands on (receptors stay
  // put). OFF by default; persisted across previews. See [_Turn].
  _Turn _turn = _Turn.off;

  // ARCADE SYNC: master switch for the cabinet timing simulation. While off,
  // both offsets below are ignored and their controls stay hidden. Turning it
  // on forces the assist tick on (restoring the previous state on the way out),
  // since an AUDIO OFFSET is inaudible without it.
  bool _arcadeSyncOn = false;
  bool? _tickBeforeArcadeSync;

  // The offsets this preview opened with. Switching ARCADE SYNC off restores
  // them, so toggling is a true A/B against the tuned value rather than
  // whatever was dialled mid-experiment.
  double _visualOffsetOnEntry = 0;
  double _audioOffsetMsOnEntry = 0;

  // The cabinet's two TIMING dials, in their own units:
  //
  //   VISUAL (表示タイミング) — a -5.0..+5.0 dial in 0.1 steps, moving the
  //     arrows' aiming position rather than the judgement against the music.
  //   AUDIO (判定タイミング) — natively milliseconds, where players work in
  //     roughly ±10-20ms. Kept in ms so a cabinet number means the same here.
  //
  // The preview has no judgement or input, so these reproduce the settings'
  // effect — they can't tell you your offset.
  static const double _visualOffsetMin = -5.0;
  static const double _visualOffsetMax = 5.0;
  static const double _visualOffsetStep = 0.1;

  static const double _audioOffsetMinMs = -50;
  static const double _audioOffsetMaxMs = 50;

  /// Seconds of arrow travel per whole VISUAL dial unit. The cabinet publishes
  /// the dial as a bare number, so this is the preview's own calibration: one
  /// unit = one 60fps frame, putting the full ±5.0 dial at ±83ms.
  static const double _visualOffsetUnitSeconds = 1.0 / 60.0;

  double _visualOffset = 0; // dial units, -5.0..+5.0
  double _audioOffsetMs = 0; // milliseconds, -50..+50

  /// Seconds fed to the painter / tick clock, gated once here so no caller can
  /// apply an offset while ARCADE SYNC is off. The gate lives in free functions
  /// so tests can exercise it — the field painter is unobservable in a widget
  /// test, since the scroller paints nothing until the noteskin future resolves.
  double get _visualOffsetSeconds => debugGatedVisualOffsetSeconds(
        arcadeSyncOn: _arcadeSyncOn,
        units: _visualOffset,
      );
  double get _audioOffsetSeconds => debugGatedAudioOffsetSeconds(
        arcadeSyncOn: _arcadeSyncOn,
        ms: _audioOffsetMs,
      );

  // Playback-rate multiplier: how fast the chart plays back in wall-clock time.
  // 1.0 = true speed; <1 slows the song, >1 speeds it up. Independent of the
  // read-speed (note-spacing) mod above.
  double _playbackRate = 1.0;
  static const double _minPlaybackRate = 0.25;
  static const double _maxPlaybackRate = 1.0;

  // Tap-and-hold fast-forward: holding the field without dragging doubles
  // playback. Releasing restores the rate active before the hold rather than a
  // hardcoded 1.0, so it composes with the song-speed control.
  static const double _holdSpeedMultiplier = 2.0;
  static const double _maxHoldPlaybackRate = 2.0;
  double? _preHoldPlaybackRate;
  bool _holdFastForward = false;

  // Notes that are part of a shock row are drawn as bars, not mines, so the
  // painter skips them and draws [_shocks] instead.
  final Set<StepNote> _shockNotes = {};
  final List<ShockRow> _shocks = [];

  // Assist tick: sorted distinct row seconds (taps + hold/roll heads, mines
  // excluded) that get an audible tick as the playhead crosses them. [TickClock]
  // fires them against the audio-thread clock rather than this render loop,
  // where dense streams jank exactly when notes are closest. If the engine or
  // sample fails to load the clock simply never fires.
  List<double> _tickSeconds = const [];
  final TickClock _tickClock = TickClock();

  // Tempo-change and stop markers, in chart seconds, built once from the chart's
  // timing so the field and minimap can show where the song shifts speed / halts.
  List<BpmMarker> _bpmMarkers = const [];
  List<StopMarker> _stopMarkers = const [];

  // Second→beat map for beat-locked scrolling: arrows are spaced by beat, so
  // BPM changes speed the field up/down and stops freeze it. Empty when the
  // chart carries no BPM data, in which case the field scrolls by constant time.
  ChartTiming _timing = ChartTiming.empty;

  // L/R foot parity for the current chart, solved once on load (client-side, so
  // the heuristic is tunable without regenerating assets). [_stances] is the
  // same solve read as pad positions, so the arrow badges and the dancing feet
  // always agree.
  Map<StepNote, Foot> _feet = const {};
  List<ParityStance> _stances = const [];

  // Chart notes ascending by second, plus the holds alone in the same order.
  // Sorted order is what lets the painter binary-search the visible window each
  // frame instead of walking the whole chart.
  List<StepNote> _notes = const [];
  List<StepNote> _holds = const [];

  // Previous same-foot note for each footed note, precomputed so the foot-path
  // pass touches only on-screen notes instead of replaying the chart's L/R walk
  // every frame.
  Map<StepNote, StepNote> _footPrev = const {};

  void _prepareNotes() {
    final src = widget.steps.notes;
    bool sorted = true;
    for (int i = 1; i < src.length; i++) {
      if (src[i].second < src[i - 1].second) {
        sorted = false;
        break;
      }
    }
    _notes =
        sorted ? src : ([...src]..sort((a, b) => a.second.compareTo(b.second)));
    _holds = [
      for (final n in _notes)
        if (n.isHold) n,
    ];
  }

  // Chain each footed note to the previous note struck by the same foot. Mines
  // and shock rows don't take a foot, same as the draw pass.
  void _buildFootLinks() {
    final links = <StepNote, StepNote>{};
    StepNote? prevLeft;
    StepNote? prevRight;
    for (final n in _notes) {
      if (n.type == StepType.mine) continue;
      if (_shockNotes.contains(n)) continue;
      final foot = _feet[n];
      if (foot == null) continue;
      final prev = foot == Foot.left ? prevLeft : prevRight;
      if (prev != null) links[n] = prev;
      if (foot == Foot.left) {
        prevLeft = n;
      } else {
        prevRight = n;
      }
    }
    _footPrev = links;
  }

  // Real DDR World sprites when bundled (assets/noteskin/), else vector. Null
  // until the sprite load resolves; the field paints nothing for that moment
  // rather than flashing vector receptors the sprite skin then replaces. The
  // resolve is cached statically, so only the app's first preview ever waits.
  Noteskin? _skin = SpriteNoteskin.resolved
      ? SpriteNoteskin.resolvedSkin ?? const VectorNoteskin()
      : null;

  // Note-density histogram for the scrub minimap, each bucket carrying its
  // rhythm colours so seeking shows both intensity and the kinds of notes there.
  List<MinimapBucket> _minimap = const [];

  // Pixels a note travels per second of chart time, before [_rate]. Only the
  // fallback for charts with no timing data — the beat-locked path uses
  // [_pxPerBeat] — expressed at a nominal 180-BPM reference so the two agree.
  static const double _referenceBpm = 180.0;
  double get _pxPerSecond =>
      _travelPx * (_referenceBpm * _rate) / _arcadeTravelConstant * _zoom;

  // The arcade's speed↔time law: at read speed R an arrow is on screen for
  // (k / R) seconds, so a CONSTANT window of N ms is read speed k × 1000 / N.
  // At read speed 600 an arrow is visible ~0.62s, and CONSTANT's 1000ms default
  // reads like SPEED 370.
  //
  // k = 370, measured from the running game — three CONSTANT guideline points
  // agree exactly (400↔925ms, 500↔740ms, 370↔1000ms). It can't be read from
  // config: the on-screen geometry that turns the stored options into a travel
  // time isn't a stored number.
  static const double _arcadeTravelConstant = 370.0;

  // Vertical distance an arrow travels in THIS field: bottom edge to receptor
  // line. Set from the painter's layout each build; the fallback only covers
  // the first frame.
  double _travelPx = 600;

  // Beat-locked spacing: pixels per chart beat. DDR's scroll VELOCITY is the
  // read speed (BPM × mod), so at one x-mod a 360-BPM stretch scrolls twice as
  // fast as a 180-BPM one. Working that through the travel law leaves a
  // constant px-per-beat, which is why a note's on-screen speed tracks the
  // LOCAL tempo (via [ChartTiming]'s slope) rather than the dominant BPM.
  double get _pxPerBeat =>
      60.0 * _travelPx * _rate / _arcadeTravelConstant * _zoom;

  int get _effectiveChartBpm =>
      widget.chartBpm > 0 ? widget.chartBpm : constants.songBpm;

  // BPM of the tempo section under the playhead — NOT the dominant chart BPM.
  // Read off the raw [Bpm] segments rather than [ChartTiming]'s slope, which
  // flattens to zero inside a stop and would read "BPM 0" mid-halt.
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

  // CONSTANT as its equivalent read speed (see [_arcadeTravelConstant]). Depends
  // only on the window, so it stays put when the scroll speed changes — see
  // [_constantVisibleReadSpeed] for the live-tracking value the UI shows. Null
  // when CONSTANT is off.
  int? get _constantReadSpeed {
    final c = _effectiveConstantMs;
    if (c == null) return null;
    return (_arcadeTravelConstant * 1000.0 / c).round();
  }

  // The read speed a player actually READS at with CONSTANT engaged. Arrows
  // still travel at the dialled speed, but CONSTANT reveals only its last `ms`,
  // so the effective read is the faster of the two. Folds in [_rate], so unlike
  // [_constantReadSpeed] it moves with the speed type. Null when CONSTANT is off.
  int? get _constantVisibleReadSpeed {
    final rc = _constantReadSpeed;
    if (rc == null) return null;
    final dialled = _effectiveChartBpm * _rate;
    return math.max(dialled, rc.toDouble()).round();
  }

  // Read speed the CURRENT tempo section reads at: localBpm × mod, full stop.
  // CONSTANT is deliberately not folded in — it changes arrow VISIBILITY, not
  // scroll velocity, and the cabinet's readout ignores it too.
  int get _liveReadSpeed => (_localBpm * _rate).round();

  double get _endSecond =>
      widget.songLength > 0 ? widget.songLength : _lastNoteSecond();

  double _lastNoteSecond() {
    if (_notes.isEmpty) return 0;
    final n = _notes.last;
    return (n.endSecond ?? n.second) + 1;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadSpeedSettings();
    _loadConstant();
    _loadTurn();
    _loadTimingOffsets();
    _prepareNotes();
    _detectShocks();
    _assignFeet();
    _buildFootLinks();
    _buildTickTimes();
    _buildTimingMarkers();
    _buildDensity();
    // Prefer real DDR World sprites if they're bundled; repaint once loaded.
    if (_skin == null) {
      SpriteNoteskin.tryLoad().then((skin) {
        if (mounted) setState(() => _skin = skin ?? const VectorNoteskin());
      });
    }
    _tickClock.load("assets/audio/assist_tick.wav").then((_) {
      if (!mounted) {
        _tickClock.dispose();
        return;
      }
      _tickClock.setRows(_tickSeconds);
      // If the user hit play before the engine finished loading, anchor now.
      if (_playing) {
        _tickClock.start(chartSecond: _second, rate: _playbackRate);
      }
    }).catchError((Object e, StackTrace st) {
      // Engine/sample failed to load: the tick stays silent. Surface it so a
      // device that plays nothing is diagnosable instead of mysteriously mute.
      debugPrint("TickClock load failed: $e");
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
      _prepareNotes();
      _detectShocks();
      _assignFeet();
      _buildFootLinks();
      _buildTickTimes();
      _buildTimingMarkers();
      _buildDensity();
      setState(() {
        _second = 0;
        _zoom = 1.0; // the study lens is per-chart; snap back on a new chart
      });
    }
    // A different sync reading means the stored offsets belong to another
    // chart's bias — re-seed so the new one still opens near zero.
    if (old.sync?.biasMs != widget.sync?.biasMs) {
      _loadTimingOffsets();
      setState(() {});
    }
    // Toggling the assist tick mid-play starts or silences the clock at once.
    if (old.assistTickOn != widget.assistTickOn) {
      _resyncTickClock();
    }
    // The minimap bakes each note's quant bucket, so a palette change has to
    // rebuild it — the field itself re-reads the colours on the next paint.
    if (old.arcadeQuantOn != widget.arcadeQuantOn) {
      _buildDensity();
    }
  }

  // Restore the SPEED TYPE selector and each type's dialled value. REAL SPEED
  // opens on the app-wide read-speed preference (shared with the song page's
  // mod picker) rather than its own saved value, and HI-SPEED derives from that
  // same target, so both types open near the same speed. Dialling here still
  // persists — it just doesn't outrank the preference next open.
  void _loadSpeedSettings() {
    _hispeedType = Settings.getInt(Settings.chartPreviewSpeedTypeKey) == 1;
    final savedScroll = Settings.getInt(Settings.chartPreviewScrollSpeedKey);
    final appReadSpeed = Settings.getInt(Settings.chosenReadSpeedKey);
    _scrollSpeed = _snapScroll(appReadSpeed > 0
        ? appReadSpeed
        : (savedScroll > 0 ? savedScroll : constants.chosenReadSpeed));
    final savedHispeed = Settings.getInt(Settings.chartPreviewHispeedKey);
    _hispeedHundredths =
        _snapHispeed(savedHispeed > 0 ? savedHispeed : _derivedHundredths);
  }

  int _snapScroll(int v) =>
      ((v / _scrollStep).round() * _scrollStep).clamp(_scrollMin, _scrollMax);

  // The cabinet's hi-speed snap: clamp to 25–800, then floor to a multiple of 5
  // (x0.05) — except sub-x1.00 values bump back up one step, i.e. round UP.
  int _snapHispeed(int h) {
    h = h.clamp(_hispeedMin, _hispeedMax);
    final r = h % _hispeedStep;
    if (r != 0) {
      h -= r;
      if (h < 100) h += _hispeedStep;
    }
    return h;
  }

  // The CONSTANT window equivalent to the app-wide read-speed preference, so
  // switching CONSTANT on doesn't change how fast the chart reads. Inverts the
  // travel law (see [_arcadeTravelConstant]) onto the dial's 10ms grid, flooring
  // so the chosen step still meets the saved preference.
  double get _constantMsForReadSpeed {
    final saved = Settings.getInt(Settings.chosenReadSpeedKey);
    final readSpeed = saved > 0 ? saved : constants.chosenReadSpeed;
    if (readSpeed <= 0) return _constantDefaultMs;
    final exact = _arcadeTravelConstant * 1000.0 / readSpeed;
    final floored =
        (exact / _constantStepMs).floor() * _constantStepMs.toDouble();
    return floored.clamp(_constantMinMs, _constantMaxMs);
  }

  // Restore the CONSTANT modifier. Only the on/off flag carries across (as 0/1
  // — Settings has no bool getter); the window is re-derived from the read-speed
  // preference, since a stored one goes stale as soon as that preference moves.
  void _loadConstant() {
    _constantMs = _constantMsForReadSpeed;
    _constantOn = Settings.getInt(Settings.constantOnKey) == 1;
  }

  // The ms value handed to the painter: null (NORMAL, arrows always visible)
  // unless the modifier is switched on.
  double? get _effectiveConstantMs => _constantOn ? _constantMs : null;

  // Restore ARCADE SYNC and both TIMING offsets. VISUAL is stored as tenths of a
  // dial unit so its 0.1 step round-trips through the int-only Settings API;
  // AUDIO is already whole ms. For both, "never set" (0) is the neutral default.
  void _loadTimingOffsets() {
    _arcadeSyncOn = Settings.getInt(Settings.arcadeSyncOnKey) == 1;
    _visualOffset = _clampVisualOffset(
        Settings.getInt(Settings.chartPreviewVisualOffsetKey) / 10.0);
    _audioOffsetMs = _clampAudioOffsetMs(
        Settings.getInt(Settings.chartPreviewAudioOffsetMsKey).toDouble());

    // The offsets cancel a PER-SONG bias, so a pair seeded against another
    // song's reading would ride along and land this one off by the difference
    // between the two biases.
    if (_arcadeSyncOn && !_offsetsMatchThisSong()) {
      _seedOffsetsFromSync();
    }

    // After any re-seed, so the baseline is what the dials actually show.
    _visualOffsetOnEntry = _visualOffset;
    _audioOffsetMsOnEntry = _audioOffsetMs;

    _tickClock.audioOffset = _audioOffsetSeconds;
  }

  /// Whether the stored offsets were seeded against THIS song's bias. Compares
  /// the bias they were computed for (persisted alongside them) with the one the
  /// song actually carries, so a user's own manual dialling on this song is
  /// preserved while another song's correction is not.
  bool _offsetsMatchThisSong() {
    final storedFor =
        Settings.getInt(Settings.chartPreviewOffsetForBiasKey) / 100.0;
    return (storedFor - _songBiasMs).abs() < 0.005;
  }

  // Snap the VISUAL dial to its 0.1 grid inside the cabinet's ±5.0 range.
  static double _clampVisualOffset(double units) {
    final clamped = units.clamp(_visualOffsetMin, _visualOffsetMax);
    return (clamped / _visualOffsetStep).round() * _visualOffsetStep;
  }

  // AUDIO is whole milliseconds — no sub-ms dial, players talk in integers.
  static double _clampAudioOffsetMs(double ms) =>
      ms.roundToDouble().clamp(_audioOffsetMinMs, _audioOffsetMaxMs);

  // The VISUAL dial reads like the cabinet's: always signed, one decimal, so
  // "+0.0" reads as deliberately neutral rather than unset.
  static String _visualOffsetLabel(double units) =>
      "${units >= 0 ? "+" : "-"}${units.abs().toStringAsFixed(1)}";

  // AUDIO reads in the unit players actually use ("+10ms").
  static String _audioOffsetLabel(double ms) =>
      "${ms >= 0 ? "+" : "-"}${ms.abs().round()}ms";

  // The song's measured sync bias in ms, exactly as the song page's Sync card
  // reads it: POSITIVE means the chart plays FAST (steps land ahead of the
  // audio), negative means SLOW. 0 when the song ships no sync data.
  double get _songBiasMs => widget.sync?.biasMs ?? 0;

  // ARCADE SYNC treats the song's own bias as the STARTING POINT and the two
  // dials as adjustments from it, matching how you'd actually sync on a cabinet:
  // the song is already off by some amount, and you dial against that. So a song
  // measured at +9.0ms reads "+9.0ms" the moment the mode is switched on, and a
  // dialled -2.0ms takes the effective figure to +7.0ms.
  //
  // Both dials are folded into one effective millisecond figure — VISUAL is
  // converted from its dial units so the two are commensurable.
  double get _effectiveSyncMs =>
      _songBiasMs +
      _visualOffset * _visualOffsetUnitSeconds * 1000 +
      _audioOffsetMs;

  // Pre-dial the offsets that cancel the song's measured bias, so engaging
  // ARCADE SYNC opens already corrected. The correction is the bias with its
  // sign flipped (a chart running +9ms FAST is fixed by −9ms), the same
  // adjustment the song page's Sync card suggests.
  //
  // The bias is split across the two dials by granularity, not arbitrarily: the
  // VISUAL dial is coarse (one unit ≈ 16.67ms) so it takes as many WHOLE units
  // as fit without overshooting, and the finer AUDIO dial (1ms) mops up the
  // remainder. A ±9ms bias therefore lands entirely on AUDIO, while a large one
  // uses both. Each is clamped to its own range, so a bias beyond their combined
  // reach is corrected as far as the dials allow.
  void _seedOffsetsFromSync() {
    const msPerVisualUnit = _visualOffsetUnitSeconds * 1000;
    final correctionMs = -_songBiasMs;

    // The AUDIO dial is exact in whole milliseconds while VISUAL only lands on
    // multiples of ~1.67ms (0.1 of a 16.67ms unit), so AUDIO carries the
    // correction wherever it can — that's what keeps typical songs landing at
    // 0.0-0.5ms. VISUAL only picks up the overflow past AUDIO's ±50ms range,
    // which real data never reaches (measured max |bias| is ~50ms).
    final audioShare = _clampAudioOffsetMs(correctionMs);
    _visualOffset =
        _clampVisualOffset((correctionMs - audioShare) / msPerVisualUnit);
    // Re-derive AUDIO from what VISUAL actually landed on, so the 0.1-grid
    // rounding is absorbed here rather than left as residue.
    _audioOffsetMs =
        _clampAudioOffsetMs(correctionMs - _visualOffset * msPerVisualUnit);

    Settings.setInt(
        Settings.chartPreviewVisualOffsetKey, (_visualOffset * 10).round());
    Settings.setInt(
        Settings.chartPreviewAudioOffsetMsKey, _audioOffsetMs.round());
    _stampOffsetBias();
  }

  /// Record which song bias the current offsets were dialled against, so a later
  /// preview can tell whether they belong to its song. Called on every write to
  /// either dial — including manual drags, which adopt this song's bias so a
  /// user's hand-tuned values are kept when they come back to it.
  void _stampOffsetBias() => Settings.setInt(
      Settings.chartPreviewOffsetForBiasKey, (_songBiasMs * 100).round());

  /// Below this the effective sync is reported as "on the beat" — half of the
  /// AUDIO dial's 1ms resolution, so a reading only counts as off-beat when a
  /// dial could actually do something about it.
  static const double _onBeatEpsilonMs = 0.05;

  /// True when the song has nothing to report: no sync block AND no dialled
  /// offset that would make an effective figure meaningful.
  bool get _hasNoSyncReading =>
      widget.sync == null && _visualOffset == 0 && _audioOffsetMs == 0;

  /// FAST/SLOW hue for the current effective sync, or null when it's on the beat
  /// (or unknown). Shared by the ARCADE SYNC caption and the tempo badge so the
  /// two never disagree about which way the song leans.
  Color? _syncAccent(BuildContext context) {
    if (_hasNoSyncReading) return null;
    final ms = _effectiveSyncMs;
    return timingAccent(
      ms.abs() < _onBeatEpsilonMs ? 0 : ms,
      Theme.of(context).brightness == Brightness.dark,
    );
  }

  /// Compact effective sync for the tempo badge: a signed millisecond figure
  /// ("+9.0ms" / "-4.5ms" / "0.0ms"), with FAST/SLOW carried by its colour since
  /// the badge is tight for space. Same number [_arcadeSyncSummary] spells out.
  /// Null hides the segment — including whenever ARCADE SYNC is off, where the
  /// dials are gated to zero and a figure would describe an unapplied correction.
  String? get _syncBadgeLabel {
    if (!_arcadeSyncOn || _hasNoSyncReading) return null;
    final ms = _effectiveSyncMs;
    if (ms.abs() < _onBeatEpsilonMs) return "0.0ms";
    return "${ms > 0 ? "+" : "-"}${ms.abs().toStringAsFixed(1)}ms";
  }

  // The ARCADE SYNC caption: the effective sync after both dials, in the same
  // terms and sign convention as the previous page's Sync card. Reads as the
  // song's raw bias until a dial is moved, then tracks the adjustment.
  String get _arcadeSyncSummary {
    if (_hasNoSyncReading) return "no sync data for this song";
    final ms = _effectiveSyncMs;
    final magnitude = "${ms.abs().toStringAsFixed(1)}ms";
    if (ms.abs() < _onBeatEpsilonMs) return "on the beat";
    return ms > 0 ? "FAST by $magnitude" : "SLOW by $magnitude";
  }

  // Toggle ARCADE SYNC. Engaging it forces the assist tick on (restoring the
  // prior state on the way out) so an AUDIO OFFSET is audible immediately.
  void _toggleArcadeSync() {
    HapticFeedback.selectionClick();
    final next = !_arcadeSyncOn;
    setState(() {
      _arcadeSyncOn = next;
      // Pre-dial the correction cancelling the song's bias so the mode opens in
      // sync. Keyed on the recorded bias rather than the dials being zero: zero
      // is itself a valid hand-tuned value.
      if (next && !_offsetsMatchThisSong()) {
        _seedOffsetsFromSync();
      }
      // Rewind the LIVE dials to what the page opened with. Deliberately no
      // Settings write, so a mid-experiment value can't become the baseline.
      if (!next) {
        _visualOffset = _visualOffsetOnEntry;
        _audioOffsetMs = _audioOffsetMsOnEntry;
      }
    });
    Settings.setInt(Settings.arcadeSyncOnKey, next ? 1 : 0);

    final toggleTick = widget.onToggleAssistTick;
    if (toggleTick != null) {
      if (next) {
        _tickBeforeArcadeSync = widget.assistTickOn;
        if (!widget.assistTickOn) toggleTick();
      } else {
        // Restore whatever the tick was before we forced it, if we changed it.
        final before = _tickBeforeArcadeSync;
        if (before != null && before != widget.assistTickOn) toggleTick();
        _tickBeforeArcadeSync = null;
      }
    }

    // Both offsets change effect the instant the gate flips (they read through
    // it), so the tick schedule has to be re-seated either way.
    _tickClock.audioOffset = _audioOffsetSeconds;
    _resyncTickClock();
    _flashScrubOverlay(next ? "ON" : "OFF", "ARCADE SYNC");
  }

  // Drag horizontally on either TIMING chip to sweep that offset. Same drag feel
  // as the CONSTANT chip (260px sweeps the full range), with a detent haptic per
  // step. The visual offset needs no explicit repaint: it reaches the painter on
  // the next build and setState covers that.
  void _onTimingOffsetDrag({required bool visual, required double dx}) {
    if (visual) {
      final next = _clampVisualOffset(
          _visualOffset + dx / 260 * (_visualOffsetMax - _visualOffsetMin));
      if (next == _visualOffset) return;
      HapticFeedback.selectionClick();
      setState(() => _visualOffset = next);
      Settings.setInt(
          Settings.chartPreviewVisualOffsetKey, (next * 10).round());
      _stampOffsetBias(); // hand-tuned for THIS song — don't re-seed over it
      _flashScrubOverlay(_visualOffsetLabel(next), "VISUAL OFFSET");
      return;
    }
    final next = _clampAudioOffsetMs(
        _audioOffsetMs + dx / 260 * (_audioOffsetMaxMs - _audioOffsetMinMs));
    if (next == _audioOffsetMs) return;
    HapticFeedback.selectionClick();
    setState(() {
      _audioOffsetMs = next;
      // Re-seat the schedule so the new offset applies from here rather than
      // only to rows beyond the current prime window.
      _tickClock.audioOffset = _audioOffsetSeconds;
    });
    _resyncTickClock();
    Settings.setInt(Settings.chartPreviewAudioOffsetMsKey, next.round());
    _stampOffsetBias(); // hand-tuned for THIS song — don't re-seed over it
    _flashScrubOverlay(_audioOffsetLabel(next), "AUDIO OFFSET");
  }

  // Tap either TIMING chip to reset that offset to neutral — the dial is fiddly
  // to land back on zero by dragging, and "back to no offset" is the common reset.
  void _resetTimingOffset({required bool visual}) {
    HapticFeedback.selectionClick();
    setState(() {
      if (visual) {
        _visualOffset = 0;
      } else {
        _audioOffsetMs = 0;
        _tickClock.audioOffset = _audioOffsetSeconds;
      }
    });
    if (!visual) _resyncTickClock();
    Settings.setInt(
      visual
          ? Settings.chartPreviewVisualOffsetKey
          : Settings.chartPreviewAudioOffsetMsKey,
      0,
    );
    _stampOffsetBias(); // a deliberate zero is also a choice for THIS song
    _flashScrubOverlay(
      visual ? _visualOffsetLabel(0) : _audioOffsetLabel(0),
      visual ? "VISUAL OFFSET" : "AUDIO OFFSET",
    );
  }

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
    setState(() {
      _turn = next;
      // The footing belongs to the turned chart, so it is re-solved here rather
      // than only when the chart itself changes.
      _assignFeet();
      _buildFootLinks();
    });
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
  // Switching ON re-seeds the window from the read-speed preference (see
  // [_constantMsForReadSpeed]) rather than resuming the last dragged value, so
  // the modifier always engages at the user's own read speed.
  void _toggleConstant() {
    HapticFeedback.selectionClick();
    final next = !_constantOn;
    setState(() {
      _constantOn = next;
      if (next) _constantMs = _constantMsForReadSpeed;
    });
    Settings.setInt(Settings.constantOnKey, next ? 1 : 0);
    if (next) Settings.setInt(Settings.constantMsKey, _constantMs.round());
    _flashScrubOverlay(
      next ? "${_constantMs.round()}ms" : "OFF",
      _constantCaption,
    );
  }

  // Overlay caption for CONSTANT flashes: carries the read speed the window
  // lets you READ at (see [_constantVisibleReadSpeed]), so a wall-clock time
  // reads in the unit players think in.
  String get _constantCaption {
    final eq = _constantVisibleReadSpeed;
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
        if (n.type == StepType.mine) continue; // shocks handled below
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
    _minimap = List<MinimapBucket>.generate(buckets, (i) {
      final total = counts[i];
      final segments = <MinimapSegment>[];
      if (total > 0) {
        for (int j = 0; j < _minimapPalette.length; j++) {
          final count = colorCounts[i][j];
          if (count == 0) continue;
          segments.add(MinimapSegment(_minimapPalette[j], count / total));
        }
      }
      return MinimapBucket(
        level: peak > 0 ? total / peak : 0,
        segments: segments,
        holdLevel: holdPeak > 0 ? holdCounts[i] / holdPeak : 0,
        hasShock: shockFlags[i],
      );
    });
  }

  // Solve the footing for the chart AS TURNED — a turn moves the arrows under
  // your feet, so a mirrored chart is danced differently and the solve re-runs
  // on every change of turn.
  //
  // The solve works on permuted COPIES, so its feet map comes back keyed by
  // those; StepNote has no value equality, so it's re-keyed by position (which
  // _turned preserves one-for-one) into the chart space the rest of the widget
  // speaks. The stances stay in turned space — they describe where the feet are.
  void _assignFeet() {
    final source = widget.steps.notes;
    final turned = _turned(source);
    final analysis = FootAssigner.analyse(turned, widget.mode);
    _feet = {
      for (int i = 0; i < source.length; i++)
        if (analysis.feet[turned[i]] case final foot?) source[i]: foot,
    };
    _stances = analysis.stances;
  }

  // [notes] with every column sent through the active TURN map. Returns the
  // originals untouched when no turn is on, so the common case allocates
  // nothing.
  List<StepNote> _turned(List<StepNote> notes) {
    if (_turn == _Turn.off) return notes;
    final map = _colMap;
    return [
      for (final n in notes)
        if (n.col >= 0 && n.col < map.length)
          StepNote(
            beat: n.beat,
            second: n.second,
            col: map[n.col],
            type: n.type,
            endBeat: n.endBeat,
            endSecond: n.endSecond,
          )
        else
          n,
    ];
  }

  // Distil the chart's BPM segments and stops into render-ready markers on the
  // seconds axis. A BPM segment is only a "change" when its value differs from
  // the one before it, so the leading segment (and any coalesced duplicates)
  // don't plant a redundant marker at the start of the field.
  void _buildTimingMarkers() {
    final bpm = <BpmMarker>[];
    int? prev;
    for (final b in widget.bpms) {
      final v = b.val;
      if (prev != null && v != prev) {
        bpm.add(BpmMarker(b.st, v));
      }
      prev = v;
    }
    _bpmMarkers = bpm;
    _stopMarkers = [
      for (final s in widget.stops)
        if (s.dur > 0) StopMarker(s.st, s.dur),
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
        _shocks
            .add(ShockRow(mines.first.second, {for (final m in mines) m.col}));
        _shockNotes.addAll(mines);
      }
    });
    // Ascending by second (the map iterates in hash order) so the painter can
    // stop at the first row beyond the visible window.
    _shocks.sort((a, b) => a.second.compareTo(b.second));
  }

  // Distinct row seconds for the assist tick: taps and hold/roll heads tick,
  // mines don't (shock rows are mines, so they drop out with them). Chords
  // collapse to one tick via the same 1ms rounding [_detectShocks] uses.
  void _buildTickTimes() {
    final Set<int> keys = {};
    for (final n in widget.steps.notes) {
      if (n.type == StepType.mine) continue;
      keys.add((n.second * 1000).round());
    }
    _tickSeconds = [for (final k in keys) k / 1000.0]..sort();
    _tickClock
        .setRows(_tickSeconds); // no-op before the engine finishes loading
  }

  // (Re)anchor the tick clock to the live playhead + rate, so upcoming rows are
  // scheduled from where we actually are. Called whenever the chart→clock
  // mapping changes: play start, seek/scrub, and playback-rate changes. If the
  // engine isn't loaded yet the clock ignores this; initState re-anchors on load.
  void _resyncTickClock() {
    if (_playing && widget.assistTickOn) {
      _tickClock.start(chartSecond: _second, rate: _playbackRate);
    } else {
      _tickClock.stop();
    }
  }

  // Silence and unschedule everything: pause, chart switch, tick toggled off,
  // dispose. Cheap and idempotent.
  void _cancelPendingTicks() => _tickClock.stop();

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

    // No setState here: writing the playhead notifier repaints the canvas and
    // the HUD listeners directly. Only the end-of-song auto-pause (inside
    // [_pause]) flips real widget state.
    double next = _second;
    if (_playing) {
      next += dt * _playbackRate;
    } else if (_flingVel != 0) {
      // Inertial scrub: advance by the current velocity, then decay it.
      next += _flingVel * dt;
      _flingVel *= math.exp(-_flingDecay * dt);
      if (_flingVel.abs() < _flingMin) {
        _flingVel = 0;
        _stopTickerIfIdle();
      }
    }
    if (next >= _endSecond) {
      next = _endSecond;
      _flingVel = 0;
      _pause();
      _stopTickerIfIdle();
    } else if (next <= 0) {
      next = 0;
      _flingVel = 0;
      _stopTickerIfIdle();
    }
    _second = next;
    // The render loop no longer schedules ticks — [_tickClock] fires them off
    // SoLoud's audio-thread clock, immune to this loop's jank. Playback state
    // changes (play/pause/seek/rate) drive the clock via [_resyncTickClock].
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
    // Starting playback tucks both edge panels away so the running chart owns
    // the screen — the options card and the bottom transport collapse together.
    // Either tab brings its panel back mid-play (neither pauses). The header
    // (title) rides the paused state, so it slides away on its own.
    setState(() {
      _playing = true;
      _shadeOpen = false;
      _transportVisible = false;
    });
    _resyncTickClock(); // anchor the audio clock to this start position + rate
  }

  void _toggleShade() {
    HapticFeedback.selectionClick();
    // Purely a visibility toggle, like the right-edge transport tab — it never
    // touches playback. (The shade is still auto-hidden while playing via the
    // `!_playing` gate in [_buildSettingsShade], but tapping the tab won't
    // pause a running chart.)
    setState(() => _shadeOpen = !_shadeOpen);
  }

  void _pause() {
    if (!_playing) return;
    _cancelPendingTicks(); // scheduled rows ahead of the playhead go silent
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
    // Playhead-only change: the notifier repaints every playhead listener.
    _second = (_second + delta).clamp(0.0, _endSecond);
    _resyncTickClock(); // re-anchor: the playhead jumped out from under the clock
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
      _play(); // _play re-anchors the clock at the new rate
    } else {
      _resyncTickClock(); // re-anchor at the sped-up rate
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
      _pause(); // stops the clock
    } else {
      _resyncTickClock(); // re-anchor at the restored rate
    }
  }

  // One detent of the active speed dial — the ∓ buttons and the drag both
  // come through here with dir ±1, so they step identically: HI-SPEED moves
  // x0.05 (the cabinet dial's grid), SCROLL SPEED moves 10 (the cabinet's
  // choice-list spacing). Each change persists its own type's value.
  void _stepSpeed(int dir) {
    if (_hispeedType) {
      final next = (_hispeedHundredths + dir * _hispeedStep)
          .clamp(_hispeedMin, _hispeedMax);
      if (next == _hispeedHundredths) return;
      HapticFeedback.selectionClick();
      setState(() => _hispeedHundredths = next);
      Settings.setInt(Settings.chartPreviewHispeedKey, next);
      _flashScrubOverlay(fmtXMod(_rate), "HI-SPEED");
    } else {
      final next =
          (_scrollSpeed + dir * _scrollStep).clamp(_scrollMin, _scrollMax);
      if (next == _scrollSpeed) return;
      HapticFeedback.selectionClick();
      setState(() => _scrollSpeed = next);
      Settings.setInt(Settings.chartPreviewScrollSpeedKey, next);
      _flashScrubOverlay("$_scrollSpeed", "REAL SPEED");
    }
  }

  // Tap on the pane: switch SPEED TYPE. Each type keeps its own dialled
  // value, so toggling back restores the previous speed exactly — matching
  // the cabinet's separate Hispeed/ScrollSpeed fields.
  void _toggleSpeedType() {
    HapticFeedback.selectionClick();
    setState(() => _hispeedType = !_hispeedType);
    Settings.setInt(Settings.chartPreviewSpeedTypeKey, _hispeedType ? 1 : 0);
    _flashScrubOverlay(
      _hispeedType ? fmtXMod(_rate) : "$_scrollSpeed",
      _hispeedType ? "HI-SPEED" : "REAL SPEED",
    );
  }

  // The cabinet's num_min / num_core / num_max readouts: each of the chart's
  // three BPM fields times the active multiplier, rounded.
  //
  //   min  = bpmmin       (this repo's true_min)
  //   core = the core BPM (this repo's dominant_bpm)
  //   max  = bpmmax       (the REAL SPEED divisor, [_scrollDivisorBpm])
  //
  // core is clamped into [min, max] so it can't fall outside the pair even if
  // the parser's dominant sits above the sustained peak. All three are always
  // shown — the cabinet always renders three numbers, even when they coincide.
  (int min, int core, int max) get _scrollSpeeds {
    final maxBpm = _scrollDivisorBpm;
    final minBpm = _minChartBpm.clamp(0, maxBpm);
    final coreBpm = _effectiveChartBpm.clamp(minBpm, maxBpm);
    return (
      (minBpm * _rate).round(),
      (coreBpm * _rate).round(),
      (maxBpm * _rate).round(),
    );
  }

  // The trio as the compact readout label, e.g. "150–301–602". Shows all three
  // whenever the chart has any BPM spread — including when just min==core or
  // core==max, matching the cabinet's num_min/num_core/num_max. Shown under
  // the dialled number for both speed types: the scroll speeds you actually
  // read at are what the trio reports, and that's as useful under a HI-SPEED
  // multiplier as under REAL SPEED.
  //
  // When the chart is constant-BPM all three fold to one number. Under REAL
  // SPEED that number is the dial itself (the multiplier is scroll/bpm, so
  // bpm × rate lands back on the dial) and repeating the big number above says
  // nothing — null hides the row. Under HI-SPEED the fold is a genuinely new
  // number (bpm × the multiplier), so it stays. When rounding or clamping
  // leaves the REAL SPEED fold a step off the dial that difference is real,
  // so it stays visible too.
  String? get _scrollSpeedLabel {
    final (min, core, max) = _scrollSpeeds;
    if (min == core && core == max) {
      if (_hispeedType) return "$min";
      return min == _scrollSpeed ? null : "$min";
    }
    return "$min–$core–$max";
  }

  // Drag on the speed pane: horizontal movement turns the active dial one
  // detent per ~7px, so a full-width sweep covers a useful chunk of either
  // range. Accumulate sub-step pixels so a slow drag still lands each detent.
  double _readSpeedDragAccum = 0;
  static const double _pxPerReadSpeedStep = 7;

  void _onReadSpeedDrag(double dx) {
    _readSpeedDragAccum += dx;
    while (_readSpeedDragAccum.abs() >= _pxPerReadSpeedStep) {
      final dir = _readSpeedDragAccum > 0 ? 1 : -1;
      _readSpeedDragAccum -= dir * _pxPerReadSpeedStep;
      final before = _activeHundredths;
      _stepSpeed(dir);
      if (_activeHundredths == before) {
        _readSpeedDragAccum = 0; // pinned at an end of the dial
        break;
      }
    }
  }

  // Drag on the song-speed pane: horizontal movement scales the playback rate.
  // Fire a detent haptic each time the rate crosses one of the 0.05× steps the
  // value snaps to on-screen, so the sweep ticks under the finger.
  void _onPlaybackRateDrag(double dx) {
    final next =
        (_playbackRate + dx / 260).clamp(_minPlaybackRate, _maxPlaybackRate);
    if (next == _playbackRate) return;
    final crossedStep = (next * 20).round() != (_playbackRate * 20).round();
    setState(() => _playbackRate = next);
    _resyncTickClock(); // re-anchor at the new rate
    if (crossedStep) HapticFeedback.selectionClick();
    _flashScrubOverlay("${next.toStringAsFixed(2)}×", "SONG SPEED");
  }

  void _resetPlaybackRate() {
    if (_playbackRate == 1.0) return;
    HapticFeedback.selectionClick();
    setState(() => _playbackRate = 1.0);
    _resyncTickClock(); // re-anchor at 1.0×
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
    // Playhead-only change — no setState; the notifier drives the repaint.
    _second = (_second - _pxToSeconds(dy)).clamp(0.0, _endSecond);
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
    _tickClock.dispose();
    _playhead.dispose();
    super.dispose();
  }

  void _toggleTransport() {
    HapticFeedback.selectionClick();
    setState(() => _transportVisible = !_transportVisible);
  }

  @override
  Widget build(BuildContext context) {
    final dirs = widget.mode == Modes.singles ? kSingleDirs : kDoubleDirs;
    return LayoutBuilder(builder: (context, constraints) {
      // Feed the real field geometry into the speed law: an arrow's travel is
      // the bottom edge up to the receptor line (which the painter places at
      // ChartPainter.receptorBase below the top safe-area inset). Keeping
      // this in sync means a taller phone scrolls FASTER in px/s so the
      // arcade's travel TIME at a given read speed is preserved, rather than
      // every device sharing one px/s and giving tall screens a longer read.
      final travel = constraints.maxHeight -
          (ChartPainter.receptorBase + MediaQuery.of(context).padding.top);
      if (travel > 0) _travelPx = travel;
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
                // RepaintBoundary so the per-frame canvas repaint (driven by
                // the playhead notifier) never invalidates the overlay/control
                // layers around it; willChange hints the compositor not to
                // bother caching a layer that changes every frame.
                // Until the skin resolves (first preview of the app run only)
                // paint nothing: a blank frame is invisible, a receptor-skin
                // swap is not.
                if (_skin == null)
                  const SizedBox.expand()
                else
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: ChartPainter(
                        notes: _notes,
                        holds: _holds,
                        shockNotes: _shockNotes,
                        shocks: _shocks,
                        bpmMarkers: _bpmMarkers,
                        stopMarkers: _stopMarkers,
                        showMeasureLines: widget.showMeasureLines,
                        feet: widget.showFootGuide ? _feet : const {},
                        footPrev: widget.showFootTrails ? _footPrev : const {},
                        dirs: dirs,
                        colMap: _colMap,
                        playhead: _playhead,
                        pxPerSecond: _pxPerSecond,
                        pxPerBeat: _pxPerBeat,
                        timing: _timing,
                        columnCount: dirs.length,
                        skin: _skin!,
                        playing: _playing,
                        zoom: _zoom,
                        constantMs: _effectiveConstantMs,
                        topInset: MediaQuery.of(context).padding.top,
                        visualOffset: _visualOffsetSeconds,
                        arcadeQuant: widget.arcadeQuantOn,
                      ),
                      size: Size.infinite,
                      willChange: true,
                    ),
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

          // Dancing feet: the parity solve read as a body on a pad, floating
          // wherever the user has dragged it — anywhere on the field, including
          // over the controls.
          //
          // Sits ABOVE the transport and scrubber, because a pad parked on top
          // of them must still be the thing your finger finds or it could never
          // be dragged off again. But BELOW the header, the settings shade and
          // the edge tabs: those are pulled over the field deliberately and for
          // a moment, so the pad passes under them rather than punching a hole
          // through whatever the user just opened.
          if (widget.showDancingFeet && _stances.isNotEmpty)
            Positioned.fill(
              // The pad places itself within these bounds; the rest of the
              // layer stays transparent to taps, so the field (and the controls
              // under it) still get everything the pad itself doesn't cover.
              child: DancingFeet(
                stances: _stances,
                playhead: _playhead,
                columnCount: dirs.length,
                visualOffset: _visualOffsetSeconds,
              ),
            ),

          // Floating header (song title / difficulty): shown whenever paused,
          // slides up out of view once playback starts so the running chart owns
          // the top of the screen. Not tied to the transport handle — the title
          // is always up while paused.
          if (widget.headerBuilder != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: _playing,
                child: AnimatedSlide(
                  offset: _playing ? const Offset(0, -1) : Offset.zero,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _playing ? 0 : 1,
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
                    // Rides the playhead notifier (the local BPM changes as the
                    // playhead crosses tempo sections) inside its own repaint
                    // boundary, so per-frame updates stay off the widget tree.
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _playhead,
                          builder: (_, __, ___) => TempoBadge(
                            bpm: _localBpm,
                            readSpeed: _liveReadSpeed,
                            // Same numbers and hue as the ARCADE SYNC caption —
                            // both read [_effectiveSyncMs], so they can't drift
                            // apart. Unlike BPM/READ this doesn't vary with the
                            // playhead, so it's computed from the outer context.
                            syncLabel: _syncBadgeLabel,
                            syncAccent: _syncAccent(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Transport (read/song speed): hidden by the right-edge tab.
                    IgnorePointer(
                      ignoring: !_transportVisible,
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.bottomCenter,
                        child: AnimatedSlide(
                          offset: _transportVisible
                              ? Offset.zero
                              : const Offset(0, 1),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: _transportVisible ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: _transportVisible
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

          // Always-visible handle to show/hide the bottom transport: a small tab
          // pinned to the right edge. Its chevron points the way the transport
          // will move (up-into-view vs down-out-of-view). Only affects the
          // bottom config — the title header rides the paused state instead.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: EdgeTab(
                leftEdge: false,
                icon: _transportVisible
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_up,
                onTap: _toggleTransport,
              ),
            ),
          ),

          // The settings-shade handle: the left-edge mirror of the transport
          // tab, replacing the old gear tucked in the header's corner. Its
          // chevron points the way the shade will move (down-into-view when
          // closed, up-out-of-view when open). Purely a visibility toggle — it
          // never pauses the chart (see [_toggleShade]).
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: EdgeTab(
                key: shadeTabKey,
                leftEdge: true,
                icon: _shadeOpen
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          // The elapsed label tracks the playhead; keep its per-frame updates
          // inside their own boundary instead of rebuilding the whole bar.
          child: RepaintBoundary(
            child: ValueListenableBuilder<double>(
              valueListenable: _playhead,
              builder: (_, s, __) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    fmtTime(s),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  Text(
                    fmtTime(_endSecond),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            color: Colors.black.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: DensityScrubBar(
              buckets: _minimap,
              playhead: _playhead,
              endSecond: _endSecond,
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
                _second = next;
              },
            ),
          ),
        ),
      ],
    );
  }

  // The settings shade: a top "pull-down" card of chart-viewing modifiers,
  // hidden behind the left-edge pull-tab until opened. Operationally it mirrors
  // the bottom transport: a panel pinned to its edge with pointer-handling
  // scoped to its own bounds, so it never blocks the full-bleed chart's
  // tap-to-play gesture and is only dismissed via its own tab — never by tapping
  // elsewhere on the field. Its body scrolls so it has room to grow toward the
  // full DDR option set (arrows, lane, scroll, assist …).
  Widget _buildSettingsShade(BuildContext context) {
    final open = _shadeOpen;
    final topInset = MediaQuery.of(context).padding.top;
    // The card's top is dynamic: when the floating header is on screen (there is
    // a headerBuilder AND we're paused) it seats below the title (a ~64px 48px
    // icon-button row in 4/12 padding) plus a 16px gap so the card reads as
    // detached from the header rather than glued to its underside; otherwise
    // there is no title above it, so it hugs the status-bar inset. Animated so it
    // glides down/up as the header appears/disappears on pause/play.
    final headerShowing = widget.headerBuilder != null && !_playing;
    final top = topInset + (headerShowing ? 64 + 16 : 8);
    return AnimatedPositioned(
      left: 0,
      right: 0,
      top: top,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedSlide(
          offset: open ? Offset.zero : const Offset(0, -1),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: open ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: SettingsShade(
              sections: _buildShadeSections(context),
            ),
          ),
        ),
      ),
    );
  }

  // The modifier sections shown in the shade. Only the arrows modifiers
  // (CONSTANT + TURN) are wired for now; the rest are placeholders reserving
  // their place so the shade already reads as the full options screen and new
  // controls slot in without a layout rethink. Mirrors the DDR World option
  // categories. The section carries no label — the controls read on their own.
  List<ShadeSection> _buildShadeSections(BuildContext context) {
    return [
      ShadeSection(
        // Tiled: CONSTANT spans the full top row; below it a row split three
        // ways — MIRROR (flip L↔R), LEFT and RIGHT turns — mirroring DDR World's
        // appearance options.
        content: Column(
          children: [
            ConstantChip(
              on: _constantOn,
              ms: _constantMs,
              equivalentReadSpeed: _constantVisibleReadSpeed,
              onTap: _toggleConstant,
              onDrag: _onConstantDrag,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TurnTile(
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
                  child: TurnTile(
                    label: "LEFT",
                    icon: Icons.rotate_left,
                    selected: _turn == _Turn.left,
                    onTap: () => _setTurn(_Turn.left),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TurnTile(
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
      // Viewing aids, split off into their own segment and laid out as two rows
      // of tiles: the parity readings (the on-arrow L/R guide, the same-foot
      // trails and the dancing-feet pad, all three drawn from one solve) above,
      // the rest — the assist tick, the measure rules and the arcade quant
      // palette — below.
      // These moved out of the floating header so it carries only title/back;
      // the toggles read the same as the TURN tiles, so they slot in as more
      // rows of the options card.
      if (widget.onToggleAssistTick != null ||
          widget.onToggleFootGuide != null ||
          widget.onToggleFootTrails != null ||
          widget.onToggleDancingFeet != null ||
          widget.onToggleMeasureLines != null ||
          widget.onToggleArcadeQuant != null)
        ShadeSection(
          content: Column(
            spacing: 8,
            children: [
              if (widget.onToggleFootGuide != null ||
                  widget.onToggleFootTrails != null ||
                  widget.onToggleDancingFeet != null)
                Row(
                  spacing: 8,
                  children: [
                    if (widget.onToggleFootGuide != null)
                      Expanded(
                        child: TurnTile(
                          label: "FOOT GUIDE",
                          icon: widget.showFootGuide
                              ? Icons.directions_walk
                              : Icons.directions_walk_outlined,
                          selected: widget.showFootGuide,
                          onTap: widget.onToggleFootGuide!,
                        ),
                      ),
                    if (widget.onToggleFootTrails != null)
                      Expanded(
                        child: TurnTile(
                          label: "FOOT TRAILS",
                          icon: widget.showFootTrails
                              ? Icons.timeline
                              : Icons.timeline_outlined,
                          selected: widget.showFootTrails,
                          onTap: widget.onToggleFootTrails!,
                        ),
                      ),
                    if (widget.onToggleDancingFeet != null)
                      Expanded(
                        child: TurnTile(
                          label: "DANCING FEET",
                          icon: widget.showDancingFeet
                              ? Icons.do_not_step
                              : Icons.do_not_step_outlined,
                          selected: widget.showDancingFeet,
                          onTap: widget.onToggleDancingFeet!,
                        ),
                      ),
                  ],
                ),
              if (widget.onToggleAssistTick != null ||
                  widget.onToggleMeasureLines != null ||
                  widget.onToggleArcadeQuant != null)
                Row(
                  spacing: 8,
                  children: [
                    if (widget.onToggleAssistTick != null)
                      Expanded(
                        child: TurnTile(
                          label: "ASSIST TICK",
                          icon: widget.assistTickOn
                              ? Icons.volume_up
                              : Icons.volume_off_outlined,
                          selected: widget.assistTickOn,
                          onTap: widget.onToggleAssistTick!,
                        ),
                      ),
                    if (widget.onToggleMeasureLines != null)
                      Expanded(
                        child: TurnTile(
                          label: "MEASURES",
                          icon: widget.showMeasureLines
                              ? Icons.straighten
                              : Icons.straighten_outlined,
                          selected: widget.showMeasureLines,
                          onTap: widget.onToggleMeasureLines!,
                        ),
                      ),
                    if (widget.onToggleArcadeQuant != null)
                      Expanded(
                        child: TurnTile(
                          label: "ARCADE NOTES",
                          icon: widget.arcadeQuantOn
                              ? Icons.music_note
                              : Icons.music_note_outlined,
                          selected: widget.arcadeQuantOn,
                          onTap: widget.onToggleArcadeQuant!,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      // ARCADE SYNC: the cabinet timing simulation. The master toggle always
      // shows; its two dials appear only while it's engaged, so the shade stays
      // uncluttered for the common case and the offsets can't be dialled into a
      // mode that ignores them. Sits under the playback aids because engaging it
      // drives the assist tick (an AUDIO OFFSET is inaudible without it).
      ShadeSection(
        content: Column(
          children: [
            ArcadeSyncHeader(
              key: arcadeSyncTileKey,
              on: _arcadeSyncOn,
              // The song's sync shows whether the mode is engaged or not — it's
              // a property of the song, and seeing it is often the reason to
              // turn ARCADE SYNC on in the first place.
              summary: _arcadeSyncSummary,
              // Tracks the EFFECTIVE sync, so dialling a bias back toward zero
              // visibly drains the colour out of the label — the feedback that
              // tells you when you've corrected it.
              summaryAccent: _syncAccent(context),
              onTap: _toggleArcadeSync,
            ),
            if (_arcadeSyncOn) ...[
              const SizedBox(height: 8),
              // The two dials split the row evenly, reading as the pair they are
              // (and matching the TURN tiles' split-row rhythm) rather than two
              // stacked full-width bars.
              Row(
                children: [
                  Expanded(
                    child: TimingOffsetChip(
                      key: visualOffsetChipKey,
                      label: "VISUAL",
                      icon: Icons.visibility_outlined,
                      value: _visualOffset,
                      valueLabel: _visualOffsetLabel(_visualOffset),
                      onTap: () => _resetTimingOffset(visual: true),
                      onDrag: (dx) => _onTimingOffsetDrag(visual: true, dx: dx),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TimingOffsetChip(
                      key: audioOffsetChipKey,
                      label: "AUDIO",
                      icon: Icons.graphic_eq,
                      value: _audioOffsetMs,
                      valueLabel: _audioOffsetLabel(_audioOffsetMs),
                      onTap: () => _resetTimingOffset(visual: false),
                      onDrag: (dx) =>
                          _onTimingOffsetDrag(visual: false, dx: dx),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _buildTransport(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(
                  child: SpeedPane(
                    label: _hispeedType ? "HI-SPEED" : "REAL SPEED",
                    value: _hispeedType ? fmtXMod(_rate) : "$_scrollSpeed",
                    // The min–core–max scroll-speed trio (cabinet
                    // num_min/num_core/num_max) under both types — HI-SPEED's
                    // dial is a bare multiplier, so the trio is the only place
                    // the resulting read speeds appear.
                    range: _scrollSpeedLabel,
                    decLabel: _hispeedType ? "−.05" : "−10",
                    incLabel: _hispeedType ? "+.05" : "+10",
                    canDecrement: _hispeedType
                        ? _hispeedHundredths > _hispeedMin
                        : _scrollSpeed > _scrollMin,
                    canIncrement: _hispeedType
                        ? _hispeedHundredths < _hispeedMax
                        : _scrollSpeed < _scrollMax,
                    onStep: _stepSpeed,
                    onDrag: _onReadSpeedDrag,
                    onToggleType: _toggleSpeedType,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SongSpeedPane(
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
/// and the read speed it reads at (localBpm × mod). CONSTANT is intentionally
/// absent — like the cabinet, CONSTANT is a separate display-time setting that
double debugGatedVisualOffsetSeconds({
  required bool arcadeSyncOn,
  required double units,
}) =>
    arcadeSyncOn ? units * _ChartScrollerState._visualOffsetUnitSeconds : 0;

/// The same gate for the AUDIO dial, in seconds (its dial is milliseconds).
@visibleForTesting
double debugGatedAudioOffsetSeconds({
  required bool arcadeSyncOn,
  required double ms,
}) =>
    arcadeSyncOn ? ms / 1000.0 : 0;

/// The VISUAL dial unit → seconds of arrow travel. The cabinet publishes this
/// dial as a bare number, so the conversion is the preview's own calibration
/// (one unit = one 60fps frame); exposed so tests pin it rather than re-deriving.
@visibleForTesting
double visualOffsetSeconds(double units) =>
    units * _ChartScrollerState._visualOffsetUnitSeconds;

/// Formats each dial the way its chip does — they use different units, so the
/// VISUAL dial reads "+1.5" while AUDIO reads "-10ms".
@visibleForTesting
String visualOffsetLabel(double units) =>
    _ChartScrollerState._visualOffsetLabel(units);
@visibleForTesting
String audioOffsetLabel(double ms) => _ChartScrollerState._audioOffsetLabel(ms);

/// Clamps/snaps each dial to its own range: VISUAL to ±5.0 on the 0.1 grid,
/// AUDIO to ±50 whole milliseconds.
@visibleForTesting
double visualOffsetClamp(double units) =>
    _ChartScrollerState._clampVisualOffset(units);
@visibleForTesting
double audioOffsetClampMs(double ms) =>
    _ChartScrollerState._clampAudioOffsetMs(ms);

/// Builds two field painters differing ONLY in their VISUAL OFFSET (in frames)
/// and reports whether the renderer treats that as a repaint-worthy change, plus
/// the receptor-relative second each one puts the playhead at.
///
/// Exposed because the painter is private and the difference has to be isolated:
/// rebuilding the widget to change the dial also churns note/colMap identities,
/// which invalidate the painter for unrelated reasons and would make a
/// shouldRepaint assertion pass even if the offset were ignored entirely.
@visibleForTesting
({bool repaints, double neutralSecond, double offsetSecond})
    debugVisualOffsetEffect(double units) {
  final playhead = ValueNotifier<double>(1.0);
  ChartPainter painterAt(double dialUnits) => ChartPainter(
        notes: const [],
        holds: const [],
        shockNotes: const {},
        shocks: const [],
        bpmMarkers: const [],
        stopMarkers: const [],
        feet: const {},
        footPrev: const {},
        dirs: kSingleDirs,
        colMap: const [0, 1, 2, 3],
        playhead: playhead,
        pxPerSecond: 300,
        pxPerBeat: 150,
        timing: ChartTiming.empty,
        columnCount: 4,
        skin: const VectorNoteskin(),
        playing: false,
        visualOffset: dialUnits * _ChartScrollerState._visualOffsetUnitSeconds,
      );
  final neutral = painterAt(0);
  final offset = painterAt(units);
  final result = (
    repaints: offset.shouldRepaint(neutral),
    neutralSecond: neutral.second,
    offsetSecond: offset.second,
  );
  playhead.dispose();
  return result;
}
