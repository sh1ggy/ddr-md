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
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

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
  });

  final ChartSteps steps;
  final Modes mode;

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

  // Scroll rate multiplier (visual speed-mod feel). 1.0 = default spacing.
  double _rate = 1.0;
  int _modIndex = 3; // 1.0x in constants.mods

  // Notes that are part of a shock row are drawn as bars, not mines, so the
  // painter skips them and draws [_shocks] instead.
  final Set<StepNote> _shockNotes = {};
  final List<_ShockRow> _shocks = [];

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

  double get _pxPerSecond => _basePxPerSecond * _rate;
  int get _effectiveChartBpm => widget.chartBpm > 0 ? widget.chartBpm : constants.songBpm;
  int get _currentReadSpeed => (_effectiveChartBpm * _rate).round();

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
    _detectShocks();
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
    if (old.steps != widget.steps || old.mode != widget.mode) {
      _pause();
      _detectShocks();
      _buildDensity();
      setState(() => _second = 0);
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

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;

    setState(() {
      if (_playing) {
        _second += dt;
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
    setState(() => _playing = true);
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

  void _togglePlay({bool showOverlay = false}) {
    HapticFeedback.selectionClick();
    final willPlay = !_playing;
    _playing ? _pause() : _play();
    if (showOverlay) _flashTapOverlay(willPlay);
  }

  void _stepReadSpeed(int delta) {
    final newIndex = _modIndex + delta;
    if (newIndex < 0 || newIndex >= constants.mods.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _modIndex = newIndex;
      _rate = constants.mods[_modIndex];
    });
  }

  // --- drag-to-scrub with momentum ---

  void _onDragStart(DragStartDetails _) {
    _pause();
    _flingVel = 0; // catch any ongoing fling
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // Drag up (negative dy) advances the chart; down rewinds. Notes descend, so
    // pulling the field up pulls future notes down toward the receptor.
    setState(() {
      _second = (_second - d.primaryDelta! / _pxPerSecond)
          .clamp(0.0, _endSecond);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    // Convert the fling's pixel velocity into chart-seconds velocity and let the
    // ticker coast it to a smooth stop.
    final vPx = d.primaryVelocity ?? 0;
    _flingVel = (-vPx / _pxPerSecond);
    if (_flingVel.abs() < _flingMin) {
      _flingVel = 0;
      return;
    }
    _ensureTicking();
  }

  @override
  void dispose() {
    _tapOverlayTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dirs = widget.mode == Modes.singles ? kSingleDirs : kDoubleDirs;
    return LayoutBuilder(builder: (context, constraints) {
      return Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Tap the field to play/pause; drag up/down to scrub with a
              // momentum fling that coasts to a stop.
              onTap: () => _togglePlay(showOverlay: true),
              onVerticalDragStart: _onDragStart,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _ChartPainter(
                        notes: widget.steps.notes,
                        shockNotes: _shockNotes,
                        shocks: _shocks,
                        dirs: dirs,
                        second: _second,
                        pxPerSecond: _pxPerSecond,
                        columnCount: dirs.length,
                        skin: _skin,
                        playing: _playing,
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
                              color: Colors.black.withOpacity(0.26),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _tapOverlayIcon,
                              color: Colors.white.withOpacity(0.88),
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildTransport(context),
        ],
      );
    });
  }

  Widget _buildTransport(BuildContext context) {
    final progress = _endSecond <= 0
        ? 0.0
        : (_second / _endSecond).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmtTime(_second),
                style: const TextStyle(
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              Text(
                _fmtTime(_endSecond),
                style: const TextStyle(
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              color: Colors.black.withOpacity(0.12),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _DensityScrubBar(
                buckets: _minimap,
                progress: progress,
                accent: Theme.of(context).colorScheme.primary,
                onSeek: (frac) {
                  _pause();
                  setState(() => _second = (frac * _endSecond)
                      .clamp(0.0, _endSecond));
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => _stepReadSpeed(-1),
                child: const Text("−10"),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    "$_currentReadSpeed",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () => _stepReadSpeed(1),
                child: const Text("+10"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _fmtTime(double s) {
  final m = (s ~/ 60).toString();
  final sec = (s % 60).floor().toString().padLeft(2, '0');
  return "$m:$sec";
}

/// A scrub bar whose track is a note-density minimap of the whole chart (busy
/// sections show taller bars), with a played/unplayed split and a draggable
/// playhead. Tap or drag anywhere to seek. [progress] and [onSeek] are 0..1.
class _DensityScrubBar extends StatelessWidget {
  const _DensityScrubBar({
    required this.buckets,
    required this.progress,
    required this.accent,
    required this.onSeek,
  });

  final List<_MinimapBucket> buckets;
  final double progress;
  final Color accent;
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
  });

  final List<_MinimapBucket> buckets;
  final double progress;
  final Color accent;

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
                  ? const Color(0xFF39C46B).withOpacity(0.36)
                  : const Color(0xFF39C46B).withOpacity(0.18),
          );
        }
        if (bucket.segments.isEmpty) {
          canvas.drawRect(
            rect,
            Paint()..color = played ? accent : accent.withOpacity(0.28),
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
                    : segment.color.withOpacity(0.34),
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
                  ? const Color(0xFF79E7FF).withOpacity(0.95)
                  : const Color(0xFF79E7FF).withOpacity(0.55),
          );
        }
      }
    }

    // Playhead: vertical needle plus a layered knob for stronger visibility.
    canvas.drawRect(
      Rect.fromLTWH(playedX - 1, 0, 2, size.height),
      Paint()..color = Colors.white.withOpacity(0.92),
    );
    canvas.drawCircle(
      Offset(playedX, midY),
      10,
      Paint()..color = accent.withOpacity(0.22),
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
        ..color = Colors.white.withOpacity(0.95),
    );
  }

  @override
  bool shouldRepaint(_DensityPainter old) =>
      old.progress != progress ||
      old.buckets != buckets ||
      old.accent != accent;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.notes,
    required this.shockNotes,
    required this.shocks,
    required this.dirs,
    required this.second,
    required this.pxPerSecond,
    required this.columnCount,
    required this.skin,
    required this.playing,
  });

  final List<StepNote> notes;
  final Set<StepNote> shockNotes;
  final List<_ShockRow> shocks;
  final List<NoteDir> dirs;
  final double second;
  final double pxPerSecond;
  final int columnCount;
  final Noteskin skin;
  final bool playing;

  // Receptors sit near the TOP; arrows scroll up into them. Notes are drawn
  // ON TOP OF (z-above) the receptors so an arrow reaching the line covers it.
  static const double _receptorTop = 56;
  static const double _laneTighten = 0.92;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);

    final laneW = size.width / columnCount;
    final laneStride = laneW * _laneTighten;
    final fieldLeft = (size.width - laneStride * columnCount) / 2;
    // DDR World arrows fill nearly the whole lane (the atlas glyph is ~0.94 of
    // its cell). No small upper clamp — arrows scale with the lane so they read
    // at the arcade's size instead of shrinking on wide fields.
    final arrowSize = laneW * 0.92;

    double laneCenterX(int col) => fieldLeft + laneStride * col + laneStride / 2;
    double yFor(double t) => _receptorTop + (t - second) * pxPerSecond;

    _paintLanes(canvas, size, laneW, _receptorTop);

    // Visible time window. Notes draw on-screen until they align with the
    // receptor, then disappear immediately. Holds are the exception: once
    // their head is hit, it stays pinned to the receptor while the body drains.
    final maxT = second + ((size.height - _receptorTop) / pxPerSecond) + 1;

    // Receptors FIRST (behind the notes) so an arrow at the line covers its
    // receptacle rather than being hidden by it.
    // Receptors only pulse while playing; static (dim, steady) when paused.
    final glow = playing ? 1.0 - ((second * 2) % 1.0) : 0.0;
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

    // 1) Freeze/hold bodies (behind arrowheads). While a hold is being held its
    // head has reached the receptor, so clamp the head to the line; the body
    // then shrinks upward into it and vanishes at the tail.
    for (final n in notes) {
      if (!n.isHold) continue;
      final endS = n.endSecond ?? n.second;
      if (endS < second || n.second > maxT) continue;
      final headY =
          n.second >= second ? yFor(n.second) : _receptorTop.toDouble();
      skin.paintHoldBody(canvas, laneCenterX(n.col), headY, yFor(endS),
          arrowSize, dirs[n.col], n.type == StepType.roll);
      skin.paintHoldTail(canvas, laneCenterX(n.col), yFor(endS), arrowSize,
          dirs[n.col], n.type == StepType.roll);
    }

    // 2) Shock rows: a light-blue arrow in every lit lane linked by electricity,
    // spanning the whole row (also vanishes once hit).
    for (final s in shocks) {
      if (s.second < second || s.second > maxT) continue;
      final y = yFor(s.second);
      final lanes = [
        for (final c in s.cols) (laneCenterX(c), dirs[c]),
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
      final x = laneCenterX(n.col);
      final y = held ? _receptorTop.toDouble() : yFor(n.second);
      if (n.type == StepType.mine) {
        if (shockNotes.contains(n)) continue; // drawn in the shock pass
        skin.paintMine(canvas, x, y, arrowSize);
      } else {
        skin.paintArrow(canvas, x, y, arrowSize, dirs[n.col], n.beat);
      }
    }

    canvas.restore(); // end note clip
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

  void _paintLanes(Canvas canvas, Size size, double laneW, double receptorY) {
    // Subtle lane dividers.
    final div = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1;
    for (int c = 1; c < columnCount; c++) {
      final x = laneW * c;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), div);
    }
    // Receptor line highlight.
    final line = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withOpacity(0),
          Colors.white.withOpacity(0.18),
          Colors.white.withOpacity(0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 1));
    canvas.drawRect(
        Rect.fromLTWH(0, receptorY - 0.5, size.width, 1), line);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.second != second ||
      old.pxPerSecond != pxPerSecond ||
      old.notes != notes ||
      old.columnCount != columnCount ||
      old.skin != skin ||
      old.playing != playing;
}
