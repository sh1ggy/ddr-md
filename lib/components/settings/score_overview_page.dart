/// Name: ScoreOverviewPage
/// Parent: SettingsPage
/// Description: The player's synced scores at a glance: flare skill with its
/// best charts per group, clear lamps per level, and a year of plays as a
/// day grid. Everything here comes from e-amusement syncs on Home.
library;

import 'dart:math';

import 'package:ddr_md/components/session/recent_plays.dart'
    show HomeCard, HomeSubpage;
import 'package:ddr_md/components/settings/flare_class_style.dart';
import 'package:ddr_md/components/song/card_heading.dart';
import 'package:ddr_md/components/song/difficulty_label.dart'
    show LevelNumber, LevelPicker;
import 'package:ddr_md/components/song/scores/art_badge.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/flare_card.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/grades.dart'
    show
        Grade,
        clearIcon,
        life4Icon,
        flareClassColor,
        flareRankIcon,
        gradeColor,
        gradeForScore,
        flareColor,
        gradeIcon,
        kFlareExColors,
        kLampColors;
import 'package:ddr_md/helpers.dart' show kFlareRanks;
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/score_overview.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

typedef _Loaded = ({List<ScoreRecord> records, List<RecentPlay> plays});

Future<_Loaded> _load() async => (
      records: await DatabaseProvider.getScoreRecords(ScoreRecordSource.eamuse),
      plays: await DatabaseProvider.getRecentPlays(),
    );

class ScoreOverviewPage extends StatefulWidget {
  const ScoreOverviewPage({super.key, this.mode = Modes.singles, this.level});

  /// Opens on [mode], scrolled to the level cards with [level] picked.
  final Modes mode;
  final int? level;

  @override
  State<ScoreOverviewPage> createState() => _ScoreOverviewPageState();
}

class _ScoreOverviewPageState extends State<ScoreOverviewPage> {
  late Modes _mode = widget.mode;
  final _levelsKey = GlobalKey();
  late bool _scrollToLevels = widget.level != null;

  @override
  Widget build(BuildContext context) {
    final revision = context.select<EamuseSyncState, int>((s) => s.revision);
    return HomeSubpage(
      title: 'Statistics',
      body: FutureBuilder<_Loaded>(
        key: ValueKey(revision),
        future: _load(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (data.records.isEmpty) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Sync e-amusement on Home to see your scores here',
                  textAlign: TextAlign.center),
            ));
          }
          final levels = chartsByLevel(data.records, Songs.list, _mode);
          if (_scrollToLevels) {
            _scrollToLevels = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final cards = _levelsKey.currentContext;
              if (cards != null && cards.mounted) {
                Scrollable.ensureVisible(cards,
                    duration: FloorPop.beat, curve: FloorPop.settle);
              }
            });
          }
          return ListView(
            padding: clearOfBars(context, const EdgeInsets.only(bottom: 24)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: PillTabs<Modes>(
                  values: const [Modes.singles, Modes.doubles],
                  tabs: [
                    for (final (mode, asset) in [
                      (Modes.singles, 'assets/icons/style_single.png'),
                      (Modes.doubles, 'assets/icons/style_double.png'),
                    ])
                      Tab(
                          child: Opacity(
                        opacity: _mode == mode ? 1 : 0.4,
                        child: Image.asset(asset, height: 15),
                      )),
                  ],
                  selected: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
              ),
              _FlareCard(flareSkill(data.records, Songs.list, _mode),
                  key: ValueKey(_mode)),
              _LevelsCard(levels, key: _levelsKey, initial: widget.level),
              _LevelStatsCard(levels, initial: widget.level),
              _ActivityCard(playsPerDay(data.plays, data.records)),
            ],
          );
        },
      ),
    );
  }
}

