/// Name: ChartPainter
/// Parent: ChartScroller
/// Description: Draws one frame of the scrolling note field — arrows, hold
/// bodies, shock bars, receptors, tempo/stop markers and the foot guide.
/// Everything it needs arrives through the constructor, so it holds no state
/// of its own; split out of chart_scroller.dart to keep the render pass
/// separate from the widget that drives it.
library;

import 'chart_models.dart';
import 'chart_timing.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// A compact seconds label for a stop's duration, e.g. "0.16s".
String _fmtDur(double s) => "${s.toStringAsFixed(2)}s";

class ChartPainter extends CustomPainter {
  ChartPainter({
    required this.notes,
    required this.holds,
    required this.shockNotes,
    required this.shocks,
    required this.bpmMarkers,
    required this.stopMarkers,
    required this.feet,
    required this.footPrev,
    required this.dirs,
    required this.colMap,
    required this.playhead,
    required this.pxPerSecond,
    required this.pxPerBeat,
    required this.timing,
    required this.columnCount,
    required this.skin,
    required this.playing,
    this.showMeasureLines = false,
    this.zoom = 1.0,
    this.constantMs,
    this.topInset = 0,
    this.visualOffset = 0,
    this.arcadeQuant = false,
  }) : super(repaint: playhead);

  /// All notes ascending by second (see [_ChartScrollerState._prepareNotes]) —
  /// sorted order is what the per-frame binary-search culling relies on.
  final List<StepNote> notes;

  /// Just the holds/rolls, same order — a hold's body must draw while its head
  /// second is already behind the playhead, so it can't be found by
  /// binary-searching [notes] on second.
  final List<StepNote> holds;

  final Set<StepNote> shockNotes;
  final List<ShockRow> shocks;
  final List<BpmMarker> bpmMarkers;
  final List<StopMarker> stopMarkers;
  final Map<StepNote, Foot> feet;

  /// Previous same-foot note per footed note (precomputed once per chart), so
  /// foot paths draw from the visible window alone.
  final Map<StepNote, StepNote> footPrev;

  final List<NoteDir> dirs;

  // DDR TURN permutation: `colMap[originalCol]` is the column the note is drawn
  // in (and the glyph orientation it takes). Receptors/lanes stay in their fixed
  // positions, so a turn only moves the notes. Identity when TURN is OFF.
  final List<int> colMap;

  /// The moving playhead. Registered as this painter's repaint listenable, so
  /// per-frame motion repaints the canvas without a widget rebuild; everything
  /// else about the painter is per-build configuration.
  final ValueListenable<double> playhead;

  /// VISUAL OFFSET in seconds (cabinet convention: positive = EARLIER, so the
  /// arrows reach the receptor sooner; negative = later). Added to the playhead
  /// rather than subtracted from every note: advancing the *reference* second by
  /// dt is exactly equivalent to pulling every note dt closer to the line, and
  /// doing it here means the whole renderer inherits it from one place — note Ys
  /// ([yFor]), the visible-window cull ([maxT]), stop expansion, the beat-locked
  /// mapping, and the CONSTANT display window ([_constantAlpha]) all key off
  /// [second]. Zero leaves the pipeline bit-for-bit unchanged.
  ///
  /// Only the rendered field shifts; the transport's own position readout keeps
  /// using the true playhead, so the offset never desyncs the seek bar or the
  /// reported time from the audio.
  final double visualOffset;

  double get second => playhead.value + visualOffset;

  final double pxPerSecond;

  // Beat-locked scroll: [pxPerBeat] is the pixels-per-beat spacing and [timing]
  // maps a note's second to its beat. When [timing] is empty the painter falls
  // back to [pxPerSecond] constant-time scrolling (charts with no BPM data).
  final double pxPerBeat;
  final ChartTiming timing;

  final int columnCount;
  final Noteskin skin;
  final bool playing;

  /// Rule the field into numbered 4-beat measures. Needs the beat axis, so it
  /// does nothing on charts with no BPM data.
  final bool showMeasureLines;

