/// Name: YourTiersPage
/// Parent: BestRings (the song list's level stats), TierChips
/// Description: Your tier list for one level: every rung from hardest to
/// easiest with the charts you've played there. Until you place one, it
/// starts faded on its calculated rung; placed ones show how far they sit
/// from it. Drag a chart onto a rung (its own rung keeps it there), or tap
/// it to place it. Played charts with no calculated tier wait in a tray.
/// Leaving shares what changed with your circle.
library;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/tiers/circle_tiers_page.dart';
import 'package:ddr_md/components/tiers/place_tier_sheet.dart';
import 'package:ddr_md/components/tiers/tier_lean_page.dart';
import 'package:ddr_md/components/tiers/tier_widgets.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/your_tiers.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class YourTiersPage extends StatefulWidget {
  const YourTiersPage({super.key, this.level});

  /// The level to open on; otherwise the one you've played most charts of.
  final int? level;

  @override
  State<YourTiersPage> createState() => _YourTiersPageState();
}

class _YourTiersPageState extends State<YourTiersPage> {
  int? _level;
  bool _ready = false;
  // Charts placed or moved here, by level, for the circle's feed.
  final _changed = <int, Set<TierChart>>{};
  late final CircleState _circle = context.read<CircleState>();

  @override
  void initState() {
    super.initState();
    _level = widget.level;
    ChartBests.ensure(Modes.singles).then((_) {
      if (!mounted) return;
      setState(() {
        _level ??= _mostPlayedLevel();
        _ready = true;
      });
    });
  }

  @override
  void dispose() {
    final busiest = _changed.entries
        .where((e) => e.value.isNotEmpty)
        .fold<MapEntry<int, Set<TierChart>>?>(
            null,
            (best, e) =>
                best == null || e.value.length > best.value.length ? e : best);
    _circle.shareTiers(
        post: busiest == null
            ? null
            : (level: busiest.key, count: busiest.value.length));
    super.dispose();
  }

  int _mostPlayedLevel() {
    final counts = <int, int>{};
    for (var l = 1; l <= 19; l++) {
      counts[l] = chartsAt(l).where((c) => c.played).length;
    }
    final best = counts.entries.reduce((a, b) => b.value >= a.value ? b : a);
    return best.value == 0 ? 14 : best.key;
  }

  Future<void> _place(LevelChart chart, int? rung) async {
    HapticFeedback.mediumImpact();
    await YourTiers.place(chart.song.name, chart.difficulty, chart.level, rung);
    _changed.putIfAbsent(chart.level, () => {}).add(chart.key);
  }

  Future<void> _open(LevelChart chart) async {
    final before = chart.placement?.hundredths;
    await showPlaceTierSheet(context, chart, share: false);
    if (YourTiers.of(chart.song.name, chart.difficulty, chart.level)
            ?.hundredths !=
        before) {
      _changed.putIfAbsent(chart.level, () => {}).add(chart.key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final level = _level;
    return Scaffold(
      backgroundColor: pop.ink,
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder(
          valueListenable: YourTiers.revision,
          builder: (context, _, __) {
            final charts = !_ready || level == null
                ? const <LevelChart>[]
                : [
                    for (final c in chartsAt(level))
                      if (c.played) c
                  ];
            final placed = <int, List<LevelChart>>{};
            final tray = <LevelChart>[];
            for (final c in charts) {
              if (c.placement?.hundredths ?? c.calc case final h?) {
                placed.putIfAbsent(h, () => []).add(c);
              } else {
                tray.add(c);
              }
            }
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(children: [
                  const BackButton(),
                  const Expanded(child: PageTitle('Your tiers')),
                  HeaderButton(
                      tooltip: 'Your lean',
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const TierLeanPage())),
                      icon: const Icon(Icons.insights_rounded)),
                  if (CircleState.available && _circle.id != null)
                    HeaderButton(
                        tooltip: "Your circle's tiers",
                        onPressed: level == null
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        CircleTiersPage(level: level))),
                        icon: const Icon(Icons.groups_rounded)),
                ]),
              ),
              const SizedBox(height: 12),
              if (level != null)
                TierLevelPicker(
                    level: level, onChanged: (l) => setState(() => _level = l)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text('${charts.where((c) => c.placement != null).length}',
                      style: FloorPop.readout(14, color: pop.voltText)),
                  Text(' / ${charts.length}',
                      style: FloorPop.readout(14, color: pop.haze)),
                  const Spacer(),
                  const TierShownSwitch(),
                ]),
              ),
              Expanded(
                child: level == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          for (final h in rungsOf(level))
                            _Rung(
                                level: level,
                                hundredths: h,
                                charts: placed[h] ?? const [],
                                onDrop: (c) => _place(c, h),
                                onTap: _open),
                          if (CircleState.available && _circle.id != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: _ShareRow(_circle),
                            ),
                        ],
                      ),
              ),
              if (tray.isNotEmpty)
                _Tray(tray, onTap: _open, onDrop: (c) => _place(c, null)),
            ]);
          },
        ),
      ),
    );
  }
}

