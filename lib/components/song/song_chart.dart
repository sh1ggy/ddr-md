/// Name: SongChart
/// Parent: SongPage
/// Description: Page that displays selected song chart information
library;

import 'dart:math' as math;

import 'package:ddr_md/components/song/card_heading.dart';
import 'package:ddr_md/components/song/song_details.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SongChart extends StatefulWidget {
  const SongChart({
    super.key,
    required this.context,
    required this.songInfo,
    required this.chart,
  });
  final BuildContext context;
  final SongInfo? songInfo;
  final Chart chart;

  @override
  State<StatefulWidget> createState() => SongChartState();
}

class SongChartState extends State<SongChart> {
  bool isShowingStops = true;
  // The BPM section picked by touch, read out in the header.
  int? _picked;

  @override
  void didUpdateWidget(SongChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chart != widget.chart) _picked = null;
  }

  void _pick(double dx, double width) {
    final bpms = widget.chart.bpms;
    if (bpms.isEmpty || width <= 0) return;
    final t = dx / width * widget.songInfo!.songLength;
    final i = bpms.indexWhere((b) => t >= b.st && t < b.ed);
    final picked = i < 0 ? (t < bpms.first.st ? 0 : bpms.length - 1) : i;
    if (picked != _picked) {
      HapticFeedback.selectionClick();
      setState(() => _picked = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    final length = widget.songInfo!.songLength;
    final hasStops = chart.stops.isNotEmpty;
    final picked = _picked == null ? null : chart.bpms[_picked!];
    String time(double s) => formattedTime(timeInSecond: s.round());
    final muted = TextStyle(fontSize: 11, color: pop.haze);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const CardHeading('BPM Graph', icon: Icons.show_chart),
                const Spacer(),
                if (hasStops)
                  FilterChip(
                    label: Text('${chart.stops.length} stops'),
                    selected: isShowingStops,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) {
                      HapticFeedback.lightImpact();
                      setState(() => isShowingStops = v);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // What's under the finger, else the chart's headline and range.
            AnimatedSwitcher(
              duration: FloorPop.eighth,
              child: Row(
                key: ValueKey(_picked),
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${picked?.val ?? chart.dominantBpm}',
                      style: FloorPop.readout(28,
                          color: picked == null
                              ? scheme.onSurface
                              : _bpmColor(picked.val, chart.dominantBpm))),
                  const SizedBox(width: 8),
                  Text(
                    picked == null
                        ? '${chart.trueMin} ~ ${chart.trueMax}'
                        : '${time(picked.st)} – ${time(picked.ed)}',
                    style: FloorPop.readout(15, color: pop.haze)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, box) => GestureDetector(
                onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _pick(d.localPosition.dx, box.maxWidth),
                child: RepaintBoundary(
                  child: SizedBox(
                    height: 88,
                    child: TweenAnimationBuilder<double>(
                      // Bars rise into place when the chart changes.
                      key: ValueKey(chart),
                      tween: Tween(begin: 0, end: 1),
                      duration: MediaQuery.of(context).disableAnimations
                          ? Duration.zero
                          : FloorPop.beat,
                      curve: FloorPop.step,
                      builder: (context, grow, _) => CustomPaint(
                        size: Size.infinite,
                        painter: _BpmBarsPainter(
                          bpms: chart.bpms,
                          stops: isShowingStops ? chart.stops : const [],
                          length: length,
                          dominant: chart.dominantBpm,
                          lowest: chart.trueMin,
                          highest: chart.trueMax,
                          picked: _picked,
                          grow: grow,
                          stopColor: pop.haze,
                          baseline: pop.line,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final f in const [0.0, 0.25, 0.5, 0.75, 1.0])
                  Text(time(length * f), style: muted),
              ],
            ),
            const SizedBox(height: 8),
            // What the colours mean: each section against the headline BPM
            // that hi-speed is picked for.
            Wrap(spacing: 14, runSpacing: 4, children: [
              for (final (colour, label) in [
                (FloorPop.padBlue, 'slower'),
                (FloorPop.volt, '${chart.dominantBpm} BPM'),
                (FloorPop.coral, 'faster'),
              ])
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: colour, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 5),
                  Text(label, style: muted),
                ]),
              if (hasStops && isShowingStops)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.arrow_drop_down, size: 16, color: pop.haze),
                  Text('stop', style: muted),
                ]),
            ]),
          ],
        ),
      ),
    );
  }
}

