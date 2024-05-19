/// Name: SongChart
/// Parent: SongPage
/// Description: Page that displays selected song chart information
library;

import 'package:ddr_md/components/song/song_details.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class SongChart extends StatefulWidget {
  const SongChart({
    super.key,
    required this.songBpmSpots,
    required this.songStopSpots,
    required this.context,
    required this.songInfo,
    required this.chart,
  });

  final List<FlSpot> songBpmSpots;
  final List<FlSpot> songStopSpots;
  final BuildContext context;
  final SongInfo? songInfo;
  final Chart? chart;

  @override
  State<StatefulWidget> createState() => SongChartState();
}

class SongChartState extends State<SongChart> {
  late bool isShowingStops;

  @override
  void initState() {
    super.initState();
    isShowingStops = true;
  }

  @override
  Widget build(BuildContext context) {
    Color bpmLineColor = Colors.redAccent.shade100;
    MaterialAccentColor stopLineColor = Colors.lightBlueAccent;
    List<LineChartBarData> lineChartBarData = [
      LineChartBarData(
          spots: widget.songBpmSpots,
          barWidth: 1.25,
          color: bpmLineColor,
          isCurved: false,
          dotData: const FlDotData(
            show: false,
          )),
      LineChartBarData(
          show: isShowingStops,
          barWidth: 0,
          spots: widget.songStopSpots,
          color: stopLineColor.withOpacity(.85),
          dotData: FlDotData(
            getDotPainter: (spot, percent, barData, index) =>
                FlDotCirclePainter(
                    radius: 2.5,
                    color: stopLineColor,
                    strokeWidth: 1,
                    strokeColor: stopLineColor.shade700),
          ))
    ];
    return Column(
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
                        if (isShowingStops) ...<Widget>[
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
                      getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                        bool first = true;
                        return touchedBarSpots.map((barSpot) {
                          var stopTime =
                              formattedTime(timeInSecond: barSpot.x.toInt()) +
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
                      tooltipBorder: const BorderSide(color: Colors.black))),
              clipData: const FlClipData.all(),
              borderData: FlBorderData(
                  border: Border.all(color: Colors.grey.shade600, width: 1)),
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
              maxY: widget.chart!.trueMax.toDouble() + 10,
              lineBarsData: lineChartBarData,
            ),
          ),
        ),
        CheckboxListTile(
          title: const Text("Toggle Stops"),
          value: isShowingStops,
          onChanged: (value) {
            setState(() {
              isShowingStops = !isShowingStops;
            });
          },
          controlAffinity: ListTileControlAffinity.trailing,
        ),
      ],
    );
  }
}