String _thousands(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// A flare skill [total] in its class's colours, with the class's progress.
class FlareClassHeader extends StatelessWidget {
  const FlareClassHeader(this.total, {super.key});

  final int total;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final cls = flareClass(total);
    final next = cls.next;
    final rankColor = flareClassColor(cls.name);
    final track = FloorPop.readout(13, color: pop.haze);
    final world = next == null;
    final sub = flareSubRank(cls.name);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        FlareClassArt(cls.name, size: 40),
        const SizedBox(width: 8),
        FlareClassPaint(cls.name,
            child: Text(_thousands(total),
                style: FloorPop.display(22, color: rankColor).copyWith(
                    shadows: world || sub == 0
                        ? null
                        : [
                            Shadow(
                                color: rankColor.withValues(alpha: 0.25 * sub),
                                blurRadius: 5.0 * sub)
                          ]))),
        const Spacer(),
        FlareClassName(cls.name),
      ]),
      const SizedBox(height: 4),
      _ClassTrack(
          color: rankColor,
          back: pop.riser,
          sub: sub,
          world: world,
          progress: world ? 1 : (total - cls.from) / (next - cls.from)),
      const SizedBox(height: 3),
      Row(children: [
        Expanded(child: Text(_thousands(cls.from), style: track)),
        Text(
            world
                ? 'Top class'
                : '${_thousands(next - total)} to ${flareClass(next).name}',
            style: track.copyWith(color: rankColor)),
        Expanded(
            child: Text(next == null ? '' : _thousands(next),
                textAlign: TextAlign.right, style: track)),
      ]),
    ]);
  }
}

/// Every flare skill class's header, part way through the class.
class FlareClassPreviewPage extends StatelessWidget {
  const FlareClassPreviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final totals = <int>[];
    for (int? t = 0; t != null; t = flareClass(t).next) {
      final next = flareClass(t).next;
      totals.add(next == null ? t : t + (next - t) * 2 ~/ 5);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Flare class preview')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
        children: [
          for (final total in totals)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: flareClassSurface(flareClass(total).name,
                  base: FloorPop.of(context).stage,
                  radius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CardHeading('Flare Skill',
                          icon: Icons.local_fire_department_outlined,
                          iconColor: flareClassColor(flareClass(total).name),
                          iconGradient: flareClass(total).next == null
                              ? kFlareRainbow
                              : null),
                      const SizedBox(height: 6),
                      FlareClassHeader(total),
                    ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// The class and its progress, then one tile per group. Tapping a tile swaps
/// the single chart list under them, which opens on the lowest floor.
class _FlareCard extends StatefulWidget {
  const _FlareCard(this.skill, {super.key});

  final FlareSkill skill;

  @override
  State<_FlareCard> createState() => _FlareCardState();
}

class _FlareCardState extends State<_FlareCard> {
  FlareGroup? _picked;

  @override
  Widget build(BuildContext context) {
    final skill = widget.skill;
    final picked = _picked ?? skill.lowestFloor;
    final rankColor = flareClassColor(flareClass(skill.total).name);
    return HomeCard(
      title: 'Flare Skill',
      icon: Icons.local_fire_department_outlined,
      decoration: flareClassSurface(flareClass(skill.total).name,
          base: FloorPop.of(context).stage, radius: BorderRadius.circular(24)),
      heading: Row(mainAxisSize: MainAxisSize.min, children: [
        CardHeading('Flare Skill',
            icon: Icons.local_fire_department_outlined,
            iconColor: rankColor,
            iconGradient:
                flareClass(skill.total).name == 'WORLD' ? kFlareRainbow : null),
        IconButton(
          tooltip: 'Flare points table',
          icon: const Icon(Icons.info_outline, size: 18),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            builder: (_) => _FlareTableSheet(
                charts: [for (final g in skill.groups.values) ...g]),
          ),
        ),
      ]),
      children: [
        FlareClassHeader(skill.total),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final g in FlareGroup.values) ...[
            if (g != FlareGroup.values.first) const SizedBox(width: 6),
            Expanded(
              child: _FlareGroupTile(
                group: g,
                skill: skill,
                selected: g == picked,
                onTap: () => setState(() => _picked = g),
              ),
            ),
          ],
        ]),
        _FlareCharts(skill.groups[picked]!),
      ],
    );
  }
}