  /// Mirrors [QuantColors.arcadeMode]. The skins read that global directly, so
  /// the painter never uses this value — it exists purely so [shouldRepaint]
  /// can see a palette change. Without it the field only recolours once
  /// something else (the playhead ticking) forces a repaint.
  final bool arcadeQuant;

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
  // (in real seconds) from the line, then FADES IN over the leading slice of
  // the window and travels the rest of the way solid. Null = NORMAL (arrows
  // always visible). The window is keyed on real seconds-to-receptor, not beat
  // distance, so its span in pixels/beats stretches and compresses with the
  // local tempo, exactly as in-game. See [_constantAlpha].
  final double? constantMs;

  // Top safe-area inset (status bar / notch). The field is full-bleed, so the
  // receptor line is pushed down by this much to clear the system chrome.
  final double topInset;

  // Leading slice of the CONSTANT window over which an arrow ramps from
  // invisible to solid. The arcade fades arrows in as they enter their display
  // window (RemyWiki/DDR wiki both describe CONSTANT as arrows that "fade in as
  // they reach the Step Zone", and the modifier's origin — 鳳 as A3's
  // BABY-LON'S GALAXY encore — visibly fades); the exact curve isn't published,
  // so this fraction is eyeballed from footage and tunable. Unlike HIDDEN/
  // SUDDEN, which are drawn lane covers, CONSTANT is per-arrow alpha.
  static const double _constantFadeFrac = 0.2;

  // Opacity of the note at chart-second [t] under the CONSTANT modifier: 1 when
  // CONSTANT is off, the note is at/past the receptor, or it's solidly inside
  // its display window; 0 while it's still beyond the window; ramping linearly
  // across the first [_constantFadeFrac] of the window in between. Driven by
  // real seconds-to-receptor (`t - second`), so the window is a fixed
  // wall-clock time no matter the tempo. For a held note whose head has already
  // reached the line, [t] should be the head's own second (<= playhead),
  // yielding 1.
  double _constantAlpha(double t) {
    final c = constantMs;
    if (c == null) return 1;
    final timeToReceptor = t - second;
    if (timeToReceptor <= 0) return 1; // at or past the line
    final window = c / 1000.0;
    if (timeToReceptor >= window) return 0; // beyond the display window
    // Seconds since the note entered its window, as a share of the fade band.
    final sinceAppear = window - timeToReceptor;
    return (sinceAppear / (window * _constantFadeFrac)).clamp(0.0, 1.0);
  }

  // Draws [draw] composited at [alpha] via a save layer over [bounds]. Full
  // opacity skips the layer entirely, so only the handful of notes inside the
  // CONSTANT fade band pay for compositing.
  void _fadeLayer(
      Canvas canvas, double alpha, Rect bounds, void Function() draw) {
    if (alpha >= 1) {
      draw();
      return;
    }
    canvas.saveLayer(bounds, Paint()..color = Colors.white.withValues(alpha: alpha));
    draw();
    canvas.restore();
  }

  // Receptors sit near the TOP; arrows scroll up into them. Tap/hold-head
  // arrows draw ON TOP OF (z-above) the receptors so an arrow reaching the
  // line covers it, but hold bodies/tails draw BEHIND the receptor (matching
  // DDR/StepMania) so a sustain passing through or ending at the line slides
  // under the receptor frame instead of covering it.
  // [receptorBase] is the gap below the (inset-adjusted) top edge. Read by
  // the state to derive the field's travel distance for the speed law.
  static const double receptorBase = 56;
  double get _receptorTop => receptorBase + topInset;

  // Impact flash lifetime. DDR's is 120ms; the preview has no input or
  // judgement, so every arrival draws the clean-hit flash rather than one of
  // the per-judgement variants.
  static const double _flashSeconds = 0.12;

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

    // Receptors only pulse while playing; static (dim, steady) when paused. The
    // pulse rides the beat (freezing on stops, quickening with the tempo) when
    // beat-locked, else falls back to a fixed half-second cadence. Use a
    // triangle wave (peak on the beat, easing symmetrically to the trough) so
    // the glow never snaps back discontinuously — a sawtooth flashed each beat.
    final phase = (beatLocked ? currentBeat : second * 2) % 1.0;
    final glow = playing ? 1.0 - (2.0 * phase - 1.0).abs() : 0.0;

