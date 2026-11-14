/// Name: CircleTiersPage
/// Parent: YourTiersPage, CircleTierPostCard
/// Description: Your circle's tier lists for one level beside yours: each
/// chart with everyone's rung on one strip, your ring and the calculated
/// tick, biggest disagreement first or by the circle's median. A person
/// picked narrows it to them and you. Also the card the circle's feed shows
/// when someone places charts.
library;

import 'package:ddr_md/components/circle/circle_page.dart' show CircleBubble;
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/tiers/place_tier_sheet.dart';
import 'package:ddr_md/components/tiers/tier_widgets.dart';
import 'package:ddr_md/components/tiers/your_tiers_page.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/your_tiers.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CircleTiersPage extends StatefulWidget {
  const CircleTiersPage({super.key, required this.level, this.person});

  final int level;

  /// Opens narrowed to this person's list beside yours.
  final String? person;

  @override
  State<CircleTiersPage> createState() => _CircleTiersPageState();
}

enum _Order { split, median }

class _CircleTiersPageState extends State<CircleTiersPage> {
  late int _level = widget.level;
  late String? _person = widget.person;
  var _order = _Order.split;

  @override
  void initState() {
    super.initState();
    context.read<CircleState>().loadTiers();
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final circle = context.watch<CircleState>();
    return Scaffold(
      backgroundColor: pop.ink,
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: YourTiers.revision,
          builder: (context, _, __) {
            final lists = {
              for (final MapEntry(:key, :value)
                  in YourTiers.circleLists.entries)
                if (_person == null || key == _person) key: value
            };
            final rows = <_Row>[];
            final charts = <TierChart>{
              for (final l in lists.values)
                for (final MapEntry(:key, :value) in l.entries)
                  if (value.level == _level) key,
            };
            for (final key in charts) {
              final chart = levelChart(key.$1, key.$2, _level);
              if (chart == null) continue;
              final others = {
                for (final MapEntry(key: who, value: l) in lists.entries)
                  if (l[key] case final p? when p.level == _level)
                    who: p.hundredths
              };
              rows.add((
                chart: chart,
                you: chart.placement?.hundredths,
                others: others,
              ));
            }
            int median(_Row r) {
              final v = r.others.values.toList()..sort();
              return v[v.length ~/ 2];
            }

            int split(_Row r) {
              final all = [...r.others.values, if (r.you != null) r.you!];
              return all.reduce((a, b) => a > b ? a : b) -
                  all.reduce((a, b) => a < b ? a : b);
            }

            rows.sort((a, b) => _order == _Order.split
                ? split(b).compareTo(split(a))
                : median(b).compareTo(median(a)));
            final people = [
              for (final id in YourTiers.circleLists.keys)
                if (circle.tierPeople[id] case final p?) p
            ];
            return Column(children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(children: [
                  BackButton(),
                  Expanded(child: PageTitle('Circle tiers')),
                ]),
              ),
              const SizedBox(height: 12),
              TierLevelPicker(
                  level: _level, onChanged: (l) => setState(() => _level = l)),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _PersonChip(
                        label: 'Everyone',
                        selected: _person == null,
                        onTap: () => setState(() => _person = null)),
                    for (final p in people)
                      _PersonChip(
                          person: p,
                          label: p.name,
                          selected: _person == p.id,
                          onTap: () => setState(() => _person = p.id)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(children: [
                  SegmentedButton<_Order>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: _Order.split,
                          icon: Icon(Icons.unfold_more_rounded),
                          tooltip: 'Biggest split'),
                      ButtonSegment(
                          value: _Order.median,
                          icon: Icon(Icons.sort_rounded),
                          tooltip: 'Circle median'),
                    ],
                    selected: {_order},
                    onSelectionChanged: (s) =>
                        setState(() => _order = s.single),
                  ),
                  const Spacer(),
                  Text('.00', style: FloorPop.readout(11, color: pop.haze)),
                  Container(
                      width: 96,
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: pop.line),
                  Text(rungLabel(100 - tierStep(_level)),
                      style: FloorPop.readout(11, color: pop.haze)),
                ]),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Icon(Icons.groups_rounded,
                            size: 40,
                            color: pop.haze,
                            semanticLabel: 'Nobody has placed charts here'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: rows.length,
                        itemBuilder: (context, i) => _ChartRow(rows[i],
                            people: circle.tierPeople, level: _level),
                      ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

typedef _Row = ({LevelChart chart, int? you, Map<String, int> others});

class _PersonChip extends StatelessWidget {
  const _PersonChip(
      {this.person,
      required this.label,
      required this.selected,
      required this.onTap});

  final CirclePerson? person;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          avatar: person == null ? null : CircleBubble(person!, size: 18),
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onTap(),
        ),
      );
}

class _ChartRow extends StatelessWidget {
  const _ChartRow(this.row, {required this.people, required this.level});