class _FlareGroupTile extends StatelessWidget {
  const _FlareGroupTile({
    required this.group,
    required this.skill,
    required this.selected,
    required this.onTap,
  });

  final FlareGroup group;
  final FlareSkill skill;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pop = FloorPop.of(context);
    final charts = skill.groups[group]!;
    final radius = BorderRadius.circular(12);
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? pop.riser : pop.stage,
        shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
                width: 2, color: selected ? pop.voltText : Colors.transparent)),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group.label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: group.color(theme.brightness == Brightness.dark))),
              const SizedBox(height: 2),
              Text(_thousands(skill.groupTotal(group)),
                  style:
                      FloorPop.readout(16, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 5),
              SizedBox(
                height: 10,
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < kFlareChartsPerGroup; i++)
                        Expanded(
                            child: DecoratedBox(
                                decoration: _slot(
                                    i,
                                    i < charts.length
                                        ? charts[i].flareRank
                                        : null,
                                    pop))),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// A counted chart in its flare's colour, or an outline for an open slot.
  /// EX slots read off one rainbow spanning the ribbon.
  BoxDecoration _slot(int i, String? rank, FloorPop pop) {
    if (rank == null) {
      return BoxDecoration(border: Border.all(color: pop.line, width: 0.5));
    }
    if (rank != 'EX') {
      return BoxDecoration(color: rank.isEmpty ? pop.haze : flareColor(rank));
    }
    final t = i / (kFlareChartsPerGroup - 1) * (kFlareExColors.length - 1);
    final from = t.floor();
    return BoxDecoration(
        color: Color.lerp(
            kFlareExColors[from],
            kFlareExColors[min(from + 1, kFlareExColors.length - 1)],
            t - from));
  }
}

/// A class's four sub-ranks as segments, those passed full and the current one
/// filling, each a step brighter. WORLD has no sub-ranks: one rainbow bar.
class _ClassTrack extends StatelessWidget {
  const _ClassTrack({
    required this.color,
    required this.back,
    required this.sub,
    required this.world,
    required this.progress,
  });

  final Color color, back;
  final int sub;
  final bool world;
  final double progress;

