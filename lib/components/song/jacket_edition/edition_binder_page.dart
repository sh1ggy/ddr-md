/// Name: EditionBinderPage
/// Parent: DevelopmentPage
/// Description: The player's cards as a binder, one play style at a time:
/// a divider for each level, highest first, with how many of its charts
/// you've collected and its top card, then nine-pocket sheets of every
/// chart at that level in title order. A chart without a best is an empty
/// pocket, its jacket a ghost, so the gaps show. Tapping a card opens it.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyNames;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/version_group.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'compact_jacket_edition.dart';
import 'edition_model.dart';
import 'edition_viewer.dart';
import 'jacket_edition.dart';

const binderPockets = 9;

/// One chart's pocket: its card's facts when it has a best, else empty.
typedef BinderPocket = ({SongInfo song, String difficulty, EditionFacts? card});

sealed class BinderPage {
  const BinderPage(this.level);
  final int level;
}

class BinderDivider extends BinderPage {
  const BinderDivider(super.level,
      {required this.collected, required this.total, this.top});
  final int collected, total;
  // The level's negative, its top score.
  final BinderPocket? top;
}

class BinderSheet extends BinderPage {
  const BinderSheet(super.level, this.pockets);
  final List<BinderPocket> pockets;
}

/// Every chart of [mode] by level, highest first, as dividers and sheets.
/// Reads [ChartBests], which must be loaded for [mode].
List<BinderPage> binderPages(Modes mode) {
  final levels = <int, List<BinderPocket>>{};
  for (final song in Songs.list) {
    final json = (mode == Modes.singles ? song.singles : song.doubles).toJson();
    for (final MapEntry(:key, :value) in kInGameDifficultyNames.entries) {
      final level = json[key];
      if (level is! int) continue;
      final best = ChartBests.forChart(song.name, mode, value);
      levels.putIfAbsent(level, () => []).add((
        song: song,
        difficulty: value,
        card: best == null
            ? null
            : EditionFacts(
                chart: (song: song.name, mode: mode.name, difficulty: key),
                level: level,
                version: flareGroup(song.version),
                grade: best.grade,
                flare: best.flare,
                lamp: best.lamp,
                score: best.score,
                precision: ChartBests.precisionAt(song.name, mode, value),
                levelTop: ChartBests.levelTop(song.name, mode, value)),
      ));
    }
  }
  return [
    for (final level in levels.keys.toList()..sort((a, b) => b - a))
      ...() {
        final pockets = levels[level]!
          ..sort((a, b) =>
              a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase()));
        return [
          BinderDivider(level,
              collected: pockets.where((p) => p.card != null).length,
              total: pockets.length,
              top: pockets.where((p) => p.card?.levelTop ?? false).firstOrNull),
          for (var i = 0; i < pockets.length; i += binderPockets)
            BinderSheet(
                level,
                pockets.sublist(
                    i, (i + binderPockets).clamp(0, pockets.length))),
        ];
      }(),
  ];
}

class EditionBinderPage extends StatefulWidget {
  const EditionBinderPage({super.key});
  @override
  State<EditionBinderPage> createState() => _EditionBinderPageState();
}

class _EditionBinderPageState extends State<EditionBinderPage> {
  late Modes _mode = context.read<SongState>().modes;
  List<BinderPage>? _pages;
  final _controller = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final mode = _mode;
    setState(() => _pages = null);
    await ChartBests.ensure(mode);
    if (!mounted || mode != _mode) return;
    setState(() {
      _pages = binderPages(mode);
      _page = 0;
    });
    if (_controller.hasClients) _controller.jumpToPage(0);
  }

  void _open(BinderPocket pocket) {
    final options = editionPreferences();
    showEditionViewer(context,
        facts: pocket.card!,
        options: (
          borderId: options.borderId,
          effects: options.effects,
          motion: options.motion,
          modeStamp: false,
          gradeStamp: false,
          difficultyStamp: false,
          tierSuffix: false
        ),
        artwork: SongArtwork(
            songName: pocket.song.name,
            title: pocket.song.title,
            fullResolution: true,
            fade: Duration.zero));
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final theme = Theme.of(context);
    final dividers = [
      if (pages != null)
        for (var i = 0; i < pages.length; i++)
          if (pages[i] is BinderDivider) (i, pages[i].level)
    ];
    final level = pages == null || pages.isEmpty ? null : pages[_page].level;
    final sheets = pages?.where((p) => p is BinderSheet && p.level == level);
    final sheet = pages == null || level == null
        ? 0
        : pages.sublist(0, _page + 1).where((p) => p.level == level).length - 1;
    return Scaffold(
        appBar: AppBar(title: const Text('Binder'), actions: [
          Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SegmentedButton<Modes>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: Modes.singles, label: Text('SP')),
                    ButtonSegment(value: Modes.doubles, label: Text('DP')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) {
                    _mode = s.first;
                    _load();
                  })),
        ]),
        body: pages == null
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                // A tab for each level, to jump to its divider.
                SizedBox(
                    height: 44,
                    child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          for (final (index, l) in dividers)
                            Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                    showCheckmark: false,
                                    selected: l == level,
                                    label: LevelNumber(
                                        level: l,
                                        difficulty: 'EXPERT',
                                        height: 16),
                                    onSelected: (_) =>
                                        _controller.jumpToPage(index))),
                        ])),
                Expanded(
                    child: PageView.builder(
                        controller: _controller,
                        itemCount: pages.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: switch (pages[i]) {
                              final BinderDivider d =>
                                _Divider(divider: d, onOpen: _open),
                              final BinderSheet s =>
                                _Sheet(sheet: s, onOpen: _open),
                            }))),
                Padding(
                    padding: const EdgeInsets.only(bottom: 110, top: 4),
                    child: Text(
                        sheet == 0
                            ? 'Level $level'
                            : 'Level $level · sheet $sheet of ${sheets?.length}',
                        style: theme.textTheme.labelMedium)),
              ]));
  }
}

