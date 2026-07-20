/// Name: SongChart
/// Parent: SongPage
/// Description: Page that displays selected song chart information
library;

import 'package:ddr_md/components/song/song_details.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
  // fl_chart spot arrays
  final List<FlSpot> _songBpmSpots = [];
  final List<FlSpot> _songStopSpots = [];

  // Late initialisations
  late bool hasStops; // if chart has stops at all
  late bool isShowingStops; // handler for toggling stops

  /// Finds nearest BPM to the stop's [st]arting point
  /// provided compared against the [array]
  int findNearestStop(double st, List array) {
    var nearest = 0;
    array.asMap().entries.forEach((entry) {
      var i = entry.key;
      Bpm a = array[i];
      if (a.st <= st) {
        nearest = a.val;
        return;
      }
    });
    return nearest;
  }

  // Generate BPM points from song chart
  void genBpmPoints(Chart chart) {
    List<Bpm> bpms = chart.bpms;

    if (_songBpmSpots.isNotEmpty || _songStopSpots.isNotEmpty) {
      _songBpmSpots.clear();
      _songStopSpots.clear();
    }
    // Adding a spot for each BPM change in the song
    for (int i = 0; i < bpms.length; i++) {
      _songBpmSpots.add(FlSpot(bpms[i].st, bpms[i].val.toDouble()));
      _songBpmSpots.add(FlSpot(bpms[i].ed, bpms[i].val.toDouble()));
    }
    // Adding a spot for each stop in the song
    for (int i = 0; i < chart.stops.length; i++) {
      // Finding nearest BPM to the stop
      double nearestBpm = findNearestStop(chart.stops[i].st, bpms).toDouble();
      _songStopSpots.add(FlSpot(chart.stops[i].st, nearestBpm));
    }
  }

  // Initialise variables
  @override
  void initState() {
    super.initState();
    hasStops = widget.chart.stops.isNotEmpty;
    isShowingStops = true;
  }

  // Ensure that we're watching the songInfo.chart for any changes
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    late SongState songState = Provider.of<SongState>(context);
    final charts = songState.songInfo!.charts;
    genBpmPoints(songState.songInfo!.perChart
        ? charts[songState.chosenDifficulty.clamp(0, charts.length - 1)]
        : charts.first);
  }

  @override
  Widget build(BuildContext context) {
    Color bpmLineColor = Colors.redAccent.shade100;
    MaterialAccentColor stopLineColor = Colors.lightBlueAccent;
    List<LineChartBarData> lineChartBarData = [
      LineChartBarData(
          spots: _songBpmSpots,
          barWidth: 1.25,
          color: bpmLineColor,
          isCurved: false,
          dotData: const FlDotData(
            show: false,
          )),
      LineChartBarData(
          show: isShowingStops && hasStops,
          barWidth: 0,
          spots: _songStopSpots,
          color: stopLineColor.withValues(alpha: 0.85),
          dotData: FlDotData(
            getDotPainter: (spot, percent, barData, index) =>
                FlDotCirclePainter(
                    radius: 2.5,
                    color: stopLineColor,
                    strokeWidth: 1,
                    strokeColor: stopLineColor.shade700),
          ))
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Remove the default ExpansionTile top/bottom divider lines so the
        // expanded state doesn't show a stray line against the card.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          title: const Text(
            'BPM Graph',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(10, 0, 25, 0),
              height: MediaQuery.of(context).size.height / 3,
              child: LineChart(
                curve: Easing.standard,
                LineChartData(
                  titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        axisNameWidget: const Text(
                          'Time (s)',
                          style: TextStyle(fontSize: 10),
                        ),
                        sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 26,
                            interval: 15,
                            getTitlesWidget: (value, meta) {
                              Widget axisTitle = Text(value.floor().toString());
                              // A workaround to hide the max value title as FLChart is overlapping it on top of previous
                              if (value == meta.max) {
                                final remainder = value % meta.appliedInterval;
                                if (remainder != 0.0 &&
                                    remainder / meta.appliedInterval < 0.5) {
                                  axisTitle = const SizedBox.shrink();
                                }
                              }
                              return SideTitleWidget(
                                  axisSide: meta.axisSide, child: axisTitle);
                            }),
                      ),
                      leftTitles: AxisTitles(
                        axisNameWidget: const Text(
                          'BPM',
                          style: TextStyle(fontSize: 10),
                        ),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 43,
                          interval: 100,
                          getTitlesWidget: (value, meta) {
                            Widget axisTitle = Text(value.floor().toString());
                            // A workaround to hide the max value title as FLChart is overlapping it on top of previous
                            if (value == meta.max) {
                              final remainder = value % meta.appliedInterval;
                              if (remainder != 0.0 &&
                                  remainder / meta.appliedInterval < 0.5) {
                                axisTitle = const SizedBox.shrink();
                              }
                            }
                            return SideTitleWidget(
                                axisSide: meta.axisSide, child: axisTitle);
                          },
                        ),
                      ),
                      topTitles: AxisTitles(
                        axisNameWidget: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle, color: bpmLineColor),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              "BPM",
                              style: TextStyle(fontSize: 10),
                            ),
                            const SizedBox(width: 10),
                            if (isShowingStops && hasStops) ...<Widget>[
                              Container(
                                width: 10,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: stopLineColor.shade200),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                "Stops",
                                style: TextStyle(fontSize: 10),
                              ),
                            ],
                          ],
                        ),
                        sideTitles: const SideTitles(
                          showTitles: false,
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: false,
                        ),
                      )),
                  lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                          fitInsideHorizontally: true,
                          getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                            bool first = true;
                            return touchedBarSpots.map((barSpot) {
                              var stopTime = formattedTime(
                                      timeInSecond: barSpot.x.toInt()) +
                                  "s";
                              var bpmY = barSpot.y;
                              if (first) {
                                first = false;
                                return LineTooltipItem(
                                    ('BPM: $bpmY\nTIME: $stopTime'),
                                    const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold));
                              }
                            }).toList();
                          },
                          tooltipBgColor: Colors.grey.shade900,
                          tooltipPadding: const EdgeInsets.all(2),
                          tooltipBorder:
                              const BorderSide(color: Colors.black))),
                  clipData: const FlClipData.all(),
                  borderData: FlBorderData(
                      border:
                          Border.all(color: Colors.grey.shade600, width: 1)),
                  gridData: FlGridData(
                    show: true,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.shade400,
                        strokeWidth: 1,
                      );
                    },
                    drawVerticalLine: true,
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Colors.grey.shade400,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  minX: 0,
                  minY: 0,
                  maxX: widget.songInfo!.songLength,
                  maxY: widget.chart.trueMax.toDouble() + 10,
                  lineBarsData: lineChartBarData,
                ),
              ),
            ),
            if (hasStops) ...[
              CheckboxListTile(
                title: const Text("Toggle Stops",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                value: isShowingStops,
                onChanged: (_) {
                  HapticFeedback.lightImpact();
                  setState(() {
                    isShowingStops = !isShowingStops;
                  });
                },
                controlAffinity: ListTileControlAffinity.trailing,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SongSyncChart extends StatelessWidget {
  const SongSyncChart({super.key, required this.songInfo, required this.chart});

  final SongInfo songInfo;
  final Chart chart;

  @override
  Widget build(BuildContext context) {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final curveColor = Color.alphaBlend(
      Colors.black.withValues(alpha: isDark ? 0.18 : 0.14),
      Theme.of(context).cardColor,
    );
    // Theme variants: darker hues for light mode, brighter for dark mode.
    final fastColor =
      isDark ? const Color(0xFF46FCE7) : const Color(0xFF00A89E);
    final slowColor =
      isDark ? const Color(0xFFFF45A0) : const Color(0xFFE53886);
    final biasColor = sync.biasMs < 0
        ? slowColor
        : sync.biasMs > 0
            ? fastColor
            : Colors.grey.shade600;
    final biasLabel =
        '${sync.biasMs >= 0 ? '+' : ''}${sync.biasMs.toStringAsFixed(1)} ms';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Remove the default ExpansionTile top/bottom divider lines so the
        // expanded state doesn't show a stray line against the card.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text(
            'Sync',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '$biasLabel bias · ${(sync.confidence * 100).round()}% confidence'
            ' · ${isCabinet ? 'cabinet' : 'simfile'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(10, 8, 25, 8),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height / 4,
              child: LineChart(
                LineChartData(
                  titlesData: FlTitlesData(
                    bottomTitles: const AxisTitles(
                      axisNameWidget: Text(
                        'offset from beat (ms)',
                        style: TextStyle(fontSize: 10),
                      ),
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    // The response curve is normalized (0-100, unitless), so
                    // the y-axis carries no readable values.
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
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
                          tooltipBgColor: Colors.grey.shade900,
                          tooltipPadding: const EdgeInsets.all(2),
                          tooltipBorder:
                              const BorderSide(color: Colors.black))),
                  extraLinesData: ExtraLinesData(
                    verticalLines: [
                      // On-beat reference (0 ms)
                      VerticalLine(
                        x: 0,
                        color: Colors.grey.shade600,
                        strokeWidth: 1,
                        dashArray: [4, 4],
                      ),
                      // Detected attack (sync bias)
                      VerticalLine(
                        x: sync.biasMs,
                        color: biasColor,
                        strokeWidth: 1.5,
                        label: VerticalLineLabel(
                          show: true,
                          alignment: sync.biasMs >= 0
                              ? Alignment.topRight
                              : Alignment.topLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: biasColor,
                          ),
                          labelResolver: (_) => biasLabel,
                        ),
                      ),
                    ],
                  ),
                  clipData: const FlClipData.all(),
                  borderData: FlBorderData(
                      border:
                          Border.all(color: Colors.grey.shade600, width: 1)),
                  gridData: FlGridData(
                    show: true,
                    drawHorizontalLine: false,
                    drawVerticalLine: false,
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Colors.grey.shade400,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  minX: sync.curveStartMs,
                  maxX: sync.curveStartMs +
                      (sync.curve.length - 1) * sync.curveStepMs,
                  minY: 0,
                  maxY: 108,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      barWidth: 0.6,
                      color: curveColor,
                      isCurved: false,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: curveColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'feels late',
                    style: TextStyle(
                      color: slowColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'feels early',
                    style: TextStyle(
                      color: fastColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SongRadarChart extends StatelessWidget {
  const SongRadarChart({super.key, required this.radar});

  final Radar? radar;

  @override
  Widget build(BuildContext context) {
    final radar = this.radar;
    if (radar == null) return const SizedBox.shrink();
    final labels = <String>['Stream', 'Voltage', 'Air', 'Freeze', 'Chaos'];
    final values = <double>[
      radar.stream,
      radar.voltage,
      radar.air,
      radar.freeze,
      radar.chaos,
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Remove the default ExpansionTile top/bottom divider lines so the
        // expanded state doesn't show a stray line against the card.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text(
            'Groove Radar',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
          children: [
            SizedBox(
              height: 280,
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
                  titleTextStyle: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600),
                  getTitle: (index, angle) {
                    return RadarChartTitle(text: labels[index]);
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
                      fillColor: Colors.transparent,
                      borderColor: Colors.grey.shade400,
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
                    RadarDataSet(
                      fillColor: Colors.redAccent.withValues(alpha: 0.25),
                      borderColor: Colors.redAccent,
                      borderWidth: 2,
                      entryRadius: 2.5,
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
          ],
        ),
      ),
    );
  }
}