/// One rung: its decimal and the charts on it, taking a chart dropped on it.
/// Empty rungs fold down to a line so the full ones get the room.
class _Rung extends StatelessWidget {
  const _Rung(
      {required this.level,
      required this.hundredths,
      required this.charts,
      required this.onDrop,
      required this.onTap});

  final int level, hundredths;
  final List<LevelChart> charts;
  final ValueChanged<LevelChart> onDrop;
  final ValueChanged<LevelChart> onTap;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return DragTarget<LevelChart>(
      onWillAcceptWithDetails: (d) =>
          d.data.placement?.hundredths != hundredths,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, hovering, _) {
        final over = hovering.isNotEmpty;
        final full = charts.isNotEmpty || over;
        return AnimatedContainer(
          duration: FloorPop.sixteenth,
          constraints: BoxConstraints(minHeight: full ? 60 : 16),
          padding: EdgeInsets.symmetric(vertical: full ? 6 : 0),
          decoration: BoxDecoration(
            color: over ? FloorPop.volt.withValues(alpha: .08) : null,
            borderRadius: over ? BorderRadius.circular(12) : null,
            border: over
                ? Border.all(color: pop.voltText, width: 1.5)
                : Border(
                    top: BorderSide(
                        color: pop.line, width: charts.isEmpty ? .5 : 1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                child: Text(rungLabel(hundredths),
                    textAlign: TextAlign.right,
                    style: full
                        ? FloorPop.readout(18, color: pop.voltText)
                        : FloorPop.readout(10,
                            color: pop.haze.withValues(alpha: .6))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(spacing: 12, runSpacing: 10, children: [
                  for (final c in charts)
                    _DraggableJacket(c, rung: hundredths, onTap: onTap),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DraggableJacket extends StatelessWidget {
  const _DraggableJacket(this.chart, {this.rung, required this.onTap});

  final LevelChart chart;
  final int? rung;
  final ValueChanged<LevelChart> onTap;

  @override
  Widget build(BuildContext context) {
    // Still on its calculated rung, not placed yet.
    final jacket = Opacity(
        opacity: chart.placement == null ? .4 : 1,
        child: TierJacket(chart, rung: rung));
    return Semantics(
      button: true,
      label: '${chart.song.title} ${chart.difficulty}',
      child: LongPressDraggable<LevelChart>(
        data: chart,
        delay: const Duration(milliseconds: 150),
        hapticFeedbackOnStart: true,
        feedback: Transform.rotate(
            angle: -.1,
            child: Material(
                color: Colors.transparent,
                elevation: 12,
                borderRadius: BorderRadius.circular(10),
                child: TierJacket(chart, size: 56))),
        childWhenDragging: Opacity(opacity: .3, child: jacket),
        child: GestureDetector(onTap: () => onTap(chart), child: jacket),
      ),
    );
  }
}

/// The level's played charts with no calculated tier to start on, until
/// they're placed. Dropping a placed chart here takes it off.
class _Tray extends StatelessWidget {
  const _Tray(this.charts, {required this.onTap, required this.onDrop});

  final List<LevelChart> charts;
  final ValueChanged<LevelChart> onTap;
  final ValueChanged<LevelChart> onDrop;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return DragTarget<LevelChart>(
      onWillAcceptWithDetails: (d) => d.data.placement != null,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, hovering, _) => Container(
        decoration: BoxDecoration(
          color: pop.stage,
          border:
              Border.all(color: hovering.isNotEmpty ? pop.voltText : pop.line),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            16, 14, 16, 14 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Text('PLAYED · NOT PLACED', style: pop.label),
              const SizedBox(width: 8),
              Text('${charts.length}',
                  style: FloorPop.readout(12, color: pop.voltText)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 70,
              child: charts.isEmpty
                  ? Center(
                      child: Icon(Icons.check_circle_rounded,
                          color: pop.voltText, semanticLabel: 'All placed'))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: charts.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (context, i) => Column(children: [
                        _DraggableJacket(charts[i], onTap: onTap),
                        const SizedBox(height: 4),
                        Text(
                            charts[i].calc == null
                                ? '—'
                                : '${charts[i].level}${rungLabel(charts[i].calc!)}',
                            style: FloorPop.readout(11, color: pop.haze)),
                      ]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Says the list is shared with the circle, and turns that off.
class _ShareRow extends StatelessWidget {
  const _ShareRow(this.circle);

  final CircleState circle;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return ListenableBuilder(
      listenable: circle,
      builder: (context, _) => SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        secondary: Icon(Icons.groups_rounded, color: pop.haze),
        title: const Text('Shared with your circle'),
        value: !CircleState.tiersHidden,
        onChanged: (on) => circle.setTiersHidden(!on),
      ),
    );
  }
}