// A binder page's paper: a sheet with a ring margin down its left edge.
class _Paper extends StatelessWidget {
  const _Paper({required this.child, this.tint});
  final Widget child;
  final Color? tint;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
        decoration: BoxDecoration(
            color: tint ?? scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant)),
        child: Row(children: [
          // The rings the page hangs from.
          SizedBox(
              width: 22,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.surface,
                              border: Border.all(color: scheme.outline))),
                  ])),
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
                  child: child)),
        ]));
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.divider, required this.onOpen});
  final BinderDivider divider;
  final ValueChanged<BinderPocket> onOpen;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = divider.top;
    return _Paper(
        tint: theme.colorScheme.surfaceContainerHighest,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LevelNumber(
                  level: divider.level, difficulty: 'EXPERT', height: 64),
              const SizedBox(height: 12),
              Text('${divider.collected} of ${divider.total} collected',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: divider.total == 0
                      ? 0
                      : divider.collected / divider.total,
                  borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 24),
              if (top != null) ...[
                Text('Top card', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Center(
                    child: SizedBox.square(
                        dimension: 150,
                        child: _Pocket(pocket: top, onOpen: onOpen))),
              ] else
                Text(
                    'Score ${ChartBests.levelTopMinCharts} charts here and '
                    'your top one turns negative.',
                    style: theme.textTheme.bodySmall),
            ]));
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.sheet, required this.onOpen});
  final BinderSheet sheet;
  final ValueChanged<BinderPocket> onOpen;
  @override
  Widget build(BuildContext context) =>
      _Paper(child: LayoutBuilder(builder: (context, constraints) {
        // Three by three, captions under each, square pockets that fit.
        const caption = 16.0, gap = 10.0;
        final side = ((constraints.maxWidth - gap * 2) / 3)
            .clamp(0.0, (constraints.maxHeight - gap * 2) / 3 - caption);
        return Center(
            child: Wrap(spacing: gap, runSpacing: gap, children: [
          for (var i = 0; i < binderPockets; i++)
            SizedBox(
                width: side,
                height: side + caption,
                child: i < sheet.pockets.length
                    ? Column(children: [
                        SizedBox.square(
                            dimension: side,
                            child: _Pocket(
                                pocket: sheet.pockets[i], onOpen: onOpen)),
                        const SizedBox(height: 3),
                        DifficultyLabel(
                            difficulty: sheet.pockets[i].difficulty,
                            height: caption - 5),
                      ])
                    : null),
        ]));
      }));
}

// A sleeve: the card when collected, else the chart's jacket as a ghost.
class _Pocket extends StatelessWidget {
  const _Pocket({required this.pocket, required this.onOpen});
  final BinderPocket pocket;
  final ValueChanged<BinderPocket> onOpen;

  static const _grey = ColorFilter.matrix([
    .2126, .7152, .0722, 0, 0, //
    .2126, .7152, .0722, 0, 0,
    .2126, .7152, .0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final art =
        SongArtwork(songName: pocket.song.name, title: pocket.song.title);
    final card = pocket.card;
    if (card == null) {
      return Semantics(
          label: '${pocket.song.title}, not collected',
          child: DecoratedBox(
              decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant)),
              child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Opacity(
                      opacity: .18,
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: ColorFiltered(
                              colorFilter: _grey, child: art))))));
    }
    return GestureDetector(
        onTap: () => onOpen(pocket),
        child: CompactJacketEdition(
            facts: card,
            options: (
              borderId: 'gilded',
              effects: true,
              motion: false,
              modeStamp: false,
              gradeStamp: false,
              difficultyStamp: false,
              tierSuffix: false
            ),
            child: art));
  }
}
