/// Name: SessionTrendsPage
/// Parent: SessionPage, SessionsPage
/// Description: Trends as one page per week, read against your usual on the
/// same charts: the week and the seven before it, its days and biggest
/// upscore, each cab side's form with the lamps you gave it, each level,
/// timing and goals. Swipe or use the arrows to change week; SP/DP sits in
/// the header and the other filters in a sheet behind it.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/play_style_icon.dart';
import 'package:ddr_md/components/session/goal_card.dart';
import 'package:ddr_md/components/session/pad_check.dart';
import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/session/session_page.dart' show signedMs;
import 'package:ddr_md/components/session/session_summary.dart'
    show LevelGapBars, vsUsual;
import 'package:ddr_md/components/session/visits.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/song_search_sheet.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart' show formatScore;
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/models/session_goal.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/session_trends.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

class SessionTrendsPage extends StatefulWidget {
  const SessionTrendsPage({super.key});

  @override
  State<SessionTrendsPage> createState() => _SessionTrendsPageState();
}

class _SessionTrendsPageState extends State<SessionTrendsPage> {
  Future<VisitData>? _visits;
  Future<TrendSources>? _sources;

  static Future<TrendSources> _load(VisitData data) async {
    final cabinets = {
      for (final list in data.credits.values)
        for (final c in list) c.cabinet.id: c.cabinet
    };
    return (
      plays: trendPlays(data.visits, data.timing, data.credits, data.model),
      model: data.model,
      cabinets: cabinets,
      ratings: [
        for (final venue in {for (final c in cabinets.values) c.venueId})
          ...await DatabaseProvider.getVenuePadRatings(venue)
      ],
      gains: data.gains,
      goals: data.goals,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visits = visitsFor(context);
    if (!identical(visits, _visits)) {
      _visits = visits;
      _sources = visits.then(_load);
    }
    return FutureBuilder<TrendSources>(
      future: _sources,
      builder: (context, snapshot) {
        if (snapshot.data case final sources?) {
          return SessionTrendsView(sources: sources);
        }
        return HomeSubpage(
          title: 'Trends',
          body: Center(
              child: snapshot.hasError
                  ? const Text('Could not load trends. Reopen to try again.')
                  : const CircularProgressIndicator()),
        );
      },
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

/// "Nov 2–8", "Oct 26 – Nov 1".
String weekRange(TrendWindow w) {
  final end = DateTime(w.end.year, w.end.month, w.end.day - 1);
  final from = '${_months[w.start.month - 1]} ${w.start.day}';
  return w.start.month == end.month
      ? '$from–${end.day}'
      : '$from – ${_months[end.month - 1]} ${end.day}';
}

/// Data is supplied separately so week changes and filters need no re-query.
class SessionTrendsView extends StatefulWidget {
  const SessionTrendsView({super.key, required this.sources, this.now});
  final TrendSources sources;
  final DateTime? now;

  @override
  State<SessionTrendsView> createState() => _SessionTrendsViewState();
}

class _SessionTrendsViewState extends State<SessionTrendsView> {
  DateTime get _now => widget.now ?? DateTime.now();
  late TrendWindow _week = TrendWindow.containing(_now);
  late TrendFilter _filter = TrendFilter(
      mode: widget.sources.plays.any((p) => p.play.mode == Modes.singles) ||
              !widget.sources.plays.any((p) => p.play.mode == Modes.doubles)
          ? Modes.singles
          : Modes.doubles);
  TrendHistory? _history;
  PadSideId? _open;

  TrendHistory get history {
    final h = _history;
    if (h != null &&
        identical(h.sources, widget.sources) &&
        identical(h.filter, _filter)) {
      return h;
    }
    return _history = TrendHistory(widget.sources, _filter);
  }

  @override
  void didUpdateWidget(SessionTrendsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A sync or deleted visit can remove the last option in a picker.
    final f = _filter, plays = widget.sources.plays;
    final cabinets = widget.sources.cabinets;
    _filter = TrendFilter(
      mode: f.mode,
      level: plays.any((p) => p.level == f.level) ? f.level : null,
      chart: plays.any((p) => p.chart == f.chart) ? f.chart : null,
      venueId:
          cabinets.values.any((c) => c.venueId == f.venueId) ? f.venueId : null,
      cabinetId: cabinets.containsKey(f.cabinetId) ? f.cabinetId : null,
      side: f.side,
    );
  }

  TrendWindow get _current => TrendWindow.containing(_now);

  void _move(int weeks) {
    final next = _week.shift(weeks);
    if (next.start.isAfter(_now)) return;
    setState(() => _week = next);
  }

  Future<void> _showFilters() async {
    final picked = await showModalBottomSheet<TrendFilter>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TrendFiltersSheet(
          plays: widget.sources.plays,
          cabinets: widget.sources.cabinets,
          initial: _filter),
    );
    if (picked != null && mounted) setState(() => _filter = picked);
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final labels =
        _filterLabels(_filter, widget.sources.plays, widget.sources.cabinets);
    final mode = _filter.mode;
    final current = _current;
    // Recent weeks keep the same eight bars; further back, the bars end at
    // the week shown.
    final last = _week.start.isAfter(current.shift(-kTrendWeeks).start)
        ? current
        : _week;
    final span = history.span(last);
    final week = history.week(_week);
    final before = history.week(_week.shift(-1));
    return HomeSubpage(
      title: 'Trends',
      actions: [
        Tooltip(
          message: 'Switch to ${mode == Modes.singles ? 'doubles' : 'singles'}',
          child: InkWell(
            key: const ValueKey('trend-mode'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _filter = TrendFilter(
                mode: mode == Modes.singles ? Modes.doubles : Modes.singles,
                venueId: _filter.venueId,
                cabinetId: _filter.cabinetId,
                side: _filter.side)),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                  color: pop.riser, borderRadius: BorderRadius.circular(12)),
              child: PlayStyleIcon(mode: mode, height: 14),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('trend-filters'),
          tooltip: labels.isEmpty ? 'Filters' : 'Filters (${labels.length})',
          onPressed: _showFilters,
          icon: Badge(
              isLabelVisible: labels.isNotEmpty,
              label: Text('${labels.length}'),
              child: const Icon(Icons.tune_rounded)),
        ),
        const SizedBox(width: 4),
      ],
      body: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() > 300) _move(v < 0 ? 1 : -1);
        },
        // Under the Scaffold, so the padding clears its app bar.
        child: Builder(
            builder: (context) => ListView(
                  padding: clearOfBars(
                      context, const EdgeInsets.fromLTRB(16, 8, 16, 32)),
                  children: [
                    _header(current),
                    if (labels.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text.rich(
                            TextSpan(children: [
                              for (final (i, l) in labels.indexed) ...[
                                if (i > 0) const TextSpan(text: ' · '),
                                // The level in its numeral, not as text.
                                if (l == 'Level ${_filter.level}')
                                  WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: LevelNumber(
                                          level: _filter.level!,
                                          difficulty: 'EXPERT',
                                          height: 14))
                                else
                                  TextSpan(text: l),
                              ],
                            ]),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: pop.haze)),
                      ),
                    const SizedBox(height: 12),
                    _hero(week, before),
                    const SizedBox(height: 12),
                    _weeks(span),
                    const SizedBox(height: 12),
                    _days(week),
                    ..._sides(span),
                    if (week.levels.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _levels(week, before),
                    ],
                    if (span.any((w) => w.spreadMs != null)) ...[
                      const SizedBox(height: 12),
                      _timing(span, week, before),
                    ],
                    if (history.goals(_week) case final goals
                        when goals.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _goals(goals),
                    ],
                  ],
                )),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    final pop = FloorPop.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
          color: pop.stage,
          border: Border.all(color: pop.line),
          borderRadius: BorderRadius.circular(20)),
      child: child,
    );
  }

  Widget _labelRow(String label, [String? trailing]) {
    final pop = FloorPop.of(context);
    return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(label, style: pop.label)),
          if (trailing != null)
            Text(trailing, style: TextStyle(fontSize: 12, color: pop.haze)),
        ]);
  }

  Widget _header(TrendWindow current) {
    final pop = FloorPop.of(context);
    final ago = current.start.difference(_week.start).inDays ~/ 7;
    final empty = history.week(_week).plays.isEmpty;
    final note = switch (ago) {
      0 => empty ? 'This week · nothing played yet' : 'This week',
      1 => 'Last week',
      _ => '$ago weeks ago',
    };
    final year = _week.start.year == _now.year ? '' : ' · ${_week.start.year}';
    Widget arrow(String tip, IconData icon, VoidCallback? onPressed) =>
        IconButton.filledTonal(
          tooltip: tip,
          onPressed: onPressed,
          icon: Icon(icon, size: 22),
          style: IconButton.styleFrom(
            backgroundColor: pop.riser,
            minimumSize: const Size(44, 44),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
    return Row(children: [
      arrow('Previous week', Icons.chevron_left_rounded, () => _move(-1)),
      Expanded(
        child: Column(children: [
          Text(weekRange(_week),
              key: const ValueKey('trend-week'),
              textAlign: TextAlign.center,
              style: FloorPop.display(18)),
          const SizedBox(height: 3),
          Text('$note$year',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: pop.haze)),
        ]),
      ),
      arrow('Next week', Icons.chevron_right_rounded,
          ago == 0 ? null : () => _move(1)),
    ]);
  }

  Color _tone(double? v) {
    final pop = FloorPop.of(context);
    return v == null
        ? pop.haze
        : v < 0
            ? pop.down
            : pop.up;
  }

  Widget _hero(TrendWeek week, TrendWeek before) {
    final pop = FloorPop.of(context);
    final gap = week.gap, was = before.gap;
    final delta = gap == null || was == null ? null : gap - was;
    Widget stat(String label, int value, Color? colour) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: pop.riser, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text('$value', style: FloorPop.readout(18, color: colour)),
              const SizedBox(height: 3),
              Text(label,
                  style: pop.label.copyWith(fontSize: 9, letterSpacing: 1)),
            ]),
          ),
        );
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          container: true,
          label: gap == null
              ? 'No scores against your usual this week'
              : '${vsUsual(gap)} vs your usual',
          excludeSemantics: true,
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(gap == null ? '—' : vsUsual(gap),
                        style: FloorPop.readout(40, color: _tone(gap))),
                  ),
                ),
                const SizedBox(width: 8),
                Text('vs your usual',
                    style: TextStyle(fontSize: 13, color: pop.haze)),
              ]),
        ),
        const SizedBox(height: 6),
        Text(
            delta == null
                ? 'No week before to compare'
                : '${delta >= 0 ? '↑' : '↓'} ${vsUsual(delta.abs()).replaceFirst('+', '')} on the week before',
            style: TextStyle(fontSize: 13, color: _tone(delta))),
        const SizedBox(height: 12),
        Row(spacing: 6, children: [
          stat('SESSIONS', week.sessions, null),
          stat('PLAYS', week.plays.length, null),
          stat('UPSCORES', week.upscores, pop.sunText),
          stat('CARDS', week.cards, pop.voltText),
        ]),
      ]),
    );
  }

  Widget _weeks(List<TrendWeek> span) {
    final pop = FloorPop.of(context);
    final most = math.max(
        5000.0, span.map((w) => w.gap?.abs() ?? 0).fold(0.0, math.max));
    const half = 50.0;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _labelRow('LAST 8 WEEKS', 'vs your usual'),
        const SizedBox(height: 8),
        SizedBox(
          height: half * 2 + 10,
          child: Stack(children: [
            Positioned(
                left: 0,
                right: 0,
                top: half + 4,
                child: Container(height: 1.5, color: pop.line)),
            Row(spacing: 4, children: [
              for (final w in span) Expanded(child: _weekBar(w, most, half)),
            ]),
          ]),
        ),
        const SizedBox(height: 4),
        Row(spacing: 4, children: [
          for (final w in span)
            Expanded(
              child: Text('${w.window.start.day}/${w.window.start.month}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          w.window == _week ? FontWeight.w700 : FontWeight.w400,
                      color: w.window == _week ? pop.voltText : pop.haze)),
            ),
        ]),
      ]),
    );
  }

  Widget _weekBar(TrendWeek w, double most, double half) {
    final gap = w.gap;
    final picked = w.window == _week;
    final h = gap == null ? 4.0 : math.max(4.0, gap.abs() / most * half);
    final colour = gap == null ? FloorPop.of(context).line : _tone(gap);
    final bar = Lean(
      child: Container(
        width: double.infinity,
        height: h,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: picked ? colour : colour.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(4),
          border: picked ? Border.all(color: FloorPop.volt, width: 2) : null,
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: picked,
      label:
          '${weekRange(w.window)}: ${gap == null ? 'no scores' : '${vsUsual(gap)} vs your usual'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _week = w.window),
        child: Column(children: [
          SizedBox(
              height: half + 4,
              child: Align(
                  alignment: Alignment.bottomCenter,
                  child: gap == null || gap >= 0 ? bar : null)),
          const SizedBox(height: 1.5),
          SizedBox(
              height: half + 4.5,
              child: Align(
                  alignment: Alignment.topCenter,
                  child: gap != null && gap < 0 ? bar : null)),
        ]),
      ),
    );
  }

  Widget _days(TrendWeek week) {
    final pop = FloorPop.of(context);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final days = week.days;
    final played = {for (final p in week.plays) trendDay(p.play.playedAt)};
    final biggest = week.biggest;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _labelRow(_week == _current ? 'THIS WEEK' : 'THE WEEK'),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var i = 0; i < 7; i++)
            () {
              final day = DateTime(
                  _week.start.year, _week.start.month, _week.start.day + i);
              final v = days[i];
              return Semantics(
                label:
                    '${names[i]}: ${v != null ? '${vsUsual(v)} vs your usual' : played.contains(day) ? 'played' : 'not played'}',
                excludeSemantics: true,
                child: SizedBox(
                  width: 36,
                  child: Column(children: [
                    SizedBox(
                      height: 16,
                      child: Center(
                        child: v == null && !played.contains(day)
                            ? Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: pop.line, width: 1.5)))
                            : Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: v == null ? pop.haze : _tone(v))),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(names[i],
                        style: TextStyle(fontSize: 11, color: pop.haze)),
                  ]),
                ),
              );
            }(),
        ]),
        if (biggest != null) ...[
          const SizedBox(height: 14),
          Divider(height: 1, color: pop.line),
          const SizedBox(height: 12),
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                  width: 40,
                  height: 40,
                  child: SongArtwork(
                      songName:
                          biggest.play.play.song ?? biggest.play.play.konamiId,
                      title: biggest.play.play.title)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Biggest upscore',
                        style: TextStyle(fontSize: 12, color: pop.haze)),
                    const SizedBox(height: 2),
                    Text(biggest.play.play.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    DifficultyLabel(
                        difficulty: biggest.play.play.difficulty,
                        level: biggest.play.level,
                        height: 12),
                  ]),
            ),
            const SizedBox(width: 8),
            Text('+${formatScore(biggest.gain)}',
                style: FloorPop.readout(16, color: pop.sunText)),
          ]),
        ],
      ]),
    );
  }

  String _sideName(PadSideId id) {
    final c = widget.sources.cabinets[id.$1];
    if (c == null) return sideName(id.$2);
    return '${c.venueName} · ${padSideLabel(c, id.$2)}';
  }

  List<Widget> _sides(List<TrendWeek> span) {
    final pop = FloorPop.of(context);
    final sides = history.sides(span);
    if (sides.isEmpty) return const [];
    final regular = [
      for (final s in sides)
        if (s.weeks >= 2) s
    ];
    final other = [
      for (final s in sides)
        if (s.weeks < 2) s
    ];
    Widget rows(List<({PadSideId id, int sessions, int weeks})> list) =>
        Column(children: [
          for (final (i, s) in list.indexed) ...[
            if (i > 0) Divider(height: 1, color: pop.line),
            _sideRow(span, s.id, s.sessions,
                most: identical(list, regular) && i == 0 && list.length > 1),
          ],
        ]);
    return [
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _labelRow('PADS AND SIDES · 8 WEEKS', 'vs your usual'),
      ),
      const SizedBox(height: 8),
      _card(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (regular.isNotEmpty) rows(regular),
          if (other.isNotEmpty) ...[
            if (regular.isNotEmpty) Divider(height: 1, color: pop.line),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 2),
              child: Text('OTHER PADS', style: pop.label),
            ),
            rows(other),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text(
            'Lamps are your pad check that week (the latest if there were '
            'several); a dashed slot means you didn\'t rate it.',
            style: TextStyle(fontSize: 12, color: pop.haze, height: 1.4)),
      ),
    ];
  }

  Widget _sideRow(List<TrendWeek> span, PadSideId id, int sessions,
      {required bool most}) {
    final pop = FloorPop.of(context);
    final gaps = [for (final w in span) w.sideGap(id)];
    final lamps = [for (final w in span) history.lamp(id, w.window)];
    final upTo = span.indexWhere((w) => w.window == _week);
    final latest = [
      for (var i = 0; i < gaps.length; i++)
        if (gaps[i] != null && (upTo < 0 || i <= upTo)) gaps[i]!
    ].lastOrNull;
    final open = _open == id;
    final scale =
        math.max(5000.0, gaps.map((g) => g?.abs() ?? 0).fold(0.0, math.max));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => setState(() => _open = open ? null : id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_sideName(id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                          '$sessions session${sessions == 1 ? '' : 's'}${most ? ' · most played' : ''}',
                          style: TextStyle(fontSize: 12, color: pop.haze)),
                    ]),
              ),
              const SizedBox(width: 8),
              CustomPaint(
                size: const Size(84, 28),
                painter: _FormLine(gaps,
                    scale: scale,
                    colour: _tone(latest),
                    baseline: pop.line,
                    inset: 3,
                    stroke: 2),
              ),
              SizedBox(
                width: 54,
                child: Text(latest == null ? '—' : vsUsual(latest),
                    textAlign: TextAlign.right,
                    style: FloorPop.readout(15, color: _tone(latest))),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: pop.haze),
            ]),
          ),
        ),
      ),
      AnimatedSize(
        duration: FloorPop.eighth,
        curve: FloorPop.settle,
        alignment: Alignment.topCenter,
        child: !open
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: LayoutBuilder(builder: (context, box) {
                  final col = box.maxWidth / kTrendWeeks;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CustomPaint(
                          size: Size(box.maxWidth, 120),
                          painter: _FormLine(gaps,
                              scale: scale,
                              colour: pop.haze,
                              baseline: pop.line,
                              inset: col / 2,
                              stroke: 2.5,
                              dashed: true,
                              dots: [for (final g in gaps) _tone(g)]),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          for (final (i, w) in span.indexed)
                            SizedBox(
                              width: col,
                              child: Column(children: [
                                SizedBox(
                                  height: 16,
                                  child: Center(
                                      child: lamps[i] == null
                                          ? _NoLamp(
                                              colour: pop.line,
                                              width: math.min(34, col - 4))
                                          : LampTag(lamps[i]!,
                                              width: math.min(34, col - 4),
                                              height: 14)),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                    '${w.window.start.day}/${w.window.start.month}',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: w.window == _week
                                            ? pop.voltText
                                            : pop.haze)),
                              ]),
                            ),
                        ]),
                        const SizedBox(height: 10),
                        Text(sideRead(gaps, lamps),
                            style: const TextStyle(fontSize: 13, height: 1.4)),
                      ]);
                }),
              ),
      ),
    ]);
  }

  Widget _levels(TrendWeek week, TrendWeek before) {
    final pop = FloorPop.of(context);
    final levels = week.levels, was = before.levels;
    Widget numeral(int l) =>
        LevelNumber(level: l, difficulty: 'EXPERT', height: 16);
    final best = levels.entries.reduce((a, b) => b.value > a.value ? b : a);
    final worst = levels.entries.reduce((a, b) => b.value < a.value ? b : a);
    final style = TextStyle(fontSize: 12, color: pop.haze);
    final read = levels.length < 2
        ? null
        : best.value >= 0 && worst.value < 0
            ? [
                WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: numeral(best.key)),
                const TextSpan(text: 's carried the week; '),
                WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: numeral(worst.key)),
                const TextSpan(text: 's are where the drop came from.'),
              ]
            : [
                TextSpan(
                    text: worst.value >= 0
                        ? 'Above your usual at every level.'
                        : 'Below your usual at every level.')
              ];
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _labelRow('BY LEVEL', 'this week · vs last'),
        const SizedBox(height: 4),
        LevelGapBars([
          for (final MapEntry(key: l, value: v) in levels.entries)
            (
              level: l,
              gap: v,
              trailing: was[l] == null
                  ? null
                  : Text(v >= was[l]! ? '↑' : '↓',
                      style:
                          TextStyle(fontSize: 13, color: _tone(v - was[l]!))),
            ),
        ]),
        if (read != null) ...[
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: read), style: style),
        ],
      ]),
    );
  }

  Widget _timing(List<TrendWeek> span, TrendWeek week, TrendWeek before) {
    final pop = FloorPop.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fast = kFastColor(dark), slow = kSlowColor(dark);
    final avg = week.timingMs, spread = week.spreadMs, was = before.spreadMs;
    final lean = avg == null
        ? 'no timing logged'
        : avg.abs() < 1.5
            ? 'on the beat'
            : '${avg.abs() < 5 ? 'a touch ' : ''}${avg < 0 ? 'fast' : 'slow'}';
    final change = spread == null || was == null || (spread - was).abs() < .5
        ? ''
        : ', ${spread < was ? '↓' : '↑'} ${(spread - was).abs().round()} on last week';
    final averages = [for (final w in span) w.timingMs];
    final spreads = [for (final w in span) w.spreadMs];
    final range = [
      ...averages.whereType<double>().map((v) => v.abs()),
      ...spreads.whereType<double>(),
      5.0,
    ].reduce(math.max);
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _labelRow('TIMING'),
        const SizedBox(height: 10),
        Row(spacing: 20, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(avg == null ? '—' : signedMs(avg),
                style: FloorPop.readout(24,
                    color: avg == null
                        ? pop.haze
                        : avg < 0
                            ? fast
                            : slow)),
            Text('average, $lean',
                style: TextStyle(fontSize: 12, color: pop.haze)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(spread == null ? '—' : '±${spread.round()} ms',
                style: FloorPop.readout(24)),
            Text('spread$change',
                style: TextStyle(fontSize: 12, color: pop.haze)),
          ]),
        ]),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, box) => CustomPaint(
            size: Size(box.maxWidth, 44),
            painter: _FormLine(averages,
                scale: range,
                colour: fast,
                baseline: pop.line,
                inset: box.maxWidth / kTrendWeeks / 2,
                stroke: 2,
                second: spreads,
                secondColour: pop.haze),
          ),
        ),
        const SizedBox(height: 4),
        Text.rich(
            TextSpan(children: [
              TextSpan(text: '━ ', style: TextStyle(color: fast)),
              const TextSpan(text: 'average   '),
              const TextSpan(text: '┅ spread (lower is tighter)'),
            ]),
            style: TextStyle(fontSize: 11, color: pop.haze)),
      ]),
    );
  }

  Widget _goals(List<GoalProgress> goals) {
    final told = [
      for (final g in goals)
        if (g.goal.target != null) g
    ];
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('GOALS', style: FloorPop.of(context).label)),
          if (told.isNotEmpty)
            Text('${told.where((g) => g.reached).length} of ${told.length}',
                style: FloorPop.readout(14)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 10, children: [
          for (final g in goals) _GoalStamp(g),
        ]),
      ]),
    );
  }
}

