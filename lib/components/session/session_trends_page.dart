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
import 'package:ddr_md/helpers.dart' show formatScore;
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
    final first = widget.plays
        .map((p) => p.play.playedAt)
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    return ListView(
      padding: clearOfBars(context, const EdgeInsets.all(16)),
      children: [
        PillTabs<TrendRange>(
          values: TrendRange.values,
          tabs: const [Text('Week'), Text('Fortnight'), Text('Month')],
          selected: _range,
          onChanged: (range) => _change(() => _range = range),
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
        BeatIn(child: _hero(summary, selected)),
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

  Widget _hero(TrendSummary summary, TrendSample? selected) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    final delta = summary.comparison;
    final score = _metric == TrendMetric.score;
    final colour = selected != null && selected.value != null
        ? score
            ? (selected.value! >= 0 ? pop.up : pop.down)
            : FloorPop.grape
        : delta == null || delta == 0
            ? pop.voltText
            : delta > 0
                ? pop.up
                : pop.down;
    final status = selected != null
        ? 'DAY DETAIL'
        : delta == null
            ? 'BUILDING'
            : delta == 0
                ? 'STEADY'
                : delta > 0
                    ? 'IMPROVING'
                    : 'BELOW PRIOR';
    final value = selected?.value ?? delta;
    final number = value == null
        ? '—'
        : score
            ? '${value >= 0 ? '+' : '−'}${formatScore(value.abs().round())}'
            : '${selected == null && value > 0 ? '−' : selected == null && value < 0 ? '+' : ''}${value.abs().toStringAsFixed(1)}';
    final caption = selected != null
        ? MaterialLocalizations.of(context)
            .formatMediumDate(selected.day)
            .toUpperCase()
        : 'VS PREVIOUS ${_range == TrendRange.week ? 'WEEK' : _range == TrendRange.fortnight ? 'FORTNIGHT' : 'MONTH'}';
    final hasData = summary.samples.any((s) => s.value != null);
    return Material(
      color: pop.stage,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: pop.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          decoration: pop.stripes(color: pop.stage),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Text(score ? 'SCORE TREND' : 'TIMING TREND',
                      style: pop.label)),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                      color: colour.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        delta != null && delta > 0
                            ? Icons.north_east
                            : delta != null && delta < 0
                                ? Icons.south_east
                                : Icons.insights,
                        size: 14,
                        color: colour),
                    const SizedBox(width: 5),
                    Text(status,
                        style: pop.label.copyWith(
                            color: colour, fontSize: 9, letterSpacing: .7)),
                  ])),
            ]),
            const SizedBox(height: 14),
            Align(
                alignment: Alignment.centerLeft,
                child: BeatSwap(
                    child: Text(number,
                        key: ValueKey((_metric, _selected, number)),
                        style: FloorPop.readout(46, color: colour)))),
            const SizedBox(height: 4),
            Text('${score ? 'POINTS' : 'MS VARIATION'} · $caption',
                style: pop.label.copyWith(fontSize: 9, letterSpacing: .8)),
            const SizedBox(height: 7),
            Text(
                selected != null
                    ? '${selected.plays} plays · ${score ? 'score vs chart reference' : 'lower is tighter'}'
                    : delta == null
                        ? 'Repeat a chart across periods to compare.'
                        : '${summary.comparedCharts} shared charts · compared like for like',
                style: TextStyle(fontSize: 11, color: pop.haze)),
            if (selected != null)
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                      onPressed: () => setState(() => _selected = null),
                      child: const Text('Period summary'))),
          ]),
        ),
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
            child: PillTabs<TrendMetric>(
                values: TrendMetric.values,
                tabs: const [Text('Score'), Text('Timing variation')],
                selected: _metric,
                onChanged: (metric) => _change(() => _metric = metric))),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Column(children: [
              if (hasData)
                SizedBox(height: 180, child: _plot(summary, scheme))
              else
                SizedBox(
                    height: 144,
                    child: Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(score ? Icons.stacked_bar_chart : Icons.graphic_eq,
                          size: 40, color: pop.haze.withValues(alpha: .6)),
                      const SizedBox(height: 12),
                      Text(
                          summary.current.isEmpty
                              ? 'No plays in this period with these filters.'
                              : score
                                  ? 'Play these charts on another day to start a trend.'
                                  : 'Log result-screen timing to track consistency.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: pop.haze, fontSize: 12)),
                    ]))),
              if (hasData) ...[
                const SizedBox(height: 8),
                _dayStrip(summary),
              ],
              const SizedBox(height: 10),
              Row(children: [
                _legend(score ? pop.up : FloorPop.grape,
                    score ? 'Above reference' : 'Variation · ms'),
                const SizedBox(width: 14),
                if (score) _legend(pop.down, 'Below'),
                const Spacer(),
                Text(score ? 'HIGHER ↑' : 'LOWER ↓',
                    style: pop.label.copyWith(fontSize: 8, letterSpacing: .6)),
              ]),
              const SizedBox(height: 18),
              Row(spacing: 6, children: [
                _stat('PLAYS', '${summary.current.length}', scheme.primary,
                    Icons.play_arrow_rounded),
                _stat(
                    'SETS',
                    '${summary.current.map((p) => p.visitKey).toSet().length}',
                    FloorPop.grape,
                    Icons.layers_outlined),
                _stat(
                    'GOOD SETS',
                    summary.ratedSets == 0
                        ? '—'
                        : '${summary.goodSets}/${summary.ratedSets}',
                    pop.up,
                    Icons.north_east),
              ]),
              const SizedBox(height: 12),
              Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text('How this is measured',
                        style: TextStyle(fontSize: 11, color: pop.haze)),
                    children: [
                      Text(
                          score
                              ? 'Daily score vs earlier averages on the same charts. New repeated charts use their first day as zero. Failed plays are excluded. A good set meets or beats its earlier chart averages.'
                              : 'Daily timing variation in ms. Lower is more consistent, even when scores stay flat. Only logged timing counts. Good sets are measured using cleared scores.',
                          style: TextStyle(fontSize: 11, color: pop.haze))
                    ],
                  )),
            ])),
      ]),
    );
  }

  Widget _dayStrip(TrendSummary summary) {
    final pop = FloorPop.of(context);
    return Row(spacing: 3, children: [
      for (final (i, sample) in summary.samples.indexed)
        Expanded(
            child: Tooltip(
          message:
              '${MaterialLocalizations.of(context).formatMediumDate(sample.day)} · ${sample.value == null ? 'No comparable data' : _format(sample.value!, signed: _metric == TrendMetric.score)}',
          child: Semantics(
            key: ValueKey('trend-day-$i'),
            button: sample.value != null,
            selected: _selected == i,
            label:
                '${MaterialLocalizations.of(context).formatMediumDate(sample.day)}: ${sample.value == null ? 'no comparable data' : _format(sample.value!, signed: _metric == TrendMetric.score)}',
            child: InkWell(
              onTap: sample.value == null
                  ? null
                  : () => setState(() => _selected = i),
              borderRadius: BorderRadius.circular(3),
              child: Ink(
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: sample.value == null
                        ? pop.riser
                        : (_metric == TrendMetric.timing
                                ? FloorPop.grape
                                : sample.value! >= 0
                                    ? pop.up
                                    : pop.down)
                            .withValues(alpha: .65),
                    border: _selected == i
                        ? Border.all(
                            color: Theme.of(context).colorScheme.onSurface)
                        : null,
                  )),
            ),
          ),
        )),
    ]);
  }

  Widget _legend(Color colour, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: colour, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(fontSize: 9, color: FloorPop.of(context).haze)),
      ]);

  Widget _stat(String label, String value, Color colour, IconData icon) =>
      Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
            color: colour.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(height: 5),
          FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: FloorPop.readout(26, color: colour))),
          const SizedBox(height: 4),
          Text(label,
              style: FloorPop.of(context)
                  .label
                  .copyWith(fontSize: 8, letterSpacing: .7)),
        ]),
      ));

  Widget _plot(TrendSummary summary, ColorScheme scheme) {
    final pop = FloorPop.of(context);
    final score = _metric == TrendMetric.score;
    final samples = summary.samples;
    final values = samples.map((s) => s.value).whereType<double>().toList();
    final low = values.reduce(math.min), high = values.reduce(math.max);
    final pad = math.max(score ? 1000.0 : 1.0, (high - low) * .2);
    final span =
        math.max(1.0, high + pad - (score ? math.min(0.0, low - pad) : 0.0));
    final magnitude =
        math.pow(10, (math.log(span / 4) / math.ln10).floor()).toDouble();
    final step =
        [1, 2, 5, 10].firstWhere((n) => n * magnitude >= span / 4) * magnitude;
    final minY = score ? (math.min(0.0, low - pad) / step).floor() * step : 0.0;
    final maxY = (math.max(0.0, high + pad) / step).ceil() * step;
    String tick(double value) => score
        ? value == 0
            ? '0'
            : step < 1000
                ? formatScore(value.round())
                : '${value < 0 ? '−' : ''}${(value.abs() / 1000).round()}k'
        : value.toStringAsFixed(step < 1 ? 1 : 0);
    return LayoutBuilder(
        builder: (context, box) => BarChart(
            BarChartData(
              minY: minY,
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  getDrawingHorizontalLine: (value) => FlLine(
                      color: pop.line.withValues(alpha: .6), strokeWidth: 1)),
              extraLinesData: ExtraLinesData(horizontalLines: [
                if (score)
                  HorizontalLine(
                      y: 0,
                      color: pop.haze.withValues(alpha: .7),
                      strokeWidth: 1,
                      dashArray: [3, 4])
              ]),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: step,
                        getTitlesWidget: (value, meta) => Text(tick(value),
                            style: TextStyle(fontSize: 9, color: pop.haze)))),
                bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        getTitlesWidget: (value, meta) {
                          final i = value.round();
                          if (i < 0 ||
                              i >= samples.length ||
                              (_range == TrendRange.fortnight && i.isOdd) ||
                              (_range == TrendRange.month && i % 5 != 0)) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text('${samples[i].day.day}',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: _selected == i
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: _selected == i
                                          ? scheme.onSurface
                                          : pop.haze)));
                        })),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  tooltipBgColor: pop.riser,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => samples[
                                  group.x]
                              .value ==
                          null
                      ? null
                      : BarTooltipItem(
                          '${MaterialLocalizations.of(context).formatMediumDate(samples[group.x].day)}\n${_format(rod.toY, signed: score)}',
                          TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600)),
                ),
                touchCallback: (event, response) {
                  if (event is FlTapUpEvent && response?.spot != null) {
                    final i = response!.spot!.touchedBarGroup.x;
                    if (samples[i].value != null) setState(() => _selected = i);
                  }
                },
              ),
              barGroups: [
                for (var i = 0; i < samples.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: samples[i].value ?? 0,
                      width: ((box.maxWidth - 32) / samples.length * .58)
                          .clamp(3.0, 24.0),
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            (score
                                    ? samples[i].value != null &&
                                            samples[i].value! < 0
                                        ? pop.down
                                        : pop.up
                                    : FloorPop.grape)
                                .withValues(alpha: .45),
                            score
                                ? samples[i].value != null &&
                                        samples[i].value! < 0
                                    ? pop.down
                                    : pop.up
                                : FloorPop.grape,
                          ]),
                      borderSide: _selected == i
                          ? BorderSide(color: scheme.onSurface, width: 1.5)
                          : BorderSide.none,
                    ),
                  ]),
              ],
            ),
            swapAnimationDuration: FloorPop.eighth));
  }
}