    // Clip only the far top of the field, so a note sitting ON the receptor
    // draws in full (z-above it) while notes that have scrolled well past are
    // hidden. Sized for the impact flash rather than the note: the flash shares
    // the receptor's centre but overhangs it (see [noteFlashCurve]), and a clip
    // cut to the arrow alone shears its top off. Never rises above the safe
    // area though — the field must not draw under the status bar / notch, so on
    // wide fields the flash is cut there rather than the chrome being overrun.
    final flashTop =
        _receptorTop - arrowSize * noteFlashPeakScale / 2 - arrowSize * 0.12;
    final clipTop = flashTop < topInset ? topInset : flashTop;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, clipTop, size.width, size.height - clipTop));

    // 0a) Measure rules, under everything else: they are scaffolding for reading
    // position, not part of the field.
    if (showMeasureLines && beatLocked) {
      _paintMeasureLines(canvas, size, yFor, currentBeat,
          currentBeat + (size.height - _receptorTop) / pxPerBeat,
          labels: false);
    }

    // 0) Timing markers (BPM changes and stops), base layer: lines/bands drawn
    // first inside the clip so notes, holds and foot paths render on top. Their
    // pill labels come later (after the notes) so they stay legible.
    _paintTimingMarkers(canvas, size, yFor, maxT, beatLocked, expandStops,
        labels: false);

    // 1) Freeze/hold bodies (behind the receptor and arrowheads). While a hold
    // is being held its head has reached the receptor, so clamp the head to
    // the line; the body then shrinks upward into it and vanishes at the tail.
    // Walks the (much smaller) holds list and stops at the window's far edge.
    for (final n in holds) {
      if (n.second > maxT) break; // sorted: nothing later can be visible
      final endS = n.endSecond ?? n.second;
      if (endS < second) continue;
      // A freeze appears as one piece under CONSTANT, keyed on its head's second
      // — the whole body fades in together as the head enters its window.
      final holdAlpha = _constantAlpha(n.second);
      if (holdAlpha <= 0) continue;
      final headY =
          n.second >= second ? yFor(n.second) : _receptorTop.toDouble();
      final col = turned(n.col);
      final holdX = laneCenterX(col);
      final tailY = yFor(endS);
      _fadeLayer(
          canvas,
          holdAlpha,
          Rect.fromLTRB(holdX - arrowSize, headY - arrowSize,
              holdX + arrowSize, tailY + arrowSize), () {
        skin.paintHoldBody(canvas, holdX, headY, tailY, arrowSize, dirs[col],
            n.type == StepType.roll);
        skin.paintHoldTail(
            canvas, holdX, tailY, arrowSize, dirs[col], n.type == StepType.roll);
      });
    }

    // Age (in seconds) of the most recent arrival in each drawn lane, for the
    // impact effects below. Notes are sorted, so the arrivals still in effect
    // are the slice ending at the playhead — walk back from a binary search
    // until one is older than the longest effect. Nothing is retained between
    // frames; every effect is a function of (playhead - note.second). Only
    // while playing: scrubbing sweeps arrivals past the playhead at arbitrary
    // speed (and backwards), which would strobe the whole field.
    final arrivals = <int, double>{};
    if (playing) {
      const longest =
          _flashSeconds > receptorRecoilSeconds ? _flashSeconds : receptorRecoilSeconds;
      for (int i = _lowerBoundBySecond(notes, second) - 1; i >= 0; i--) {
        final n = notes[i];
        final age = second - n.second;
        if (age >= longest) break; // sorted: everything earlier is older
        if (n.type == StepType.mine) continue; // mines aren't "hit"
        arrivals.putIfAbsent(turned(n.col), () => age); // newest wins the lane
      }
    }

    // 1.2) Receptors, drawn on top of hold bodies/tails but under taps and
    // held hold-heads (below) — a sustain slides under the receptor frame as
    // it passes through or ends at the line, matching DDR/StepMania, while an
    // arrow landing on the line still covers its receptacle.
    //
    // A receptor recoils when a note lands on it: it snaps in and springs back.
    // DDR drives this off ghost taps (stepping with no note there) rather than
    // arrivals — there is no input here, so it hangs off the note instead.
    for (int c = 0; c < columnCount; c++) {
      final age = arrivals[c];
      final recoil = age == null
          ? 1.0
          : receptorRecoilCurve(age / receptorRecoilSeconds);
      skin.paintReceptor(canvas, laneCenterX(c), _receptorTop,
          arrowSize * recoil, dirs[c], glow * 0.9);
    }

    // 1.5) Foot-flow paths: connect each note to the previous note struck by the
    // same foot, so the chart's left/right movement reads as two flowing lines.
    if (feet.isNotEmpty) {
      _paintFootPaths(canvas, laneCenterX, yFor, arrowSize, second, maxT);
    }

    // 2) Shock rows: a light-blue arrow in every lit lane linked by electricity,
    // spanning the whole row (also vanishes once hit).
    for (final s in shocks) {
      if (s.second > maxT) break; // sorted by second
      if (s.second < second) continue;
      final shockAlpha = _constantAlpha(s.second); // fades in under CONSTANT
      if (shockAlpha <= 0) continue;
      final y = yFor(s.second);
      final lanes = [
        for (final c in s.cols) (laneCenterX(turned(c)), dirs[turned(c)]),
      ];
      _fadeLayer(canvas, shockAlpha,
          Rect.fromLTRB(0, y - arrowSize, size.width, y + arrowSize), () {
        skin.paintShock(canvas, lanes, y, arrowSize);
      });
    }

    // 3) Taps, mines (non-shock), and hold heads — drawn last so they sit above
    // the receptors. A held freeze keeps its head pinned to the receptor line.
    // Two culled sources replace the old full-chart walk: active holds (head
    // already behind the playhead, pinned to the receptor) from the holds list,
    // then the binary-searched [second, maxT] slice of the sorted note list —
    // the same set, and the same sorted draw order, the full walk produced.
    void drawHead(StepNote n, bool held) {
      // A held head sits on the receptor, so treat it as fully arrived rather
      // than re-fading it; otherwise CONSTANT fades it in over its window.
      final noteAlpha = held ? 1.0 : _constantAlpha(n.second);
      if (noteAlpha <= 0) return;
      final col = turned(n.col);
      final x = laneCenterX(col);
      final y = held ? _receptorTop.toDouble() : yFor(n.second);
      if (n.type == StepType.mine && shockNotes.contains(n)) {
        return; // drawn in the shock pass
      }
      _fadeLayer(
          canvas,
          noteAlpha,
          Rect.fromLTRB(
              x - arrowSize, y - arrowSize, x + arrowSize, y + arrowSize), () {
        if (n.type == StepType.mine) {
          skin.paintMine(canvas, x, y, arrowSize);
        } else {
          skin.paintArrow(canvas, x, y, arrowSize, dirs[col], n.beat);
          final foot = feet[n];
          if (foot != null) _paintFootBadge(canvas, x, y, arrowSize, foot);
        }
      });
    }

    for (final n in holds) {
      if (n.second >= second) break; // at/after the playhead: scrolls normally
      if ((n.endSecond ?? n.second) < second) continue;
      drawHead(n, true);
    }
    for (int i = _lowerBoundBySecond(notes, second);
        i < notes.length;
        i++) {
      final n = notes[i];
      if (n.second > maxT) break;
      drawHead(n, false);
    }

    // 3.5) Impact flashes for notes that just reached the line, one per lane
    // (matching DDR's one-live-flash-per-column).
    for (final MapEntry(key: col, value: age) in arrivals.entries) {
      if (age >= _flashSeconds) continue; // recoil outlasts the flash
      skin.paintNoteFlash(canvas, laneCenterX(col), _receptorTop, arrowSize,
          dirs[col], age / _flashSeconds);
    }

    // 4) Timing-marker labels, top layer: drawn last so the STOP/BPM pills sit
    // above the note stream instead of being buried under passing arrows.
    _paintTimingMarkers(canvas, size, yFor, maxT, beatLocked, expandStops,
        labels: true);
    if (showMeasureLines && beatLocked) {
      _paintMeasureLines(canvas, size, yFor, currentBeat,
          currentBeat + (size.height - _receptorTop) / pxPerBeat,
          labels: true);
    }

    canvas.restore(); // end note clip
  }

  // A small L/R parity badge centred on the arrow, in the shared parity palette
  // so an arrow's badge, its flow path and the pad's foot all read as one foot.
  static const Color _leftFootColor = kLeftFootColor;
  static const Color _rightFootColor = kRightFootColor;

  // First index in [notes] (ascending by second) whose second is >= [t].
  static int _lowerBoundBySecond(List<StepNote> notes, double t) {
    int lo = 0, hi = notes.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (notes[mid].second < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  // Reused stroke paints for the two foot-path polylines; only the width (which
  // tracks the zoomed arrow size) is touched per frame.
  static final Paint _leftFootPathPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = _leftFootColor.withValues(alpha: 0.42);
  static final Paint _rightFootPathPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = _rightFootColor.withValues(alpha: 0.42);

  // Connect each note to the previous note struck by the same foot, drawing two
  // flowing polylines (one per foot) so the chart's movement pattern reads at a
  // glance. Drawn behind the arrowheads. Held notes anchor to the receptor while
  // active, matching where their head is actually drawn.
  //
  // The same-foot chaining is precomputed per chart ([footPrev]), so this only
  // touches the visible window: every visible note draws its incoming link, the
  // active holds draw theirs (their heads are pinned on the receptor), and the
  // first note per foot beyond the window closes the outgoing link — exactly
  // the segments the old whole-chart walk drew with `visible(prev)||visible(n)`.
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

    bool heldNow(StepNote n) =>
        n.isHold && n.second < second && (n.endSecond ?? n.second) >= second;
    bool visible(StepNote n) =>
        heldNow(n) || (n.second >= second && n.second <= maxT);

    final leftPaint = _leftFootPathPaint..strokeWidth = arrowSize * 0.10;
    final rightPaint = _rightFootPathPaint..strokeWidth = arrowSize * 0.10;

    void drawLink(StepNote prev, StepNote n, Foot foot) => canvas.drawLine(
          anchor(prev),
          anchor(n),
          foot == Foot.left ? leftPaint : rightPaint,
        );

    // Links into the receptor-pinned heads of active holds (their own seconds
    // sit behind the playhead, so the window scan below won't reach them).
    for (final h in holds) {
      if (h.second >= second) break;
      if (!heldNow(h)) continue;
      final foot = feet[h];
      final prev = footPrev[h];
      if (foot != null && prev != null) drawLink(prev, h, foot);
    }

    // Visible-window scan; past the far edge, only the first same-foot note
    // still owes a link back to a visible predecessor, then we're done.
    bool leftClosed = false, rightClosed = false;
    for (int i = _lowerBoundBySecond(notes, second); i < notes.length; i++) {
      final n = notes[i];
      final foot = feet[n];
      if (foot == null) continue; // mines/shocks never take a foot
      if (n.second > maxT) {
        final closed = foot == Foot.left ? leftClosed : rightClosed;
        if (!closed) {
          final prev = footPrev[n];
          if (prev != null && visible(prev)) drawLink(prev, n, foot);
          if (foot == Foot.left) {
            leftClosed = true;
          } else {
            rightClosed = true;
          }
        }
        if (leftClosed && rightClosed) break;
        continue;
      }
      final prev = footPrev[n];
      if (prev != null) drawLink(prev, n, foot);
    }
  }

  // Colours for timing markers: stops read as a warm caution band, BPM changes
  // as a cool line, so the two never get confused with the arrow palette.
  static const Color _stopColor = Color(0xFFFFB454);
  static const Color _bpmColor = Color(0xFF8AB4FF);

  // Reused marker paints (fixed colours/widths — no reason to allocate per
  // marker per frame).
  static final Paint _stopLinePaint = Paint()
    ..color = _stopColor.withValues(alpha: 0.85)
    ..strokeWidth = 2.5;
  static final Paint _stopBandPaint = Paint()
    ..color = _stopColor.withValues(alpha: 0.12);
  static final Paint _stopEdgePaint = Paint()
    ..color = _stopColor.withValues(alpha: 0.7)
    ..strokeWidth = 1.5;
  static final Paint _bpmLinePaint = Paint()
    ..color = _bpmColor.withValues(alpha: 0.75)
    ..strokeWidth = 1.5;
  static final Paint _labelPillPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.55);

  static const Color _measureColor = Color(0xFF8FA3B8);
  static final Paint _measureLinePaint = Paint()
    ..color = _measureColor.withValues(alpha: 0.22)
    ..strokeWidth = 1;

  // Rule the field every 4 beats and number each measure at the left edge, the
  // way a stepchart editor does, so a spot in the chart can be named. Positions
  // go through [yFor] like everything else, so the rules ride BPM changes and
  // stops instead of being a fixed pixel grid. Measures are numbered from 1 at
  // beat 0 (editor convention).
  //
  // Two z-layers, like [_paintTimingMarkers]: the rules are the base layer
  // ([labels] = false) so arrows scroll over them, the number pills the top
  // layer so a stream of notes can't bury them.
  void _paintMeasureLines(Canvas canvas, Size size, double Function(double) yFor,
      double currentBeat, double maxBeat, {required bool labels}) {
    var m = (currentBeat / 4).floor();
    if (m < 0) m = 0;
    // Zoomed out the rules crowd together, so number only every fourth one and
    // let the rest read as plain ruling.
    final labelEvery = pxPerBeat * 4 < 46 ? 4 : 1;
    for (; m * 4 <= maxBeat; m++) {
      final y = yFor(timing.secondAt(m * 4.0));
      if (!labels) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), _measureLinePaint);
        continue;
      }
      if (m % labelEvery != 0) continue;
      _paintMarkerLabel(canvas, size, y, "${m + 1}", _measureColor,
          alignLeft: true);
    }
  }

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
              canvas, size, y, "STOP ${_fmtDur(s.dur)}", _stopColor);
        } else {
          canvas.drawLine(
            Offset(0, y),
            Offset(size.width, y),
            _stopLinePaint,
          );
        }
        continue;
      }
      final yTop = yFor(s.second);
      if (labels) {
        _paintMarkerLabel(canvas, size, yTop, "STOP", _stopColor);
        continue;
      }
      final yBot = yFor(endSec);
      final band = Rect.fromLTRB(0, yBot, size.width, yTop);
      canvas.drawRect(band, _stopBandPaint);
      // Edges of the band, brighter, so even a near-instant stop stays visible.
      canvas.drawLine(Offset(0, yTop), Offset(size.width, yTop), _stopEdgePaint);
      canvas.drawLine(Offset(0, yBot), Offset(size.width, yBot), _stopEdgePaint);
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
          _bpmLinePaint,
        );
      }
    }
  }

  // Laid-out TextPainters are cached across frames — text shaping is far too
  // expensive to redo per marker/badge per frame. Keys carry everything the
  // glyphs depend on; the caps keep a long session (many charts, zoom levels)
  // from accumulating stale entries.
  static final Map<String, TextPainter> _labelTpCache = {};
  static final Map<int, TextPainter> _footTpCache = {};

  static TextPainter _labelTp(String text, Color color) {
    if (_labelTpCache.length > 64) _labelTpCache.clear();
    return _labelTpCache.putIfAbsent("${color.toARGB32()}|$text", () {
      return TextPainter(
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
    });
  }

  // A small pill label pinned to a marker line's right edge ([alignLeft] puts it
  // on the left, for measure numbers), centred on the line so it runs through
  // the pill.
  void _paintMarkerLabel(
    Canvas canvas,
    Size size,
    double y,
    String text,
    Color color, {
    bool alignLeft = false,
  }) {
    final tp = _labelTp(text, color);
    const padX = 5.0;
    const padY = 3.0;
    const margin = 6.0;
    final boxW = tp.width + padX * 2;
    final boxH = tp.height + padY * 2;
    final left = alignLeft ? margin : size.width - boxW - margin;
    final top = y - boxH / 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, boxW, boxH),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, _labelPillPaint);
    tp.paint(canvas, Offset(left + padX, top + padY));
  }

  static final Paint _footBadgeBgPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.55);

  void _paintFootBadge(
      Canvas canvas, double x, double y, double arrowSize, Foot foot) {
    final isLeft = foot == Foot.left;
    final r = arrowSize * 0.24;
    canvas.drawCircle(Offset(x, y), r, _footBadgeBgPaint);
    // Font size quantised to quarter-pixels for the cache key: visually exact
    // enough, and pinch-zoom then reuses a bounded set of layouts.
    final sizeKey = (arrowSize * 0.34 * 4).round();
    if (_footTpCache.length > 64) _footTpCache.clear();
    final tp = _footTpCache.putIfAbsent((sizeKey << 1) | (isLeft ? 1 : 0), () {
      return TextPainter(
        text: TextSpan(
          text: isLeft ? "L" : "R",
          style: TextStyle(
            color: isLeft ? _leftFootColor : _rightFootColor,
            fontSize: sizeKey / 4.0,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  // Frame-static paints/shaders, cached across paints (the shaders only depend
  // on the field size, which changes on rotation/resize, not per frame).
  static final Paint _bgPaint = Paint();
  static Size _bgPaintSize = Size.zero;
  static final Paint _receptorLinePaint = Paint();
  static double _receptorLineWidth = -1;
  static final Paint _laneDividerPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.04)
    ..strokeWidth = 1;

  void _paintBackground(Canvas canvas, Size size) {
    // Vertical stage gradient: darker at the bottom, lifting toward the
    // receptors so incoming notes read clearly.
    if (_bgPaintSize != size) {
      _bgPaint.shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF11151C),
          Color(0xFF080A0E),
        ],
      ).createShader(Offset.zero & size);
      _bgPaintSize = size;
    }
    canvas.drawRect(Offset.zero & size, _bgPaint);
  }

  void _paintLanes(Canvas canvas, Size size, double fieldLeft,
      double laneStride, double receptorY) {
    // Subtle lane dividers, tracking the (zoom-scaled) field so they sit between
    // the lanes rather than drifting away from the arrows when zoomed out.
    for (int c = 1; c < columnCount; c++) {
      final x = fieldLeft + laneStride * c;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _laneDividerPaint);
    }
    // Receptor line highlight.
    if (_receptorLineWidth != size.width) {
      _receptorLinePaint.shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 1));
      _receptorLineWidth = size.width;
    }
    canvas.drawRect(
        Rect.fromLTWH(0, receptorY - 0.5, size.width, 1), _receptorLinePaint);
  }

  @override
  bool shouldRepaint(ChartPainter old) =>
      old.pxPerSecond != pxPerSecond ||
      old.pxPerBeat != pxPerBeat ||
      old.timing != timing ||
      old.notes != notes ||
      old.holds != holds ||
      old.bpmMarkers != bpmMarkers ||
      old.stopMarkers != stopMarkers ||
      old.feet != feet ||
      old.footPrev != footPrev ||
      old.columnCount != columnCount ||
      !listEquals(old.colMap, colMap) ||
      old.skin != skin ||
      old.playing != playing ||
      old.showMeasureLines != showMeasureLines ||
      old.zoom != zoom ||
      old.constantMs != constantMs ||
      old.topInset != topInset ||
      old.arcadeQuant != arcadeQuant ||
      // Without this the field wouldn't move while dialling VISUAL OFFSET
      // paused: the playhead notifier hasn't changed, so nothing else here
      // would report the repaint.
      old.visualOffset != visualOffset;
}