/// A week's goal as a small tilted stamp in its kind's colour, faded when
/// missed.
class _GoalStamp extends StatelessWidget {
  const _GoalStamp(this.progress);
  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final goal = progress.goal;
    final kind = goal.kind;
    final open = goal.target == null;
    final on = open || progress.reached;
    final ink = on ? kind.ink : FloorPop.of(context).haze;
    final status = open
        ? '+${progress.count}'
        : progress.reached
            ? 'HIT'
            : '${progress.count}/${goal.target}';
    return Tooltip(
      message: goal.title,
      child: Transform.rotate(
        angle: -0.05,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: on ? kind.color : FloorPop.of(context).riser,
              borderRadius: BorderRadius.circular(10),
              boxShadow: on
                  ? [BoxShadow(color: kind.riser, offset: const Offset(0, 3))]
                  : null),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            Icon(kind.icon, size: 14, color: ink),
            // Kinds without art of their own say what they count.
            if (goalValueArt(goal) == null)
              Text(kind == GoalKind.upscore ? 'UPSCORES' : 'CLEARS',
                  style: FloorPop.display(11, color: ink)),
            GoalArt(goal, height: 16, ink: ink),
            Text(status, style: FloorPop.display(11, color: ink)),
          ]),
        ),
      ),
    );
  }
}

