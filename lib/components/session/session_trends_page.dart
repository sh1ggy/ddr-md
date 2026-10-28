/// Name: SessionTrendsPage
/// Parent: SessionPage, SessionsPage
/// Description: Browse score and timing trends by week, fortnight or month,
/// with chart, level, mode and cabinet filters and like-for-like comparisons.
library;

import 'dart:math' as math;
import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/session/visits.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/session_trends.dart';
import 'package:ddr_md/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class SessionTrendsPage extends StatelessWidget {
  const SessionTrendsPage({super.key});

  @override
  Widget build(BuildContext context) => HomeSubpage(
        title: 'Trends',
        body: FutureBuilder<VisitData>(
          future: visitsFor(context),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                  child: Text('Could not load trends. Reopen to try again.'));
            }
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return SessionTrendsView(
              plays: trendPlays(
                  data.visits, data.timing, data.credits, data.model),
              cabinets: {
                for (final list in data.credits.values)
                  for (final c in list) c.cabinet.id: c.cabinet
              },
            );
          },
        ),
      );
}

/// Data is supplied separately so range changes and filters need no re-query.
class SessionTrendsView extends StatefulWidget {
  const SessionTrendsView(
      {super.key, required this.plays, this.cabinets = const {}, this.now});
  final List<TrendPlay> plays;
  final Map<int, Cabinet> cabinets;
  final DateTime? now;

  @override
  State<SessionTrendsView> createState() => _SessionTrendsViewState();
}

class _SessionTrendsViewState extends State<SessionTrendsView> {
  late DateTime _anchor = widget.now ?? DateTime.now();
  TrendRange _range = TrendRange.week;
  TrendMetric _metric = TrendMetric.score;
  Modes? _mode;
  int? _level, _venue, _cabinet, _selected;
  String? _chart;
  PadSide? _side;

  @override
  void didUpdateWidget(SessionTrendsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A sync or deleted visit can remove the last option in a picker.
    if (!widget.plays.any((p) => p.play.mode == _mode)) _mode = null;
    if (!widget.plays.any((p) => p.level == _level)) _level = null;
    if (!widget.plays.any((p) => p.chart == _chart)) _chart = null;
    if (!widget.cabinets.values.any((c) => c.venueId == _venue)) _venue = null;
    if (!widget.cabinets.containsKey(_cabinet)) _cabinet = null;
    _selected = null;
  }

  void _change(VoidCallback update) => setState(() {
        update();
        _selected = null;
      });

