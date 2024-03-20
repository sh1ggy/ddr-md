import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

Color lineColor = Colors.orangeAccent;

List<LineChartBarData> lineChartBarData = [
  LineChartBarData(color: lineColor, isCurved: false, spots: [
    FlSpot(0, 222),
    FlSpot(56.216, 222),
    FlSpot(56.216, 111),
    FlSpot(64.865, 111),
    FlSpot(64.865, 222),
    FlSpot(82.162, 222),
    FlSpot(82.162, 444),
    FlSpot(91.351, 444),
  ])
];

// {
//   "st": 0.0,
//   "ed": 56.216,
//   "val": 222
// },
// {
//   "st": 56.216,
//   "ed": 64.865,
//   "val": 111
// },
// {
//   "st": 64.865,
//   "ed": 82.162,
//   "val": 222
// },
// {
//   "st": 82.162,
//   "ed": 91.351,
//   "val": 444
// }