  static const _height = 6.0;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_height / 2);
    if (world) {
      return Container(
          height: _height,
          decoration:
              BoxDecoration(borderRadius: radius, gradient: kFlareRainbow));
    }
    return Row(children: [
      for (var i = 0; i < 4; i++) ...[
        if (i > 0) const SizedBox(width: 3),
        Expanded(
          child: Container(
            height: _height,
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: back, borderRadius: radius),
            child: FractionallySizedBox(
              widthFactor: i < sub
                  ? 1
                  : i == sub
                      ? progress
                      : 0,
              heightFactor: 1,
              child:
                  ColoredBox(color: Color.lerp(color, Colors.white, 0.2 * i)!),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// Every level and flare rank's points, coloured by the class and sub-rank 90
/// charts at that value would reach. The toggle lights the cells [charts], from
/// every era, sit on.
class _FlareTableSheet extends StatefulWidget {
  const _FlareTableSheet({required this.charts});

  final List<ScoreRecord> charts;

  @override
  State<_FlareTableSheet> createState() => _FlareTableSheetState();
}

class _FlareTableSheetState extends State<_FlareTableSheet> {
  static const _levelWidth = 24.0;
  static const _rowHeight = 30.0;
  static const _gap = 1.0;
  bool _mine = false;

  /// How many of the group's charts sit on each (level, rank).
  Map<(int, int), int> _counts() {
    final counts = <(int, int), int>{};
    for (final r in widget.charts) {
      final song = Songs.list.where((s) => s.name == r.song).firstOrNull;
      final level =
          song == null ? null : chartLevel(song, r.mode, r.difficulty);
      if (level == null) continue;
      final key = (level, kFlareRanks.indexOf(r.flareRank) + 1);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  Widget _cell(int level, int rank, int count, FloorPop pop) {
    final points = flarePoints(level, rank);
    final name = flareClass(points * 90).name;
    final world = name == 'WORLD';
    // WORLD's cells step through the rainbow across the table's corner.
    final color = world
        ? kFlareExColors[(2 * level + rank) % kFlareExColors.length]
        : flareClassColor(name);
    final lit = _mine && count > 0;
    final back = _mine && !lit
        ? pop.riser
        : Color.lerp(
            pop.stage, color, world ? 0.85 : flareSubRankStrength(name))!;
    final text = _mine && !lit
        ? pop.haze
        : ThemeData.estimateBrightnessForColor(back) == Brightness.dark
            ? Colors.white
            : FloorPop.onVolt;
    return Expanded(
      child: Container(
        height: _rowHeight,
        margin: const EdgeInsets.only(left: _gap),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: back,
            border: _mine || flareSubRank(name) < 2
                ? null
                : Border.all(
                    color: Colors.white.withValues(
                        alpha: flareSubRank(name) == 3 ? 0.9 : 0.35))),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$points', style: FloorPop.readout(11, color: text)),
            if (lit)
              Text('×$count',
                  style: TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: text))
            else if (!_mine && flareSubRank(name) > 0)
              Text('+' * flareSubRank(name),
                  style: TextStyle(
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: text)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    final counts = _counts();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Expanded(
                  child: Text('Flare points',
                      style: FloorPop.display(18, color: ink))),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _mine = !_mine),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(
                      value: _mine,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setState(() => _mine = v ?? false)),
                  Text('Show my charts',
                      style: TextStyle(fontSize: 13, color: ink)),
                ]),
              ),
            ]),
          ),
          Row(children: [
            const SizedBox(width: _levelWidth),
            for (var rank = 10; rank >= 0; rank--)
              Expanded(
                child: Center(
                  child: rank == 0
                      ? Text('–', style: TextStyle(color: pop.haze))
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ArtBadge(flareRankIcon(kFlareRanks[rank - 1]),
                              aspect: kFlareAspect, ink: 12, height: 18)),
                ),
              ),
          ]),
          const SizedBox(height: 2),
          for (var level = 19; level >= 1; level--)
            Padding(
              padding: const EdgeInsets.only(bottom: _gap),
              child: Row(children: [
                SizedBox(
                    width: _levelWidth, child: Center(child: _Level(level))),
                for (var rank = 10; rank >= 0; rank--)
                  _cell(level, rank, counts[(level, rank)] ?? 0, pop),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// A group's counted charts, best first, two to a line.
class _FlareCharts extends StatelessWidget {
  const _FlareCharts(this.charts);

  final List<ScoreRecord> charts;

  @override
  Widget build(BuildContext context) {
    // Always every slot, so switching group or style moves nothing below.
    Widget slot(int i) => i < charts.length
        ? _FlareChartCard(charts[i])
        : Container(
            height: _FlareChartCard._height,
            decoration: BoxDecoration(
                color: FloorPop.of(context).riser.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6)),
          );
    return Column(children: [
      for (var i = 0; i < kFlareChartsPerGroup; i += 2)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(child: slot(i)),
            const SizedBox(width: 4),
            Expanded(child: slot(i + 1)),
          ]),
        ),
    ]);
  }
}

/// A counted chart in its flare's colours: the jacket, then its title over its
/// level, flare and points.
class _FlareChartCard extends StatelessWidget {
  const _FlareChartCard(this.record);

  final ScoreRecord record;

  static const _height = 40.0;

  @override
  Widget build(BuildContext context) {
    final song = Songs.list.where((s) => s.name == record.song).firstOrNull;
    final level =
        song == null ? null : chartLevel(song, record.mode, record.difficulty);
    final rank = record.flareRank;
    return Container(
      height: _height,
      clipBehavior: Clip.antiAlias,
      decoration: flareCardBack(context, rank.isEmpty ? null : rank, radius: 6),
      child: Row(children: [
        SizedBox.square(
            dimension: _height,
            child: SongArtwork(
                songName: record.song ?? record.title, title: record.title)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(children: [
                  // A fixed slot, so the flare never moves with the numeral's width.
                  SizedBox(
                      width: 24,
                      child: level == null
                          ? null
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: LevelNumber(
                                  level: level,
                                  difficulty: record.difficulty,
                                  height: 12))),
                  if (rank.isNotEmpty)
                    ArtBadge(flareRankIcon(rank),
                        aspect: kFlareAspect, ink: 12, height: 14),
                  const Spacer(),
                  Text('${record.flareSkill}',
                      style: FloorPop.readout(14,
                          color: Theme.of(context).colorScheme.onSurface)),
                ]),
              ]),
        ),
        const SizedBox(width: 6),
      ]),
    );
  }
}