  Future<void> _pickChart() async {
    final charts = {
      for (final p in widget.plays)
        if ((_mode == null || p.play.mode == _mode) &&
            (_level == null || p.level == _level))
          p.chart: p
    };
    final sorted = charts.values.toList()
      ..sort((a, b) => a.play.title.compareTo(b.play.title));
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
            builder: (context, update) => SafeArea(
                  child: SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.75,
                    child: Column(children: [
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            decoration: const InputDecoration(
                                labelText: 'Find a chart',
                                prefixIcon: Icon(Icons.search)),
                            onChanged: (text) =>
                                update(() => query = text.toLowerCase()),
                          )),
                      ListTile(
                          title: const Text('All charts'),
                          onTap: () => Navigator.pop(context, '')),
                      Expanded(
                          child: ListView(children: [
                        for (final p in sorted.where(
                            (p) => p.play.title.toLowerCase().contains(query)))
                          ListTile(
                              title: Text(p.play.title),
                              subtitle: Text(
                                  '${p.play.mode == Modes.singles ? 'SP' : 'DP'} · ${p.play.difficulty} · ${p.level ?? '?'}'),
                              selected: _chart == p.chart,
                              onTap: () => Navigator.pop(context, p.chart)),
                      ])),
                    ]),
                  ),
                ));
      },
    );
    if (picked != null && mounted) {
      _change(() => _chart = picked.isEmpty ? null : picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final window = TrendWindow.containing(_anchor, _range);
    final now = widget.now ?? DateTime.now();
    final summary = summarizeTrends(
        widget.plays,
        window,
        TrendFilter(
            mode: _mode,
            level: _level,
            chart: _chart,
            venueId: _venue,
            cabinetId: _cabinet,
            side: _side),
        _metric);
    final scheme = Theme.of(context).colorScheme;
    final dates = MaterialLocalizations.of(context);
    String date(DateTime d) => dates.formatMediumDate(d);
    final end = DateTime(window.end.year, window.end.month, window.end.day - 1);
    final levels = widget.plays
        .where((p) => _mode == null || p.play.mode == _mode)
        .map((p) => p.level)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    final venues = {
      for (final c in widget.cabinets.values) c.venueId: c.venueName
    };
    final cabs = widget.cabinets.values
        .where((c) => _venue == null || c.venueId == _venue)
        .toList();
    final chartTitle = widget.plays.where((p) => p.chart == _chart).firstOrNull;
    final selected = _selected == null ? null : summary.samples[_selected!];
    final delta = summary.comparison;
    final improving = delta != null && delta > 0;
    final first = widget.plays
        .map((p) => p.play.playedAt)
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    return ListView(
      padding: clearOfBars(context, const EdgeInsets.all(16)),
      children: [
        SegmentedButton<TrendRange>(
          segments: const [
            ButtonSegment(value: TrendRange.week, label: Text('Week')),
            ButtonSegment(
                value: TrendRange.fortnight, label: Text('Fortnight')),
            ButtonSegment(value: TrendRange.month, label: Text('Month'))
          ],
          selected: {_range},
          showSelectedIcon: false,
          onSelectionChanged: (s) => _change(() => _range = s.first),
        ),
        const SizedBox(height: 12),
        Row(children: [
          IconButton(
              tooltip: 'Previous period',
              icon: const Icon(Icons.chevron_left),
              onPressed: first == null || !first.isBefore(window.start)
                  ? null
                  : () => _change(() => _anchor = window.shift(-1).start)),
          Expanded(
              child: Text('${date(window.start)} – ${date(end)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall)),
          IconButton(
              tooltip: 'Next period',
              icon: const Icon(Icons.chevron_right),
              onPressed: !window.end.isBefore(now)
                  ? null
                  : () => _change(() => _anchor = window.shift(1).start)),
        ]),
        if (!window.contains(now))
          Align(
              alignment: Alignment.center,
              child: TextButton(
                  onPressed: () => _change(() => _anchor = now),
                  child: const Text('Today'))),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<TrendMetric>(
                          segments: const [
                            ButtonSegment(
                                value: TrendMetric.score, label: Text('Score')),
                            ButtonSegment(
                                value: TrendMetric.timing,
                                label: Text('Timing variation'))
                          ],
                          selected: {
                            _metric
                          },
                          showSelectedIcon: false,
                          onSelectionChanged: (s) =>
                              _change(() => _metric = s.first)),
                      const SizedBox(height: 20),
                      Text(
                          selected == null
                              ? 'VS PREVIOUS PERIOD'
                              : date(selected.day).toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 4),
                      Text(
                          selected != null
                              ? selected.value == null
                                  ? 'No data'
                                  : _format(selected.value!,
                                      signed: _metric == TrendMetric.score)
                              : delta == null
                                  ? 'Building history'
                                  : '${_format(delta.abs())} ${delta == 0 ? 'unchanged' : improving ? 'better' : 'worse'}',
                          style: FloorPop.readout(28,
                              color: selected == null && delta != null
                                  ? delta == 0
                                      ? scheme.onSurface
                                      : improving
                                          ? FloorPop.of(context).up
                                          : FloorPop.of(context).down
                                  : scheme.onSurface)),
                      Text(
                          selected != null
                              ? '${selected.plays} plays · ${_metric == TrendMetric.score ? 'score vs chart reference' : 'average variation; lower is better'}'
                              : delta == null
                                  ? 'Play the same chart in both periods to compare.'
                                  : '${summary.comparedCharts} shared charts · equal weight per chart',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12)),
                      const SizedBox(height: 24),
                      if (summary.samples.every((s) => s.value == null))
                        SizedBox(
                            height: 180,
                            child: Center(
                                child: Text(
                                    summary.current.isEmpty
                                        ? 'No plays in this period with these filters.'
                                        : _metric == TrendMetric.timing
                                            ? 'Log result-screen timing to track consistency.'
                                            : 'Play these charts on another day to start a trend.',
                                    textAlign: TextAlign.center)))
                      else
                        SizedBox(height: 200, child: _plot(summary, scheme)),
                      const SizedBox(height: 12),
                      Text(
                          _metric == TrendMetric.score
                              ? 'Daily score vs earlier averages on the same charts. New repeated charts use their first day as zero. Higher is better; failed plays are excluded.'
                              : 'Daily timing variation in ms. Lower is more consistent, even when scores stay flat. Only logged timing counts.',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12)),
                      const SizedBox(height: 16),
                      Wrap(spacing: 16, runSpacing: 8, children: [
                        Text('${summary.current.length} plays'),
                        Text(
                            '${summary.current.map((p) => p.visitKey).toSet().length} sets'),
                        Text(summary.ratedSets == 0
                            ? 'No rated sets'
                            : '${summary.goodSets}/${summary.ratedSets} good sets'),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                          'Good set: at or above earlier chart averages, using cleared scores. '
                          'Only charts with earlier scores count; timing is tracked separately.',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant)),
                    ]))),
        const SizedBox(height: 16),
        Text('Focus', style: Theme.of(context).textTheme.titleMedium),
        Wrap(spacing: 12, runSpacing: 4, children: [
          _picker<Modes>(
              'Mode',
              _mode,
              {
                for (final m in Modes.values)
                  m: m == Modes.singles ? 'SP' : 'DP'
              },
              (v) => _change(() {
                    _mode = v;
                    _level = null;
                    _chart = null;
                  })),
          _picker<int>(
              'Level',
              _level,
              {for (final l in levels) l: '$l'},
              (v) => _change(() {
                    _level = v;
                    _chart = null;
                  })),
        ]),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(chartTitle?.play.title ?? 'All charts'),
            subtitle: chartTitle == null
                ? const Text('Choose a chart to track it over time')
                : Text(
                    '${chartTitle.play.mode == Modes.singles ? 'SP' : 'DP'} · ${chartTitle.play.difficulty}'),
            trailing: const Icon(Icons.search),
            onTap: _pickChart),
        const SizedBox(height: 8),
        Text('Where you played',
            style: Theme.of(context).textTheme.titleMedium),
        Wrap(spacing: 12, runSpacing: 4, children: [
          _picker<int>(
              'Venue',
              _venue,
              venues,
              (v) => _change(() {
                    _venue = v;
                    _cabinet = null;
                  })),
          _picker<int>(
              'Cabinet',
              _cabinet,
              {
                for (final c in cabs)
                  c.id: c.name.isEmpty ? c.venueName : c.label
              },
              (v) => _change(() => _cabinet = v)),
          _picker<PadSide>(
              'Side',
              _side,
              const {PadSide.p1: '1P', PadSide.p2: '2P'},
              (v) => _change(() => _side = v)),
        ]),
        const Text(
            'Plays without a logged venue or credit appear in All. Cab and side filters require an assigned credit or timing.',
            style: TextStyle(fontSize: 12)),
        if (_mode != null ||
            _level != null ||
            _chart != null ||
            _venue != null ||
            _cabinet != null ||
            _side != null)
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: () => _change(() {
                        _mode = null;
                        _level = null;
                        _chart = null;
                        _venue = null;
                        _cabinet = null;
                        _side = null;
                      }),
                  child: const Text('Reset filters'))),
      ],
    );
  }

  String _format(double value, {bool signed = false}) =>
      '${signed && value >= 0 ? '+' : ''}${_metric == TrendMetric.score ? value.round() : value.toStringAsFixed(1)}${_metric == TrendMetric.timing ? ' ms' : ' pts'}';

  Widget _picker<T>(String label, T? value, Map<T, String> choices,
          ValueChanged<T?> onChanged) =>
      SizedBox(
          width: 160,
          child: DropdownButtonFormField<T>(
              key: ValueKey((label, value)),
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
              items: [
                DropdownMenuItem<T>(value: null, child: const Text('All')),
                for (final e in choices.entries)
                  DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis))
              ],
              onChanged: onChanged));

  Widget _plot(TrendSummary summary, ColorScheme scheme) {
    final samples = summary.samples;
    final values = samples.map((s) => s.value).whereType<double>().toList();
    final low = values.reduce(math.min), high = values.reduce(math.max);
    final pad = math.max(
        _metric == TrendMetric.score ? 1000.0 : 1.0, (high - low) * .2);
    final minY = _metric == TrendMetric.score
        ? math.min(0.0, low - pad)
        : math.max(0.0, low - pad);
    final maxY =
        _metric == TrendMetric.score ? math.max(0.0, high + pad) : high + pad;
    // Missing days break the line rather than implying activity on rest days.
    final groups = <List<FlSpot>>[];
    var gap = true;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].value;
      if (v == null) {
        gap = true;
        continue;
      }
      if (gap) groups.add([]);
      groups.last.add(FlSpot(i.toDouble(), v));
      gap = false;
    }
    return LineChart(LineChartData(
      minX: 0,
      maxX: (samples.length - 1).toDouble(),
      minY: minY,
      maxY: maxY,
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(drawVerticalLine: false),
      extraLinesData: ExtraLinesData(horizontalLines: [
        if (_metric == TrendMetric.score)
          HorizontalLine(
              y: 0,
              color: scheme.onSurfaceVariant,
              dashArray: [4, 4],
              strokeWidth: 1)
      ]),
      titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (v, meta) => Text(
                      _metric == TrendMetric.score
                          ? '${(v / 1000).round()}k'
                          : v.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 10)))),
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: _range == TrendRange.week
                      ? 1
                      : _range == TrendRange.fortnight
                          ? 2
                          : 5,
                  getTitlesWidget: (v, meta) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          '${samples[v.round().clamp(0, samples.length - 1)].day.day}',
                          style: const TextStyle(fontSize: 10)))))),
      lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: scheme.surfaceContainerHighest,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                    '${MaterialLocalizations.of(context).formatMediumDate(samples[spot.x.round()].day)}\n${_format(spot.y, signed: _metric == TrendMetric.score)}',
                    TextStyle(
                        color: scheme.onSurface, fontWeight: FontWeight.w600)),
            ],
          ),
          touchCallback: (event, response) {
            if (event is FlTapUpEvent &&
                response?.lineBarSpots?.isNotEmpty == true) {
              setState(
                  () => _selected = response!.lineBarSpots!.first.x.round());
            }
          }),
      lineBarsData: [
        for (final spots in groups)
          LineChartBarData(
              spots: spots,
              isCurved: false,
              color: scheme.primary,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                  show: true, color: scheme.primary.withValues(alpha: .08)))
      ],
    ));
  }
}