  final _Row row;
  final Map<String, CirclePerson> people;
  final int level;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final c = row.chart;
    final values = row.others.values.toList()..sort();
    final median = values[values.length ~/ 2];
    final top = 100 - tierStep(level);
    return InkWell(
      onTap: c.played ? () => showPlaceTierSheet(context, c) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: pop.line))),
        child: Row(children: [
          TierJacket(c, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(children: [
                if (row.you != null) ...[
                  Text(rungLabel(row.you!),
                      style: FloorPop.readout(13, color: pop.voltText)),
                  const SizedBox(width: 8),
                ],
                Icon(Icons.groups_rounded, size: 12, color: pop.haze),
                const SizedBox(width: 2),
                Text(rungLabel(median), style: FloorPop.readout(13)),
              ]),
            ]),
          ),
          SizedBox(
            width: 150,
            height: 22,
            child: LayoutBuilder(builder: (context, box) {
              double x(int h) => h / top * box.maxWidth;
              final all = [...values, if (row.you != null) row.you!];
              final lo = all.reduce((a, b) => a < b ? a : b);
              final hi = all.reduce((a, b) => a > b ? a : b);
              return Stack(clipBehavior: Clip.none, children: [
                Positioned(
                    left: 0,
                    right: 0,
                    top: 10,
                    height: 2,
                    child: ColoredBox(color: pop.line)),
                Positioned(
                    left: x(lo),
                    width: x(hi) - x(lo),
                    top: 9,
                    height: 4,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: pop.haze.withValues(alpha: .3),
                            borderRadius: BorderRadius.circular(2)))),
                for (final MapEntry(key: who, value: h) in row.others.entries)
                  if (people[who] case final p?)
                    Positioned(
                        left: x(h) - 7,
                        top: 4,
                        child: CircleBubble(p, size: 14)),
                if (row.you != null)
                  Positioned(
                    left: x(row.you!) - 10,
                    top: 1,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: pop.voltText, width: 2.5)),
                    ),
                  ),
                if (c.calc != null)
                  Positioned(
                      left: x(c.calc!) - 6,
                      top: -9,
                      child: Icon(Icons.arrow_drop_down_rounded,
                          size: 12, color: pop.haze)),
              ]);
            }),
          ),
        ]),
      ),
    );
  }
}

/// A circle feed card: someone placed charts at a level. Their charts there,
/// hardest first, each with how far from yours; Compare opens the circle's
/// ladder narrowed to them.
class CircleTierPostCard extends StatelessWidget {
  const CircleTierPostCard(this.post, {super.key});

  final CircleTierPost post;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final by = post.by;
    if (by == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: YourTiers.revision,
      builder: (context, _, __) {
        final theirs = [
          for (final MapEntry(key: (song, difficulty), value: p)
              in (YourTiers.circleLists[by.id] ?? const {}).entries)
            if (p.level == post.level)
              if (levelChart(song, difficulty, post.level) case final c?)
                (chart: c, rung: p.hundredths)
        ]..sort((a, b) => b.rung.compareTo(a.rung));
        final unrated = theirs
            .where((t) => t.chart.played && t.chart.placement == null)
            .length;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: pop.stage,
              border: Border.all(color: pop.line),
              borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                CircleBubble(by, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: by.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: ' placed '),
                    TextSpan(
                        text: '${post.count}',
                        style: FloorPop.readout(14, color: pop.voltText)),
                  ])),
                ),
                LevelNumber(
                    level: post.level, difficulty: 'EXPERT', height: 22),
              ]),
              if (theirs.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 14, runSpacing: 12, children: [
                  for (final t in theirs.take(6))
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      TierJacket(t.chart, size: 42),
                      const SizedBox(width: 6),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rungLabel(t.rung),
                                style: FloorPop.readout(15)),
                            _AgainstYours(t.chart, t.rung),
                          ]),
                    ]),
                ]),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: VoltButton(
                      height: 46,
                      radius: 14,
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => CircleTiersPage(
                                  level: post.level, person: by.id))),
                      child: Text('Compare', style: FloorPop.display(14))),
                ),
                if (unrated > 0) ...[
                  const SizedBox(width: 10),
                  GhostButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  YourTiersPage(level: post.level))),
                      child: Text('Rate $unrated')),
                ],
              ]),
            ],
          ),
        );
      },
    );
  }
}

/// Their rung against yours: equal, or how far above or below.
class _AgainstYours extends StatelessWidget {
  const _AgainstYours(this.chart, this.theirs);

  final LevelChart chart;
  final int theirs;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final yours = chart.placement?.hundredths;
    if (yours == null) {
      return Text('—', style: FloorPop.readout(11, color: pop.haze));
    }
    final d = theirs - yours;
    return d == 0
        ? Icon(Icons.check_rounded,
            size: 13, color: pop.voltText, semanticLabel: 'Same as yours')
        : Text(TierLean.label(d),
            style: FloorPop.readout(11, color: tierDeltaColor(d)));
  }
}
