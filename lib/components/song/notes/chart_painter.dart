/// Name: ChartPainter
/// Parent: ChartScroller
/// Description: Draws one frame of the scrolling note field — arrows, hold
/// bodies, shock bars, receptors, tempo/stop markers and the foot guide.
/// Everything it needs arrives through the constructor, so it holds no state
/// of its own; split out of chart_scroller.dart to keep the render pass
/// separate from the widget that drives it.
library;

import 'dart:math' as math;

import 'chart_models.dart';
import 'chart_timing.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// A compact seconds label for a stop's duration, e.g. "0.16s".
String _fmtDur(double s) => "${s.toStringAsFixed(2)}s";

/// DDR's GUIDELINE option: beat lines through the arrows' centres, or along
/// their leading edges.
enum Guideline { off, center, border }

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
    this.paintBackground = true,
    this.guideline = Guideline.off,
    this.timeSignatures = const [],
    this.zoom = 1.0,
    this.constantMs,
    this.topInset = 0,
    this.visualOffset = 0,
    this.arcadeQuant = false,
    this.focus = const {},
    this.highlights = const [],
    this.highlightIcon,
    this.section,
    this.sectionTail,
  }) : super(repaint: playhead);

  /// The snippet's (first, last) row seconds, banded in [kSectionColor].
  final (double, double)? section;

  /// End of the selected notes, including hold tails, for the A–B band.
  final double? sectionTail;

  /// Pattern occurrences to mark, (first, last) row seconds sorted by first,
  /// each banded across the field with [highlightIcon] at its start.
  final List<(double, double)> highlights;
  final IconData? highlightIcon;

  /// Notes under review (the footing editor's current moment). When set, they
  /// glow and every other note dims.
  final Set<StepNote> focus;

  double _focusAlpha(StepNote n) =>
      focus.isEmpty || focus.contains(n) ? 1.0 : 0.25;

  /// All notes ascending by second — sorted order is what the per-frame
  /// binary-search culling relies on.
  final List<StepNote> notes;

  /// Just the holds/rolls, same order. A hold's body draws while its head second
  /// is already behind the playhead, so it can't be found by binary-searching
  /// [notes].
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

  /// VISUAL OFFSET in seconds (cabinet convention: positive = EARLIER). Added to
  /// the playhead rather than subtracted from every note — advancing the
  /// reference second is equivalent, and everything downstream (note Ys, the
  /// cull window, stop expansion, CONSTANT) already keys off [second].
  ///
  /// Only the rendered field shifts; the transport's readout keeps the true
  /// playhead, so the offset never desyncs the seek bar from the audio.
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

  /// Off when something behind the field (the pad dancer) paints its own.
  final bool paintBackground;

  /// Needs the beat axis too.
  final Guideline guideline;

  /// Bar lengths for the measure rules and the guideline; empty = 4/4.
  final List<TimeSignature> timeSignatures;

  /// Mirrors [QuantColors.arcadeMode]. The skins read that global for the arrow
  /// colours; the painter uses this to pick the freeze head (DDR PALETTE draws
  /// the freeze's own head, otherwise it is a quantised tap) and so
  /// [shouldRepaint] sees a palette change. Without it the field only recolours
  /// once something else (the playhead ticking) forces a repaint.
  final bool arcadeQuant;

  // Pinch-to-zoom, applied to the horizontal geometry (arrow size and lane
  // spacing) so it shrinks arrows in step with the vertical compression already
  // in [pxPerBeat]/[pxPerSecond]. The result is a uniform "map zoom" that fits
  // more chart on screen instead of just piling the notes together.
  final double zoom;

  // DDR CONSTANT modifier: when non-null, an arrow fades in around this many
  // milliseconds of WALL-CLOCK time before the receptor, regardless of BPM or
  // read speed. Null = NORMAL. Keyed on real seconds-to-receptor, so the
  // window's span in beats stretches with the local tempo. See [constantAlpha].
  final double? constantMs;

  // Top safe-area inset (status bar / notch). The field is full-bleed, so the
  // receptor line is pushed down by this much to clear the system chrome.
  final double topInset;

  // The cabinet's CONSTANT fade is a fixed 200ms linear ramp centred on the
  // display time, whatever that is: an arrow starts appearing 100ms before its
  // window opens and is solid 100ms after. Unlike HIDDEN/SUDDEN, which are lane
  // covers, CONSTANT is per-arrow alpha.
  static const double _constantFadeHalfSeconds = 0.1;

  // Opacity under a CONSTANT of [constantMs] for a note [timeToReceptor]
  // seconds from the receptor.
  static double constantAlpha(double constantMs, double timeToReceptor) {
    final fadeEnd = constantMs / 1000.0 - _constantFadeHalfSeconds;
    final sinceFadeEnd = timeToReceptor - fadeEnd;
    if (sinceFadeEnd <= 0) return 1;
    return (1 - sinceFadeEnd / (2 * _constantFadeHalfSeconds)).clamp(0.0, 1.0);
  }

  // Opacity of the note at chart-second [t]. For a held note, pass the head's
  // own second (<= playhead), yielding 1.
  double _constantAlpha(double t) {
    final c = constantMs;
    return c == null ? 1 : constantAlpha(c, t - second);
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
    canvas.saveLayer(
        bounds, Paint()..color = Colors.white.withValues(alpha: alpha));
    draw();
    canvas.restore();
  }

  // Receptors sit near the TOP; arrows scroll up into them. Taps and hold heads
  // draw z-above the receptors so an arrow reaching the line covers it, while
  // hold bodies/tails draw behind (matching DDR/StepMania) so a sustain slides
  // under the frame. [receptorBase] is the gap below the inset-adjusted top
  // edge, read by the state to derive travel distance for the speed law.
  static const double receptorBase = 56;
  double get _receptorTop => receptorBase + topInset;

  // The field is laid out in the cabinet's proportions rather than filling the
  // screen. The cabinet's play field in arrow heights: Arrows are one lane wide with no
  // gap between lanes, and the screen's bottom edge sits 603/96 arrow heights
  // below the receptor's centre line (one beat is one arrow height at x1).
  static const double cabinetTravelArrows = 603 / 96;

  // Arrow (and lane) size that fits the cabinet's proportions into a field of
  // [size]: as wide as the lanes allow, unless the cabinet's travel below the
  // receptor wouldn't then fit on screen.
  static double arcadeArrowSize(Size size, int columns, double topInset) =>
      math.max(
          0,
          math.min(size.width / columns,
              (size.height - receptorBase - topInset) / cabinetTravelArrows));

  // Impact flash lifetime. DDR's is 120ms; the preview has no input or
  // judgement, so every arrival draws the clean-hit flash rather than one of
  // the per-judgement variants.
  static const double _flashSeconds = 0.12;

  // A pressed receptor: 88 of its 96 px.
  static const double _heldReceptorScale = 88 / 96;

  @override
  void paint(Canvas canvas, Size size) {
    if (paintBackground) _paintBackground(canvas, size);
    // The cabinet's screen ends where its bottom edge falls; arrows emerge from
    // there rather than from the bottom of a taller phone.
    final edge = _receptorTop +
        arcadeArrowSize(size, columnCount, topInset) * cabinetTravelArrows;
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, edge));

    final (
      :fieldLeft,
      :laneStride,
      :arrowSize,
      :laneCenterX,
      :beatLocked,
      :currentBeat,
      :expandStops,
      :yFor,
    ) = _geometry(size);

    // TURN modifier: a note originally in column `c` is drawn in `turned(c)`,
    // taking that panel's glyph orientation. Bounds-guarded so a mismatched map
    // (e.g. mode/width change mid-frame) falls back to the note's own column.
    int turned(int c) => (c >= 0 && c < colMap.length) ? colMap[c] : c;

    _paintLanes(canvas, size, fieldLeft, laneStride, _receptorTop);

    // Visible window's far edge, in seconds. Notes draw on-screen until they
    // align with the receptor, then disappear immediately. Holds are the
    // exception: a held head stays pinned to the receptor while the body drains.
    final double maxT = beatLocked
        ? timing.secondAt(
                currentBeat + (size.height - _receptorTop) / pxPerBeat) +
            1
        : second + ((size.height - _receptorTop) / pxPerSecond) + 1;

    // DDR's beat flash: receptors are lit for the first quarter of each beat
    // and dim for the rest, a hard step keyed to beat position, so it holds
    // through stops and follows the tempo. Before the first beat, and whenever
    // the preview is paused, they rest halfway.
    final double glow;
    if (section != null && (second < section!.$1 || second > section!.$2)) {
      glow = 0;
    } else if (!playing || !beatLocked || currentBeat < 0) {
      glow = 0.5;
    } else {
      glow = currentBeat % 1.0 < 0.25 ? 1.0 : 0.0;
    }

    // Clip only the far top, so a note sitting ON the receptor draws in full
    // while notes well past it are hidden. Sized for the impact flash, which
    // overhangs the receptor (see [noteFlashCurve]) and would be sheared by a
    // clip cut to the arrow alone — but never above the safe area, so on wide
    // fields the flash is cut rather than the status bar overrun.
    final flashTop =
        _receptorTop - arrowSize * noteFlashPeakScale / 2 - arrowSize * 0.12;
    final clipTop = flashTop < topInset ? topInset : flashTop;
    canvas.save();
    canvas
        .clipRect(Rect.fromLTWH(0, clipTop, size.width, size.height - clipTop));

    // Marker lines sit on the guideline (BORDER moves it to the arrows' leading
    // edge) so a BPM change or stop never draws as a second line beside it.
    final lineShift = guideline == Guideline.border ? -arrowSize / 2 : 0.0;
    double markY(double t) => yFor(t) + lineShift;

    // 0a) Measure rules, under everything else: they are scaffolding for reading
    // position, not part of the field.
    if (showMeasureLines && beatLocked) {
      _paintMeasureLines(canvas, size, markY, currentBeat,
          currentBeat + (size.height - _receptorTop) / pxPerBeat,
          labels: false);
    }

    if (guideline != Guideline.off && beatLocked) {
      _paintGuideline(
          canvas,
          yFor,
          lineShift,
          currentBeat,
          currentBeat + (size.height - _receptorTop) / pxPerBeat + 1,
          fieldLeft,
          laneStride * columnCount,
          arrowSize);
    }

    // 0) Timing markers (BPM changes and stops), base layer: lines/bands drawn
    // first inside the clip so notes, holds and foot paths render on top. Their
    // pill labels come later (after the notes) so they stay legible.
    _paintTimingMarkers(canvas, size, markY, maxT, beatLocked, expandStops,
        labels: false);

    // 0b) Pattern bands, under the notes they group.
    final fieldRight = fieldLeft + laneStride * columnCount;
    for (final (from, to) in highlights) {
      if (from > maxT) break;
      if (to < second) continue;
      final band = RRect.fromLTRBR(
          fieldLeft - 4,
          yFor(from) - arrowSize * 0.6,
          fieldRight + 4,
          yFor(to) + arrowSize * 0.6,
          const Radius.circular(10));
      canvas.drawRRect(band, _highlightFillPaint);
      canvas.drawRRect(band, _highlightEdgePaint);
    }
    final bandSection =
        section == null ? null : (section!.$1, sectionTail ?? section!.$2);
    if (bandSection case (final from, final to)
        when from <= maxT && to >= second) {
      final band = RRect.fromLTRBR(
          fieldLeft - 6,
          yFor(from) - arrowSize * 0.6,
          fieldRight + 6,
          yFor(to) + arrowSize * 0.6,
          const Radius.circular(10));
      canvas.drawRRect(band, _sectionFillPaint);
      canvas.drawRRect(band, _sectionEdgePaint);
    }
    // 1) Freeze/hold bodies, behind the receptor and arrowheads. A hold being
    // held has its head clamped to the line, so the body shrinks upward into it
    // and vanishes at the tail.
    for (final n in holds) {
      if (n.second > maxT) break; // sorted: nothing later can be visible
      final endS = n.endSecond ?? n.second;
      if (endS < second) continue;
      // A freeze appears as one piece under CONSTANT, keyed on its head's second
      // — the whole body fades in together as the head enters its window.
      final holdAlpha = _constantAlpha(n.second) * _focusAlpha(n);
      if (holdAlpha <= 0) continue;
      final headY =
          n.second >= second ? yFor(n.second) : _receptorTop.toDouble();
      final col = turned(n.col);
      final holdX = laneCenterX(col);
      // Playback collapses stops, but a freeze keeps the length the stops
      // inside it give it paused, draining through them as they play.
      var tailY = yFor(endS);
      if (beatLocked && !expandStops) {
        final from = math.max(n.second, second);
        tailY += (timing.stopSecondsAt(endS) - timing.stopSecondsAt(from)) *
            pxPerSecond;
      }
      _fadeLayer(
          canvas,
          holdAlpha,
          Rect.fromLTRB(holdX - arrowSize, headY - arrowSize,
              holdX + arrowSize, tailY + arrowSize), () {
        // Nothing of a freeze shows above its head's centre: a freeze shorter
        // than the tail cap would otherwise poke the cap out around the head.
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(
            holdX - arrowSize, headY, holdX + arrowSize, tailY + arrowSize));
        skin.paintHoldBody(canvas, holdX, headY, tailY, arrowSize, dirs[col],
            n.type == StepType.roll);
        skin.paintHoldTail(
            canvas, holdX, tailY, arrowSize, dirs[col], n.type == StepType.roll);
        canvas.restore();
      });
    }

    // Age of the most recent arrival in each lane, for the impact effects below.
    // Nothing is retained between frames — every effect is a function of
    // (playhead - note.second) — so this walks back from a binary search until
    // one is older than the longest effect. Only while playing: scrubbing sweeps
    // arrivals past the playhead at arbitrary speed, strobing the whole field.
    final arrivals = <int, double>{};
    if (playing) {
      const longest = _flashSeconds > receptorRecoilSeconds
          ? _flashSeconds
          : receptorRecoilSeconds;
      for (int i = _lowerBoundBySecond(notes, second) - 1; i >= 0; i--) {
        final n = notes[i];
        final age = second - n.second;
        if (age >= longest) break; // sorted: everything earlier is older
        if (n.type == StepType.mine) continue; // mines aren't "hit"
        if (section != null &&
            (n.second < section!.$1 || n.second > section!.$2)) {
          continue;
        }
        arrivals.putIfAbsent(turned(n.col), () => age); // newest wins the lane
      }
    }

    // 1.2) Receptors, above hold bodies/tails but under taps and held heads, so
    // a sustain slides under the frame while an arrow landing on the line covers
    // it. Each recoils when a note lands — DDR drives that off ghost taps, but
    // there is no input here, so it hangs off the note instead.
    // A lane with a freeze under the playhead is held down: the receptor sits
    // pressed and lit for as long as the freeze lasts.
    final held = <int>{};
    for (final n in holds) {
      if (n.second > second) break; // sorted: nothing later has started
      if ((n.endSecond ?? n.second) >= second) held.add(turned(n.col));
    }
    for (int c = 0; c < columnCount; c++) {
      final age = arrivals[c];
      var recoil =
          age == null ? 1.0 : receptorRecoilCurve(age / receptorRecoilSeconds);
      final isHeld = held.contains(c);
      if (isHeld) recoil = math.min(recoil, _heldReceptorScale);
      skin.paintReceptor(canvas, laneCenterX(c), _receptorTop,
          arrowSize * recoil, dirs[c], isHeld ? 1.0 : glow * 0.9);
    }

    // 1.5) Foot-flow paths: connect each note to the previous note struck by the
    // same foot, so the chart's left/right movement reads as two flowing lines.
    if (feet.isNotEmpty) {
      _paintFootPaths(canvas, laneCenterX, yFor, arrowSize, second, maxT);
    }

    // 2) Shock rows: an animated bolt spanning each affected pad,
    // disappearing once it reaches the receptor.
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
        skin.paintShock(canvas, lanes, y, arrowSize, chartSecond: second);
      });
    }

    // 3) Taps, mines (non-shock) and hold heads, drawn last so they sit above
    // the receptors; a held freeze keeps its head pinned to the line. Two culled
    // sources: active holds, whose heads are already behind the playhead, then
    // the binary-searched [second, maxT] slice of the sorted note list.
    void drawHead(StepNote n, bool held) {
      // A held head sits on the receptor, so treat it as fully arrived rather
      // than re-fading it; otherwise CONSTANT fades it in over its window.
      final noteAlpha =
          (held ? 1.0 : _constantAlpha(n.second)) * _focusAlpha(n);
      if (noteAlpha <= 0) return;
      final col = turned(n.col);
      final x = laneCenterX(col);
      final y = held ? _receptorTop.toDouble() : yFor(n.second);
      if (n.type == StepType.mine && shockNotes.contains(n)) {
        return; // drawn in the shock pass
      }
      if (!playing &&
          n.type != StepType.mine &&
          section != null &&
          (n.second == section!.$1 || n.second == section!.$2)) {
        // Expand the arrow's alpha silhouette; the normal arrow drawn below
        // covers the interior, leaving a border that follows the skin's shape.
        final border = math.max(2.0, arrowSize * 0.045);
        canvas.saveLayer(
            Rect.fromCenter(
                center: Offset(x, y),
                width: arrowSize * 2,
                height: arrowSize * 2),
            Paint()
              ..colorFilter =
                  const ColorFilter.mode(kSectionColor, BlendMode.srcIn));
        for (var i = 0; i < 12; i++) {
          final angle = i * math.pi / 6;
          skin.paintArrow(canvas, x + math.cos(angle) * border,
              y + math.sin(angle) * border, arrowSize, dirs[col], n.beat);
        }
        canvas.restore();
      }
      if (section == null && focus.contains(n)) {
        canvas.drawCircle(
            Offset(x, y),
            arrowSize * 0.6,
            _focusGlowPaint
              ..maskFilter =
                  MaskFilter.blur(BlurStyle.normal, arrowSize * 0.22));
      }
      _fadeLayer(
          canvas,
          noteAlpha,
          Rect.fromLTRB(
              x - arrowSize, y - arrowSize, x + arrowSize, y + arrowSize), () {
        if (n.type == StepType.mine) {
          skin.paintMine(canvas, x, y, arrowSize);
        } else {
          if (n.isHold && arcadeQuant) {
            skin.paintHoldHead(canvas, x, y, arrowSize, dirs[col], n.beat);
          } else {
            skin.paintArrow(canvas, x, y, arrowSize, dirs[col], n.beat);
          }
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
    for (int i = _lowerBoundBySecond(notes, second); i < notes.length; i++) {
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

    // 4) Timing-marker labels and pattern badges, top layer: drawn last so they
    // sit above the note stream instead of being buried under passing arrows.
    if (highlightIcon case final icon?) {
      for (final (from, to) in highlights) {
        if (from > maxT) break;
        if (to < second) continue;
        _paintPatternBadge(canvas, fieldLeft, yFor(from), icon);
      }
    }
    _paintTimingMarkers(canvas, size, markY, maxT, beatLocked, expandStops,
        labels: true);
    if (showMeasureLines && beatLocked) {
      _paintMeasureLines(canvas, size, markY, currentBeat,
          currentBeat + (size.height - _receptorTop) / pxPerBeat,
          labels: true);
    }

    canvas.restore(); // end note clip
  }

  // Lane and scroll geometry for a field of [size] at the current playhead,
  // shared by [paint] and [noteAt] so a tap lands on exactly what was drawn.
  ({
    double fieldLeft,
    double laneStride,
    double arrowSize,
    double Function(int) laneCenterX,
    bool beatLocked,
    double currentBeat,
    bool expandStops,
    double Function(double) yFor,
  }) _geometry(Size size) {
    // Zoom pulls the lanes toward the field's centre and shrinks the arrows with
    // them, in step with the vertical spacing, so zooming out fits more chart
    // while keeping the cabinet's spacing in arrow heights.
    final arrowSize = arcadeArrowSize(size, columnCount, topInset) * zoom;
    final laneStride = arrowSize;
    final fieldLeft = (size.width - laneStride * columnCount) / 2;

    double laneCenterX(int col) =>
        fieldLeft + laneStride * col + laneStride / 2;

    // Beat-locked scroll (true DDR): a note's screen position is its beat
    // distance from the playhead's, so BPM changes speed the field up/down and
    // stops freeze it. Charts with no BPM data fall back to constant time.
    final bool beatLocked = !timing.isEmpty;
    final double currentBeat = beatLocked ? timing.beatAt(second) : 0;
    // Paused, each stop re-expands to real pixels so the halt reads as a gap you
    // can scroll through rather than the collapsed seam playback shows. This
    // deliberately shifts the layout between play and scroll.
    final bool expandStops = beatLocked && !playing;
    final double currentStop = expandStops ? timing.stopSecondsAt(second) : 0;
    double yFor(double t) {
      if (!beatLocked) return _receptorTop + (t - second) * pxPerSecond;
      var y = _receptorTop + (timing.beatAt(t) - currentBeat) * pxPerBeat;
      if (expandStops) {
        y += (timing.stopSecondsAt(t) - currentStop) * pxPerSecond;
      }
      return y;
    }

    return (
      fieldLeft: fieldLeft,
      laneStride: laneStride,
      arrowSize: arrowSize,
      laneCenterX: laneCenterX,
      beatLocked: beatLocked,
      currentBeat: currentBeat,
      expandStops: expandStops,
      yFor: yFor,
    );
  }

  /// The tappable note (not a mine, not already past the receptor) under [pos]
  /// on a field of [size], nearest first.
  StepNote? noteAt(Offset pos, Size size) {
    final g = _geometry(size);
    StepNote? best;
    double bestDist = double.infinity;
    for (int i = _lowerBoundBySecond(notes, second); i < notes.length; i++) {
      final n = notes[i];
      if (n.type == StepType.mine) continue;
      final y = g.yFor(n.second);
      if (y - g.arrowSize > size.height) break;
      final col = (n.col >= 0 && n.col < colMap.length) ? colMap[n.col] : n.col;
      final d = (Offset(g.laneCenterX(col), y) - pos).distance;
      if (d < g.arrowSize * 0.6 && d < bestDist) {
        best = n;
        bestDist = d;
      }
    }
    return best;
  }

  double rowY(double second, Size size) => _geometry(size).yFor(second);

  StepNote? nearestRow(double y, Size size) {
    final g = _geometry(size);
    StepNote? best;
    var distance = double.infinity;
    for (final n in notes) {
      if (n.type == StepType.mine) continue;
      final d = (g.yFor(n.second) - y).abs();
      if (d < distance) {
        best = n;
        distance = d;
      }
    }
    return best;
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

  // Connect each note to the previous one struck by the same foot, as two
  // polylines behind the arrowheads, so the chart's movement pattern reads at a
  // glance. Held notes anchor to the receptor while active, matching where their
  // head is drawn.
  //
  // The chaining is precomputed ([footPrev]), so this touches only the visible
  // window: every visible note draws its incoming link, active holds draw
  // theirs, and the first note per foot beyond the window closes the outgoing one.
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
  static final Paint _measurePillPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.85);

  static const Color _measureColor = Color(0xFF8FA3B8);
  static final Paint _measureLinePaint = Paint()
    ..color = _measureColor.withValues(alpha: 0.22)
    ..strokeWidth = 1;

  // Rule the field at every bar and number each at the left edge, the way a
  // stepchart editor does, so a spot in the chart can be named. Positions go
  // through [yFor], so the rules ride BPM changes and stops rather than being a
  // fixed pixel grid; bars number from 1 at beat 0 (editor convention). Two
  // z-layers, like [_paintTimingMarkers].
  void _paintMeasureLines(Canvas canvas, Size size,
      double Function(double) yFor, double currentBeat, double maxBeat,
      {required bool labels}) {
    // Zoomed out the rules crowd together, so number only every fourth one and
    // let the rest read as plain ruling.
    final labelEvery = pxPerBeat * 4 < 46 ? 4 : 1;
    for (final l in BarGrid(timeSignatures).lines(currentBeat - 8, maxBeat)) {
      final number = l.number;
      if (number == null) continue;
      final y = yFor(timing.secondAt(l.beat));
      if (!labels) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), _measureLinePaint);
        continue;
      }
      if ((number - 1) % labelEvery != 0) continue;
      _paintMarkerLabel(canvas, size, y, "$number", _measureColor,
          alignLeft: true, pill: _measurePillPaint);
    }
  }

  // DDR's guideline: a line on every beat across the lanes, bar lines at full
  // strength and the rest at a quarter. Lines ride the scroll like the
  // arrows, hang down from their position, and fade out over two thirds of an
  // arrow once the beat itself has passed the receptor, whatever the [shift].
  // A beat carrying a BPM change or stop gives its line to that marker.
  void _paintGuideline(
      Canvas canvas,
      double Function(double) yFor,
      double shift,
      double currentBeat,
      double maxBeat,
      double left,
      double width,
      double arrowSize) {
    final taken = [
      for (final b in bpmMarkers) timing.beatAt(b.second),
      for (final s in stopMarkers) timing.beatAt(s.second),
    ];
    final paint = Paint();
    final thickness = math.max(1.0, arrowSize * 3 / 96);
    final fade = arrowSize * 2 / 3;
    for (final l in BarGrid(timeSignatures).lines(currentBeat - 1, maxBeat)) {
      if (taken.any((t) => (t - l.beat).abs() < 0.01)) continue;
      final y = yFor(timing.secondAt(l.beat));
      final past = (_receptorTop - y) / fade;
      if (past >= 1) continue;
      final alpha = (l.bar ? 255 : 63) / 255 * (1 - past.clamp(0.0, 1.0));
      paint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawRect(Rect.fromLTWH(left, y + shift, width, thickness), paint);
    }
  }

  // Full-width markers for stops (a band spanning the halt) and BPM changes (a
  // line + label), on the same seconds axis the notes scroll on, culled to the
  // visible window. Drawn in two z-layers: lines/bands before the notes so
  // arrows scroll over them, pill labels after so a stream can't bury them.
  void _paintTimingMarkers(
    Canvas canvas,
    Size size,
    double Function(double) yFor,
    double maxT,
    bool beatLocked,
    bool expandStops, {
    required bool labels,
  }) {
    // A stop occupies zero beat-space while playing (the field freezes on it),
    // so it draws as one bold line carrying its duration in the label. Paused,
    // and in the constant-time fallback, it gets real vertical extent and draws
    // as a band so its length reads at a glance.
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
      canvas.drawLine(
          Offset(0, yTop), Offset(size.width, yTop), _stopEdgePaint);
      canvas.drawLine(
          Offset(0, yBot), Offset(size.width, yBot), _stopEdgePaint);
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

  // Laid-out TextPainters cached across frames — text shaping is far too
  // expensive to redo per marker/badge per frame. Keys carry everything the
  // glyphs depend on; the caps stop a long session accumulating stale entries.
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
    Paint? pill,
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
    canvas.drawRRect(rect, pill ?? _labelPillPaint);
    tp.paint(canvas, Offset(left + padX, top + padY));
  }

  static final Paint _highlightFillPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.07);
  static final Paint _highlightEdgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white.withValues(alpha: 0.35);
  static final Paint _sectionFillPaint = Paint()
    ..color = kSectionColor.withValues(alpha: 0.08);
  static final Paint _sectionEdgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = kSectionColor.withValues(alpha: 0.7);
  static final Paint _patternBadgePaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.75);
  static final Map<int, TextPainter> _iconTpCache = {};

  // A pattern's icon in a dark disc on the band's top-left corner.
  void _paintPatternBadge(
      Canvas canvas, double fieldLeft, double y, IconData icon) {
    const r = 12.0;
    final c = Offset(math.max(fieldLeft, r + 4), y);
    canvas.drawCircle(c, r, _patternBadgePaint);
    canvas.drawCircle(c, r, _highlightEdgePaint);
    if (_iconTpCache.length > 16) _iconTpCache.clear();
    final tp = _iconTpCache.putIfAbsent(icon.codePoint, () {
      return TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
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
  static final Paint _focusGlowPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.16);
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
      old.paintBackground != paintBackground ||
      old.guideline != guideline ||
      old.timeSignatures != timeSignatures ||
      old.zoom != zoom ||
      old.constantMs != constantMs ||
      old.topInset != topInset ||
      old.arcadeQuant != arcadeQuant ||
      // Without this the field wouldn't move while dialling VISUAL OFFSET
      // paused: the playhead notifier hasn't changed, so nothing else here
      // would report the repaint.
      old.visualOffset != visualOffset ||
      old.focus != focus ||
      old.highlights != highlights ||
      old.section != section ||
      old.sectionTail != sectionTail;
}