/// One band of the clear table's bars: which played charts it holds, its
/// colour, and its label art (or text where there's none).
typedef _Band = ({
  bool Function(ScoreRecord) holds,
  Color color,
  String? icon,
  String text,
  Gradient? fill,
});

// Best first. A chart without a lamp shows as failed.
final _lampBands = <_Band>[
  for (final (lamp, icon, text) in const [
    (ClearLamp.mfc, 'assets/icons/cl_marv.png', 'MFC'),
    (ClearLamp.pfc, 'assets/icons/cl_perf.png', 'PFC'),
    (ClearLamp.gfc, 'assets/icons/cl_great.png', 'GFC'),
    (ClearLamp.fc, 'assets/icons/cl_good.png', 'FC'),
    (ClearLamp.life4, life4Icon, 'LIFE4'),
    (ClearLamp.clear, clearIcon, 'CLEAR'),
    (ClearLamp.failed, 'assets/icons/rank_e.png', 'E'),
  ])
    (
      holds: (r) => (r.clearLamp ?? ClearLamp.failed) == lamp,
      color: kLampColors[lamp]!,
      icon: icon,
      text: text,
      fill: null,
    ),
];

// EX first, then IX down to I, then no flare.

final _flareBands = <_Band>[
  (
    holds: (r) => r.flareRank == 'EX',
    color: flareColor('EX'),
    icon: flareRankIcon('EX'),
    text: 'EX',
    fill: const LinearGradient(colors: kFlareExColors),
  ),
  for (var i = 8; i >= 0; i--)
    (
      holds: (r) => r.flareRank == kFlareRanks[i],
      color: flareColor(kFlareRanks[i]),
      icon: flareRankIcon(kFlareRanks[i]),
      text: kFlareRanks[i],
      fill: null,
    ),
  (
    holds: (r) => r.flareRank.isEmpty,
    color: const Color(0xFF757575),
    icon: null,
    text: 'No flare',
    fill: null,
  ),
];

// AAA down to E. A failed chart is an E whatever it scored.
final _gradeBands = <_Band>[
  for (final g in Grade.values)
    (
      holds: (r) => _grade(r) == g,
      color: gradeColor(g),
      icon: gradeIcon(g),
      text: g.label,
      fill: null,
    ),
];

Grade _grade(ScoreRecord r) => gradeForScore(r.score ?? 0,
    failed: (r.clearLamp ?? ClearLamp.failed) == ClearLamp.failed);

const _bandHeight = 18.0;

enum _Tab { lamps, grades, flare }

class _LevelsCard extends StatefulWidget {
  const _LevelsCard(this.levels, {super.key, this.initial});

  final Map<int, LevelCharts> levels;
  final int? initial;