/// A section's colour against the chart's headline BPM: slower in Pad Blue,
/// the headline in Volt, faster in Coral.
Color _bpmColor(int bpm, int dominant) => bpm < dominant
    ? FloorPop.padBlue
    : bpm == dominant
        ? FloorPop.volt
        : FloorPop.coral;

/// The chart's tempo over the song as bars, each as wide as its section and
/// as tall as its BPM on a log scale (so 110 and 880 both read), with a tick
/// along the top for every stop.
class _BpmBarsPainter extends CustomPainter {
  _BpmBarsPainter({
    required this.bpms,
    required this.stops,
    required this.length,
    required this.dominant,
    required this.lowest,
    required this.highest,
    required this.picked,
    required this.grow,
    required this.stopColor,
    required this.baseline,
  });

  final List<Bpm> bpms;
  final List<Stop> stops;
  final double length, grow;
  final int dominant, lowest, highest;
  final int? picked;
  final Color stopColor, baseline;

  static const _stopBand = 10.0, _gap = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (length <= 0) return;
    final top = stops.isEmpty ? 0.0 : _stopBand;
    final h = size.height - top;
    // The floor sits an octave under the slowest section, so it still shows.
    final lo = math.log(math.max(1, lowest) / 2);
    final hi = math.log(math.max(lowest + 1, highest));
    double heightOf(int bpm) =>
        h * ((math.log(math.max(1, bpm)) - lo) / (hi - lo)).clamp(0.08, 1.0);
    double x(double t) => (t / length).clamp(0, 1) * size.width;

    canvas.drawLine(Offset(0, size.height - 0.5),
        Offset(size.width, size.height - 0.5), Paint()..color = baseline);
    for (final (i, b) in bpms.indexed) {
      final left = x(b.st), right = x(b.ed);
      if (right - left < 0.5) continue;
      final barH = heightOf(b.val) * grow;
      final colour = _bpmColor(b.val, dominant);
      final dim = picked != null && picked != i;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(left + _gap / 2, size.height - barH,
              math.max(left + _gap / 2 + 1.5, right - _gap / 2), size.height),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = colour.withValues(alpha: dim ? 0.35 : 1),
      );
    }
    final stopPaint = Paint()..color = stopColor;
    for (final s in stops) {
      final cx = x(s.st);
      canvas.drawPath(
          Path()
            ..moveTo(cx - 3.5, 0)
            ..lineTo(cx + 3.5, 0)
            ..lineTo(cx, 6)
            ..close(),
          stopPaint);
    }
  }

  @override
  bool shouldRepaint(_BpmBarsPainter old) =>
      old.bpms != bpms ||
      old.stops != stops ||
      old.picked != picked ||
      old.grow != grow ||
      old.stopColor != stopColor;
}

class SongSyncChart extends StatefulWidget {
  const SongSyncChart({super.key, required this.songInfo, required this.chart});

  final SongInfo songInfo;
  final Chart chart;

  @override
  State<SongSyncChart> createState() => _SongSyncChartState();
}