/// No lamp given that week: a dashed slot.
class _NoLamp extends StatelessWidget {
  const _NoLamp({required this.colour, required this.width});
  final Color colour;
  final double width;

  @override
  Widget build(BuildContext context) => Lean(
      child: CustomPaint(size: Size(width, 14), painter: _DashedBox(colour)));
}

class _DashedBox extends CustomPainter {
  _DashedBox(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(4)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) => old.colour != colour;
}

/// Weekly values (oldest first, null where unknown) as a line around a
/// zero baseline, [scale] the value that reaches the edge.
class _FormLine extends CustomPainter {
  _FormLine(this.values,
      {required this.scale,
      required this.colour,
      required this.baseline,
      required this.inset,
      required this.stroke,
      this.dashed = false,
      this.dots,
      this.second,
      this.secondColour});
  final List<double?> values;
  final double scale, inset, stroke;
  final Color colour, baseline;
  final bool dashed;
  final List<Color>? dots;
  // A second line on the same scale, dashed: timing's spread.
  final List<double?>? second;
  final Color? secondColour;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final step = (size.width - 2 * inset) / math.max(1, values.length - 1);
    final reach = mid - 6;
    Offset at(int i, double v) =>
        Offset(inset + i * step, mid - (v / scale).clamp(-1, 1) * reach);
    final base = Paint()
      ..color = baseline
      ..strokeWidth = dashed ? 1.5 : 1;
    if (dashed) {
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, mid), Offset(x + 4, mid), base);
      }
    } else {
      canvas.drawLine(Offset(0, mid), Offset(size.width, mid), base);
    }
    void line(List<double?> vs, Color c, {bool dash = false}) {
      final points = [
        for (var i = 0; i < vs.length; i++)
          if (vs[i] != null) at(i, vs[i]!)
      ];
      if (points.length < 2) return;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      final paint = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = dash ? 1.5 : stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      if (!dash) return canvas.drawPath(path, paint);
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 6) {
          canvas.drawPath(m.extractPath(d, d + 3), paint);
        }
      }
    }

    line(values, colour);
    if (dots == null) {
      // A lone week still shows on a sparkline.
      for (var i = 0; i < values.length; i++) {
        if (values[i] != null) {
          canvas.drawCircle(at(i, values[i]!), stroke, Paint()..color = colour);
        }
      }
    }
    if (second != null) line(second!, secondColour ?? colour, dash: true);
    if (dots != null) {
      for (var i = 0; i < values.length; i++) {
        if (values[i] != null) {
          canvas.drawCircle(at(i, values[i]!), 4.5, Paint()..color = dots![i]);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_FormLine old) => true;
}

List<String> _filterLabels(
    TrendFilter filter, List<TrendPlay> plays, Map<int, Cabinet> cabinets) {
  final chart = plays.where((p) => p.chart == filter.chart).firstOrNull;
  final venue =
      cabinets.values.where((c) => c.venueId == filter.venueId).firstOrNull;
  final cabinet = cabinets[filter.cabinetId];
  return [
    if (chart == null && filter.level != null) 'Level ${filter.level}',
    if (chart != null) '${chart.play.title} (${chart.play.difficulty})',
    if (venue != null) venue.venueName,
    if (cabinet != null)
      cabinet.name.isEmpty ? cabinet.venueName : cabinet.label,
    if (filter.side != null) filter.side == PadSide.p1 ? '1P' : '2P',
  ];
}

/// Keep edits local until Apply, including when a nested chart picker is open.
class _TrendFiltersSheet extends StatefulWidget {
  const _TrendFiltersSheet(
      {required this.plays, required this.cabinets, required this.initial});
  final List<TrendPlay> plays;
  final Map<int, Cabinet> cabinets;
  final TrendFilter initial;

  @override
  State<_TrendFiltersSheet> createState() => _TrendFiltersSheetState();
}

class _TrendFiltersSheetState extends State<_TrendFiltersSheet> {
  late final Modes _mode = widget.initial.mode;
  late int? _level = widget.initial.level;
  late String? _chart = widget.initial.chart;
  late int? _venue = widget.initial.venueId;
  late int? _cabinet = widget.initial.cabinetId;
  late PadSide? _side = widget.initial.side;

  TrendFilter get _filter => TrendFilter(
      mode: _mode,
      level: _level,
      chart: _chart,
      venueId: _venue,
      cabinetId: _cabinet,
      side: _side);

  Future<void> _pickChart() async {
    final charts = {
      for (final p in widget.plays)
        if (p.play.mode == _mode &&
            (_chart != null || _level == null || p.level == _level))
          p.chart: p
    };
    final sorted = charts.values.toList()
      ..sort((a, b) => a.play.title.compareTo(b.play.title));
    final songs = {for (final song in Songs.list) song.name: song};
    final picked = await showSongSearchSheet<String>(
      context,
      selected: _chart,
      browseWhenEmpty: true,
      allOption: (label: 'All charts', value: ''),
      options: [
        for (final p in sorted)
          SongSearchOption(
            value: p.chart,
            // Keep older plays selectable even when their song is absent
            // from the current catalogue.
            song: songs[p.play.song] ??
                SongInfo.fromJson({
                  'name': p.play.song ?? p.play.konamiId,
                  'title': p.play.title,
                }),
            mode: p.play.mode,
            difficulty: p.play.difficulty,
            level: p.level,
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() {
        _chart = picked.isEmpty ? null : picked;
        _level = charts[picked]?.level;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final levels = widget.plays
        .where((p) => p.play.mode == _mode)
        .map((p) => p.level)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    final venues = {
      for (final c in widget.cabinets.values) c.venueId: c.venueName
    };
    final cabs = widget.cabinets.values
        .where((c) => _venue == null || c.venueId == _venue);
    final chart = widget.plays.where((p) => p.chart == _chart).firstOrNull;
    final count = _filterLabels(_filter, widget.plays, widget.cabinets).length;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(children: [
              Expanded(
                  child: Text('Filters',
                      style: Theme.of(context).textTheme.titleLarge)),
              TextButton(
                onPressed: count == 0
                    ? null
                    : () => setState(() {
                          _level = null;
                          _chart = null;
                          _venue = null;
                          _cabinet = null;
                          _side = null;
                        }),
                child: const Text('Reset filters'),
              ),
            ]),
          ),
          Expanded(
              child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: [
              Text('CHARTS', style: pop.label),
              const SizedBox(height: 16),
              if (chart != null)
                Semantics(
                  label: 'Level set by selected chart',
                  enabled: false,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Level',
                      helperText: 'Set by selected chart',
                      enabled: false,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: chart.level == null
                          ? const Text('Unknown')
                          : LevelNumber(
                              level: chart.level!,
                              difficulty: chart.play.difficulty),
                    ),
                  ),
                )
              else
                _picker<int>(
                    'Level',
                    'All levels',
                    _level,
                    {for (final level in levels) level: '$level'},
                    (level) => setState(() {
                          _level = level;
                          _chart = null;
                        }),
                    itemBuilder: (level) => Semantics(
                          label: 'Level $level',
                          child: ExcludeSemantics(
                            child:
                                LevelNumber(level: level, difficulty: 'EXPERT'),
                          ),
                        )),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(chart?.play.title ?? 'All charts'),
                subtitle: chart == null
                    ? const Text('Track a specific chart')
                    : Row(children: [
                        PlayStyleIcon(mode: chart.play.mode),
                        const SizedBox(width: 6),
                        Text(chart.play.difficulty)
                      ]),
                trailing: const Icon(Icons.search_rounded),
                onTap: _pickChart,
              ),
              const Divider(height: 32),
              Text('LOCATION', style: pop.label),
              const SizedBox(height: 16),
              _picker<int>(
                  'Venue',
                  'All venues',
                  _venue,
                  venues,
                  (venue) => setState(() {
                        _venue = venue;
                        _cabinet = null;
                      })),
              const SizedBox(height: 16),
              _picker<int>(
                  'Cabinet',
                  'All cabinets',
                  _cabinet,
                  {
                    for (final c in cabs)
                      c.id: c.name.isEmpty ? c.venueName : c.label
                  },
                  (cabinet) => setState(() => _cabinet = cabinet)),
              const SizedBox(height: 16),
              Text('Pad side', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              PillTabs<PadSide?>(
                tabHeight: 48,
                values: const [null, PadSide.p1, PadSide.p2],
                tabs: const [Text('Both sides'), Text('1P'), Text('2P')],
                selected: _side,
                onChanged: (side) => setState(() => _side = side),
              ),
              const SizedBox(height: 12),
              Text(
                  'Location filters use logged venues and credits. Choose All to include plays without this information.',
                  style: TextStyle(fontSize: 12, color: pop.haze)),
            ],
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _filter),
              child: const Text('Apply filters'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _picker<T>(String label, String all, T? value, Map<T, String> choices,
          ValueChanged<T?> onChanged,
          {Widget Function(T)? itemBuilder}) =>
      DropdownButtonFormField<T>(
          key: ValueKey((label, value)),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            DropdownMenuItem<T>(value: null, child: Text(all)),
            for (final e in choices.entries)
              DropdownMenuItem(
                  value: e.key,
                  child: itemBuilder?.call(e.key) ??
                      Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged);
}