  @override
  State<_LevelsCard> createState() => _LevelsCardState();
}

class _LevelsCardState extends State<_LevelsCard> {
  _Tab _tab = _Tab.lamps;
  late int? _picked = widget.initial;

  @override
  Widget build(BuildContext context) {
    if (!widget.levels.containsKey(_picked)) _picked = null;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final bands = switch (_tab) {
      _Tab.lamps => _lampBands,
      _Tab.grades => _gradeBands,
      _Tab.flare => _flareBands,
    };
    const figures = [FontFeature.tabularFigures()];
    return HomeCard(
      title: 'By Level',
      icon: Icons.emoji_events_outlined,
      children: [
        PillTabs<_Tab>(
          values: _Tab.values,
          tabs: const [
            Tab(text: 'Lamps'),
            Tab(text: 'Grades'),
            Tab(text: 'Flare')
          ],
          selected: _tab,
          onChanged: (t) => setState(() => _tab = t),
        ),
        const SizedBox(height: 8),
        for (final MapEntry(key: level, value: row) in widget.levels.entries)
          GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  setState(() => _picked = _picked == level ? null : level),
              child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _picked == null || _picked == level ? 1 : 0.35,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                    decoration: BoxDecoration(
                        color:
                            _picked == level ? scheme.secondaryContainer : null,
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(children: [
                      SizedBox(width: 30, child: Center(child: _Level(level))),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: SizedBox(
                            height: 14,
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final b in bands)
                                    if (_count(row, b) > 0)
                                      Expanded(
                                          flex: _count(row, b),
                                          child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                  color: b.color,
                                                  gradient: b.fill))),
                                  if (_unplayed(row) > 0)
                                    Expanded(
                                        flex: _unplayed(row),
                                        child: ColoredBox(
                                            color: scheme
                                                .surfaceContainerHighest)),
                                ]),
                          ),
                        ),
                      ),
                      SizedBox(
                          width: 72,
                          child: Text('${row.played.length}/${row.charts}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                  fontFeatures: figures))),
                    ]),
                  ))),
        const SizedBox(height: 10),
        // Every band, even empty ones, so the grid holds still between picks.
        _BandCounts([
          for (final b in bands)
            (
              b,
              _picked == null
                  ? _total(widget.levels, b)
                  : _count(widget.levels[_picked]!, b)
            ),
        ]),
      ],
    );
  }
}

int _count(LevelCharts row, _Band b) => row.played.where(b.holds).length;

int _total(Map<int, LevelCharts> levels, _Band b) =>
    levels.values.fold(0, (n, row) => n + _count(row, b));

// Never negative, though the song list can lag behind a sync.
int _unplayed(LevelCharts row) => max(0, row.charts - row.played.length);

/// A level in the cabinet's numerals, in a neutral grey.
class _Level extends StatelessWidget {
  const _Level(this.level);

  final int level;

  static const _grey = ColorFilter.matrix([
    0.33, 0.33, 0.33, 0, 0, //
    0.33, 0.33, 0.33, 0, 0,
    0.33, 0.33, 0.33, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
        colorFilter: _grey,
        child: LevelNumber(level: level, difficulty: 'EXPERT', height: 16));
  }
}

/// One level picked from a row of numerals and how its scores spread.
class _LevelStatsCard extends StatefulWidget {
  const _LevelStatsCard(this.levels, {this.initial});

  final Map<int, LevelCharts> levels;
  final int? initial;

  @override
  State<_LevelStatsCard> createState() => _LevelStatsCardState();
}

class _LevelStatsCardState extends State<_LevelStatsCard> {
  late int? _picked = widget.initial;

