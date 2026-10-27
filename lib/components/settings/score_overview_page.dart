/// Name: ScoreOverviewPage
/// Parent: SettingsPage
/// Description: The player's synced scores at a glance: flare skill with its
/// best charts per group, clear lamps per level, and a year of plays as a
/// day grid. Everything here comes from e-amusement syncs on Home.
library;

import 'dart:math';

import 'package:ddr_md/components/session/recent_plays.dart'
    show HomeCard, HomeSubpage;
import 'package:ddr_md/components/song/difficulty_label.dart'
    show LevelNumber, LevelPicker;
import 'package:ddr_md/components/song/scores/art_badge.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart'
    show
        Grade,
        clearIcon,
        life4Icon,
        flareClassColor,
        flareClassIcon,
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
              _FlareCard(flareSkill(data.records, Songs.list, _mode)),
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

class _FlareCard extends StatelessWidget {
  const _FlareCard(this.skill);

  final FlareSkill skill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final total = skill.total;
    final cls = flareClass(total);
    return HomeCard(
      title: 'Flare Skill',
      icon: Icons.local_fire_department_outlined,
      children: [
        Center(
            child: Image.asset(flareClassIcon(cls.name),
                width: 96, filterQuality: FilterQuality.medium)),
        Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_thousands(total),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Text(cls.name,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: flareClassColor(cls.name))),
            ]),
        if (cls.next != null)
          Text('${_thousands(cls.next! - total)} to the next class',
              textAlign: TextAlign.center, style: TextStyle(color: muted)),
        const SizedBox(height: 4),
        for (final g in FlareGroup.values)
          Theme(
            // No dividers around an open group.
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Row(children: [
                SizedBox(
                    width: 84,
                    child: Text(g.label,
                        softWrap: false,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                Expanded(
                  child: LinearProgressIndicator(
                    value: skill.groups[g]!.length / kFlareChartsPerGroup,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                SizedBox(
                    width: 64,
                    child: Text(_thousands(skill.groupTotal(g)),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()]))),
              ]),
              subtitle: Text(
                  '${skill.groups[g]!.length} of $kFlareChartsPerGroup charts',
                  style: TextStyle(fontSize: 12, color: muted)),
              children: [
                for (final r in skill.groups[g]!) _FlareChartRow(r),
              ],
            ),
          ),
      ],
    );
  }
}

class _FlareChartRow extends StatelessWidget {
  const _FlareChartRow(this.record);

  final ScoreRecord record;

  @override
  Widget build(BuildContext context) {
    final song = Songs.list.where((s) => s.name == record.song).firstOrNull;
    final level =
        song == null ? null : chartLevel(song, record.mode, record.difficulty);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
            width: 28,
            child: level == null
                ? null
                : Align(
                    alignment: Alignment.centerLeft,
                    child: LevelNumber(
                        level: level,
                        difficulty: record.difficulty,
                        height: 16),
                  )),
        Expanded(
            child: Text(record.title,
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (record.flareRank.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ArtBadge(flareRankIcon(record.flareRank),
                aspect: kFlareAspect, ink: 14, height: 22),
          ),
        SizedBox(
            width: 40,
            child: Text('${record.flareSkill}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()]))),
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
/// same as the song list's rings card, so changing counts never moves
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
