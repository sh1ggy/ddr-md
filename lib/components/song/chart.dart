import 'package:ddr_md/components/song/chartData.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class LineChartContent extends StatelessWidget {
  const LineChartContent({super.key});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      curve: Easing.standard,
      LineChartData(

        borderData:
            FlBorderData(border: Border.all(color: Colors.black, width: 1)),
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (value) {
            return const FlLine(
              color: Colors.grey,
              strokeWidth: 1,
            );
          },
          drawVerticalLine: true,
          getDrawingVerticalLine: (value) {
            return const FlLine(
              color: Colors.grey,
              strokeWidth: 1,
            );
          },
        ),
        minX: 1,
        minY: 0,
        maxX: 105,
        maxY: 450,
        lineBarsData: lineChartBarData,
      ),
    );
  }
}