  @override
  Widget build(BuildContext context) {
    final played = [
      for (final e in widget.levels.entries)
        if (e.value.played.isNotEmpty) e.key
    ];
    if (played.isEmpty) return const SizedBox.shrink();
    // Starts on the hardest level with a decent number of plays.
    final level = played.contains(_picked)
        ? _picked!
        : played.lastWhere((l) => widget.levels[l]!.played.length >= 10,
            orElse: () => played.last);
    final row = widget.levels[level]!;
    return HomeCard(
      title: 'Level Stats',
      icon: Icons.insights,
      children: [
        LevelPicker(
          levels: widget.levels.keys.toList(),
          isSelected: (l) => l == level,
          onTap: (l) => setState(() => _picked = l),
        ),
        _ScoreSpread(row.played),
      ],
    );
  }
}

/// Band labels with their counts as a three-column grid of badge tiles, the
/// same as the binder's tier counts, so changing counts never moves
/// anything. Empty bands are dimmed.
class _BandCounts extends StatelessWidget {
  const _BandCounts(this.entries);

  final List<(_Band, int)> entries;

  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
        fontSize: 13,
        height: 1,
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()]);
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          for (final (b, n) in entries)
            Opacity(
              opacity: n > 0 ? 1 : 0.3,
              child: ArtTile(b.icon,
                  aspect: b.icon == null || b.icon!.contains('/cl_')
                      ? kLampAspect
                      : b.icon!.contains('/rank_')
                          ? kGradeAspect
                          : kFlareAspect,
                  ink: 11,
                  width: (box.maxWidth - 2 * _gap) / 3,
                  height: _bandHeight + 10,
                  color: b.color,
                  label: Text(b.text, style: style.copyWith(color: b.color)),
                  trailing: Text('$n', style: style)),
            ),
        ],
      ),
    );
  }
}

/// A level's score spread: how many charts land in each band of score, with
/// the mean marked and one standard deviation either side shaded.
class _ScoreSpread extends StatelessWidget {
  const _ScoreSpread(this.played);

  final List<ScoreRecord> played;

  @override
  Widget build(BuildContext context) {
    // A failed chart's score isn't comparable, so it's left out.
    final scores = [
      for (final r in played)
        if (r.score != null &&
            (r.clearLamp ?? ClearLamp.failed) != ClearLamp.failed)
          r.score!
    ];
    final stats = meanAndSd(scores);
    if (stats == null) return const SizedBox(height: 8);
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    // From the lowest score (rounded down to 10k) up to a perfect million.
    final low = min((scores.reduce(min) ~/ 10000) * 10000, 990000);
    Widget stat(String label, String value) => Expanded(
          child: Column(children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: muted,
                    fontWeight: FontWeight.w600)),
            Text(value,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Column(children: [
        Row(children: [
          stat('AVERAGE', _thousands(stats.mean.round())),
          stat('GRADE', gradeForScore(stats.mean.round()).label),
          stat('STD DEV', _thousands(stats.sd.round())),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 90,
          width: double.infinity,
          child: CustomPaint(
              painter: _SpreadPainter(
            scores: scores,
            low: low,
            mean: stats.mean,
            sd: stats.sd,
            bar: scheme.primary,
            band: scheme.primary.withValues(alpha: 0.12),
            line: scheme.onSurface,
          )),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text(_thousands(low), style: TextStyle(fontSize: 11, color: muted)),
          const Spacer(),
          Text('1,000,000', style: TextStyle(fontSize: 11, color: muted)),
        ]),
      ]),
    );
  }
}

class _SpreadPainter extends CustomPainter {
  _SpreadPainter({
    required this.scores,
    required this.low,
    required this.mean,
    required this.sd,
    required this.bar,
    required this.band,
    required this.line,
  });

  final List<int> scores;
  final int low;
  final double mean, sd;
  final Color bar, band, line;