class _SongSyncChartState extends State<SongSyncChart> {
  @override
  Widget build(BuildContext context) {
    final songInfo = widget.songInfo;
    final chart = widget.chart;
    final sync = songInfo.displaySyncFor(chart);
    if (sync == null || sync.curve.isEmpty) return const SizedBox.shrink();
    // Cabinet fingerprint when the arcade data covers this song; otherwise
    // the simfile fallback, which says nothing about how the cab feels.
    final isCabinet = sync == songInfo.arcadeSync;

    final spots = <FlSpot>[
      for (var i = 0; i < sync.curve.length; i++)
        FlSpot(
          sync.curveStartMs + i * sync.curveStepMs,
          sync.curve[i].toDouble(),
        ),
    ];
    final pop = FloorPop.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Shared app-wide FAST/SLOW palette (see constants.dart) — the chart
    // preview's ARCADE SYNC dials tint from the same pair.
    final fastColor = kFastColor(isDark);
    final slowColor = kSlowColor(isDark);
    final biasColor = sync.biasMs < 0
        ? slowColor
        : sync.biasMs > 0
            ? fastColor
            : pop.haze;
    // Positive bias: chart plays fast (steps land ahead of the beat), which
    // in-game is corrected by nudging the audio offset negative — so the
    // suggested adjustment is the bias with its sign flipped.
    final adjustBy = -sync.biasMs;
    final adjustLabel =
        '${adjustBy >= 0 ? '+' : ''}${adjustBy.toStringAsFixed(1)} ms';
    final caption = TextStyle(fontSize: 11, color: pop.haze);

    // Always open: the curve is short enough to read at a glance, so it sits
    // under the number rather than behind a tap.
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const CardHeading('Sync', icon: Icons.av_timer),
                const SizedBox(width: 10),
                Text(adjustLabel,
                    style: FloorPop.readout(20, color: biasColor)),
              ],
            ),
            Text('recommended offset (${isCabinet ? 'cabinet' : 'simfile'})',
                style: caption),
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: LineChart(
                LineChartData(
                  titlesData: const FlTitlesData(show: false),
                  lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                          fitInsideHorizontally: true,
                          getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                            return touchedBarSpots.map((barSpot) {
                              return LineTooltipItem(
                                  '${barSpot.x >= 0 ? '+' : ''}${barSpot.x.toStringAsFixed(0)} ms',
                                  const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold));
                            }).toList();
                          },
                          tooltipBgColor: pop.riser,
                          tooltipPadding: const EdgeInsets.all(4),
                          tooltipBorder: BorderSide(color: pop.line))),
                  extraLinesData: ExtraLinesData(
                    verticalLines: [
                      // On-beat reference (0 ms)
                      VerticalLine(
                        x: 0,
                        color: pop.line,
                        strokeWidth: 1.5,
                        dashArray: [3, 4],
                      ),
                    ],
                  ),
                  clipData: const FlClipData.all(),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  minX: sync.curveStartMs,
                  maxX: sync.curveStartMs +
                      (sync.curve.length - 1) * sync.curveStepMs,
                  minY: 0,
                  maxY: 108,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      barWidth: 2,
                      color: biasColor,
                      isCurved: false,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: biasColor.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('chart is slow',
                    style: caption.copyWith(
                        color: slowColor, fontWeight: FontWeight.w600)),
                Text('offset from beat (ms)', style: caption),
                Text('chart is fast',
                    style: caption.copyWith(
                        color: fastColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SongRadarChart extends StatelessWidget {
  const SongRadarChart(
      {super.key, required this.radar, this.expanded = false, this.color});

  final Radar? radar;
  final bool expanded;
  // The chosen chart's difficulty colour.
  final Color? color;

  static const _axisIcons = [
    Icons.waves,
    Icons.bolt,
    Icons.flight,
    Icons.ac_unit,
    Icons.shuffle,
  ];

  // The radar grows out of its spot to fill the screen, keeping its colour,
  // a beat long (instant under reduced motion).
  void _openRadar(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      transitionDuration: still ? Duration.zero : FloorPop.beat,
      reverseTransitionDuration: still ? Duration.zero : FloorPop.eighth,
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.6, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: FloorPop.step)),
          child: child,
        ),
      ),
      pageBuilder: (context, animation, secondaryAnimation) => Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(context),
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.85,
                    height: MediaQuery.sizeOf(context).height * 0.65,
                    child: SongRadarChart(
                        radar: radar, expanded: true, color: color),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Close Groove Radar',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final radar = this.radar;
    if (radar == null) return const SizedBox.shrink();
    final pop = FloorPop.of(context);
    final tint = color ?? FloorPop.volt;
    final labels = <String>['Stream', 'Voltage', 'Air', 'Freeze', 'Chaos'];
    final values = <double>[
      radar.stream,
      radar.voltage,
      radar.air,
      radar.freeze,
      radar.chaos,
    ];

    final chart = Semantics(
      label: 'Groove Radar: Stream ${radar.stream}, Voltage ${radar.voltage}, '
          'Air ${radar.air}, Freeze ${radar.freeze}, Chaos ${radar.chaos}',
      child: SizedBox(
        width: expanded ? null : 84,
        height: expanded ? null : 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: RadarChart(
                RadarChartData(
                  radarShape: RadarShape.polygon,
                  // Pull axis titles inward from the polygon edge so the top
                  // label isn't clipped by the chart's bounds.
                  titlePositionPercentageOffset: 0.15,
                  // fl_chart places the chart center at min - (max-min)/tickCount
                  // rather than zero; with the zero-anchor dataset below, a high
                  // tick count pushes the center to ~zero so radii stay
                  // proportional to value/100. Ticks are invisible anyway.
                  tickCount: 50,
                  // The built-in grid always scales to the largest data value,
                  // so hide it entirely; the 100-scale pentagon is drawn as a
                  // dataset below instead, letting values over 100 burst
                  // through the frame like the arcade groove radar.
                  ticksTextStyle:
                      const TextStyle(color: Colors.transparent, fontSize: 10),
                  tickBorderData: const BorderSide(color: Colors.transparent),
                  gridBorderData: const BorderSide(color: Colors.transparent),
                  radarBorderData: const BorderSide(color: Colors.transparent),
                  // Expanded, it sits on a dark scrim in either theme.
                  titleTextStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: expanded ? Colors.white : null),
                  getTitle: (index, angle) {
                    return RadarChartTitle(
                      text: expanded
                          ? '${labels[index]} ${values[index].round()}'
                          : '',
                    );
                  },
                  dataSets: [
                    // Invisible zero anchor so the chart's minimum (and thus
                    // its center, see tickCount above) is pinned at 0 for
                    // every song rather than at the smallest radar value.
                    RadarDataSet(
                      fillColor: Colors.transparent,
                      borderColor: Colors.transparent,
                      borderWidth: 0,
                      entryRadius: 0,
                      dataEntries: const [
                        RadarEntry(value: 0),
                        RadarEntry(value: 0),
                        RadarEntry(value: 0),
                        RadarEntry(value: 0),
                        RadarEntry(value: 0),
                      ],
                    ),
                    // The 100-scale pentagon frame. It doubles as the scale
                    // floor: when every value is <=100 it defines the outer
                    // bound, and when a value exceeds 100 the chart's bound
                    // stretches to that value while this frame stays at 100,
                    // so the data polygon renders outside it.
                    RadarDataSet(
                      fillColor: pop.riser.withValues(alpha: 0.6),
                      borderColor: pop.line,
                      borderWidth: 1.5,
                      entryRadius: 0,
                      dataEntries: const [
                        RadarEntry(value: 100),
                        RadarEntry(value: 100),
                        RadarEntry(value: 100),
                        RadarEntry(value: 100),
                        RadarEntry(value: 100),
                      ],
                    ),
                    // A halfway ring, so a value reads against the frame.
                    RadarDataSet(
                      fillColor: Colors.transparent,
                      borderColor: pop.line,
                      borderWidth: 1,
                      entryRadius: 0,
                      dataEntries: const [
                        RadarEntry(value: 50),
                        RadarEntry(value: 50),
                        RadarEntry(value: 50),
                        RadarEntry(value: 50),
                        RadarEntry(value: 50),
                      ],
                    ),
                    RadarDataSet(
                      fillColor: tint.withValues(alpha: 0.35),
                      borderColor: tint,
                      borderWidth: 2,
                      entryRadius: 1.5,
                      dataEntries: values
                          .map((value) => RadarEntry(value: value))
                          .toList(),
                    ),
                  ],
                  radarBackgroundColor: Colors.transparent,
                ),
                swapAnimationDuration: const Duration(milliseconds: 300),
                swapAnimationCurve: Curves.easeOut,
              ),
            ),
            if (!expanded) ...[
              for (final (index, alignment) in const [
                Alignment(0, -1),
                Alignment(1, -0.31),
                Alignment(0.62, 1),
                Alignment(-0.62, 1),
                Alignment(-1, -0.31),
              ].indexed)
                Align(
                  alignment: alignment,
                  child: Tooltip(
                    message: '${labels[index]}: ${values[index].round()}',
                    child: Icon(_axisIcons[index], size: 11, color: pop.haze),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
    if (expanded) return IgnorePointer(child: chart);
    return Semantics(
      button: true,
      hint: 'Expand Groove Radar',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openRadar(context),
        child: chart,
      ),
    );
  }
}