  static const _bins = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final span = (1000000 - low).toDouble();
    double x(double score) =>
        ((score - low) / span).clamp(0.0, 1.0) * size.width;
    final counts = List.filled(_bins, 0);
    for (final s in scores) {
      counts[min(((s - low) / span * _bins).floor(), _bins - 1)]++;
    }
    final most = counts.reduce(max);
    canvas.drawRect(Rect.fromLTRB(x(mean - sd), 0, x(mean + sd), size.height),
        Paint()..color = band);
    final w = size.width / _bins;
    final paint = Paint()..color = bar;
    for (var i = 0; i < _bins; i++) {
      if (counts[i] == 0) continue;
      final h = size.height * counts[i] / most;
      canvas.drawRRect(
          RRect.fromRectAndCorners(
              Rect.fromLTWH(i * w + 1, size.height - h, w - 2, h),
              topLeft: const Radius.circular(2),
              topRight: const Radius.circular(2)),
          paint);
    }
    canvas.drawLine(
        Offset(x(mean), 0),
        Offset(x(mean), size.height),
        Paint()
          ..color = line
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_SpreadPainter old) =>
      old.scores != scores || old.bar != bar;
}

class _ActivityCard extends StatefulWidget {
  const _ActivityCard(this.days);

  final Map<DateTime, int> days;

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> {
  static const _weeks = 53;
  static const _cell = 12.0;
  static const _gap = 3.0;
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  DateTime? _picked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Columns are Sunday-to-Saturday weeks, the last one holding today.
    final start = DateTime(today.year, today.month,
        today.day - today.weekday % 7 - 7 * (_weeks - 1));
    final inRange = widget.days.entries.where((e) => !e.key.isBefore(start));
    final plays = inRange.fold(0, (a, e) => a + e.value);
    final busiest = inRange.fold(0, (a, e) => max(a, e.value));

    Color shade(int n) {
      if (n == 0) return scheme.surfaceContainerHighest;
      // Quarters of the busiest day, so one huge day doesn't wash out the rest.
      final step = (4 * n / max(busiest, 1)).ceil().clamp(1, 4);
      return Color.lerp(scheme.surfaceContainerHighest, scheme.primary,
          0.25 + 0.75 * step / 4)!;
    }

    final picked = _picked;
    return HomeCard(
      title: 'Play Activity',
      icon: Icons.calendar_view_month,
      children: [
        Text(
            picked == null
                ? '$plays plays on ${inRange.length} days in the last year'
                : '${widget.days[picked] ?? 0} plays on '
                    '${picked.day} ${_months[picked.month - 1]} ${picked.year}',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted)),
        const SizedBox(height: 8),
        Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                for (var w = 0; w < _weeks; w++)
                  SizedBox(
                    width: _cell + _gap,
                    child: Builder(builder: (_) {
                      final d =
                          DateTime(start.year, start.month, start.day + 7 * w);
                      final first = w == 0 || d.day <= 7;
                      return Text(first ? _months[d.month - 1] : '',
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: TextStyle(fontSize: 10, color: muted));
                    }),
                  ),
              ]),
              const SizedBox(height: 2),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var w = 0; w < _weeks; w++)
                  Column(children: [
                    for (var d = 0; d < 7; d++)
                      Builder(builder: (_) {
                        final day = DateTime(
                            start.year, start.month, start.day + 7 * w + d);
                        if (day.isAfter(today)) {
                          return const SizedBox(
                              width: _cell + _gap, height: _cell + _gap);
                        }
                        return GestureDetector(
                          onTap: () => setState(
                              () => _picked = _picked == day ? null : day),
                          child: Container(
                            width: _cell,
                            height: _cell,
                            margin: const EdgeInsets.only(
                                right: _gap, bottom: _gap),
                            decoration: BoxDecoration(
                              color: shade(widget.days[day] ?? 0),
                              borderRadius: BorderRadius.circular(2),
                              border: day == picked
                                  ? Border.all(color: scheme.onSurface)
                                  : null,
                            ),
                          ),
                        );
                      }),
                  ]),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Text('Fills in as you sync: e-amusement only lists your last 50 plays',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted)),
      ],
    );
  }
}
