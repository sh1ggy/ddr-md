/// Name: EditionBinderPage
/// Parent: DevelopmentPage, BestRings (from the level list)
/// Description: The player's cards as a binder, one play style at a time:
/// a cover for each level, highest first, with its charts' bests as the
/// level list's rings and its best cards fanned out, then nine-pocket
/// sheets of every chart at that level in title order. A chart without a
/// best is an empty pocket, its jacket a ghost, so the gaps show. Tapping a
/// card opens it.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/best_rings.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyNames;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/version_group.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'compact_jacket_edition.dart';
import 'edition_model.dart';
import 'edition_viewer.dart';
import 'jacket_edition.dart';

const binderPockets = 9;

/// One chart's pocket: its best and card's facts when it has one, else empty.
typedef BinderPocket = ({
  SongInfo song,
  String difficulty,
  ChartBest? best,
  EditionFacts? card
});

sealed class BinderPage {
  const BinderPage(this.level);
  final int level;
}

class BinderDivider extends BinderPage {
  const BinderDivider(super.level, {required this.pockets, this.top});

  /// Every chart at the level, collected or not.
  final List<BinderPocket> pockets;
  List<ChartBest?> get bests => [for (final p in pockets) p.best];
  int get collected => pockets.where((p) => p.card != null).length;
  int get total => pockets.length;
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
        best: best,
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
              pockets: pockets,
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
  const EditionBinderPage(
      {super.key, this.mode, this.level, this.song, this.difficulty});

  /// The play style to open on, else the one picked; and the level, else the
  /// highest.
  final Modes? mode;
  final int? level;

  /// A chart to open on the sheet of, its pocket picked out.
  final String? song, difficulty;

  @override
  State<EditionBinderPage> createState() => _EditionBinderPageState();
}

class _EditionBinderPageState extends State<EditionBinderPage> {
  late Modes _mode = widget.mode ?? context.read<SongState>().modes;
  List<BinderPage>? _pages;
  var _controller = PageController();
  int _page = 0;
  // The chart opened on, until the style changes.
  late ({String song, String difficulty})? _focus =
      widget.song == null || widget.difficulty == null
          ? null
          : (song: widget.song!, difficulty: widget.difficulty!);

  @override
  void initState() {
    super.initState();
    _load(widget.level);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Opens on the focused chart's sheet, else [level]'s cover, else the first.
  Future<void> _load([int? level]) async {
    final mode = _mode;
    setState(() => _pages = null);
    await ChartBests.ensure(mode);
    if (!mounted || mode != _mode) return;
    final pages = binderPages(mode);
    final focus = _focus;
    var page = focus == null
        ? -1
        : pages.indexWhere((p) =>
            p is BinderSheet &&
            p.pockets.any((c) =>
                c.song.name == focus.song && c.difficulty == focus.difficulty));
    if (page < 0) {
      page = math.max(
          0, pages.indexWhere((p) => p is BinderDivider && p.level == level));
    }
    // The PageView is out while loading, so it comes back on a controller
    // already at [page].
    _controller.dispose();
    setState(() {
      _controller = PageController(initialPage: page);
      _pages = pages;
      _page = page;
    });
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
    final pop = FloorPop.of(context);
    final dividers = [
      if (pages != null)
        for (var i = 0; i < pages.length; i++)
          if (pages[i] is BinderDivider) (i, pages[i].level)
    ];
    final level = pages == null || pages.isEmpty ? null : pages[_page].level;
    final sheets =
        pages?.where((p) => p is BinderSheet && p.level == level).length ?? 0;
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
                  // Stays on the level, in the other style.
                  onSelectionChanged: (s) {
                    final level = _pages == null || _pages!.isEmpty
                        ? null
                        : _pages![_page].level;
                    _mode = s.first;
                    _focus = null;
                    _load(level);
                  })),
        ]),
        body: pages == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                top: false,
                child: Column(children: [
                  // A tab for each level, to jump to its cover.
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
                  // Pages as tall as a sheet's pockets need, the rest of the
                  // screen left below rather than padded in between.
                  Flexible(child: LayoutBuilder(builder: (context, box) {
                    final width = math.min(box.maxWidth, _kPageMaxWidth);
                    return SizedBox(
                        width: width,
                        height: math.min(
                            box.maxHeight, _sheetHeight(width - 32) + 16),
                        child: PageView.builder(
                            controller: _controller,
                            itemCount: pages.length,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (context, i) => Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                child: switch (pages[i]) {
                                  final BinderDivider d =>
                                    _Cover(divider: d, onOpen: _open),
                                  final BinderSheet s => _Sheet(
                                      sheet: s, focus: _focus, onOpen: _open),
                                })));
                  })),
                  SizedBox(
                      height: 28,
                      child: Center(
                          child: sheet == 0
                              ? null
                              : Text('$sheet/$sheets',
                                  style:
                                      FloorPop.readout(14, color: pop.haze)))),
                ])));
  }
}

const _kPageMaxWidth = 520.0;
// A sheet's padding, the gap between pockets and a pocket's caption.
const _kPad = 10.0, _kGap = 8.0, _kCaption = 16.0;

// The height three rows of square pockets take in a sheet [width] wide.
double _sheetHeight(double width) {
  final side = (width - 2 * _kPad - 2 * _kGap) / 3;
  return 3 * (side + _kCaption) + 2 * _kGap + 2 * _kPad;
}

// A level's cover: its number and rings across the top, its best cards
// fanned in the middle with the negative in front, and the count below.
class _Cover extends StatelessWidget {
  const _Cover({required this.divider, required this.onOpen});
  final BinderDivider divider;
  final ValueChanged<BinderPocket> onOpen;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    final top = divider.top;
    // Up to three, best score first, the negative always in front.
    final fan = [
      if (top != null) top,
      ...(divider.pockets.where((p) => p.card != null && p != top).toList()
            ..sort(
                (a, b) => (b.card!.score ?? 0).compareTo(a.card!.score ?? 0)))
          .take(top == null ? 3 : 2),
    ];
    final caps = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
        color: pop.haze);
    return DecoratedBox(
        decoration: BoxDecoration(
            color: pop.riser, borderRadius: BorderRadius.circular(20)),
        child: DecoratedBox(
            decoration: pop.stripes(radius: BorderRadius.circular(20)),
            child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('LEVEL', style: caps),
                              const SizedBox(height: 6),
                              LevelNumber(
                                  level: divider.level,
                                  difficulty: 'EXPERT',
                                  height: 76),
                            ]),
                        const Spacer(),
                        // The level list's rings, tapped open the same way.
                        BestRings(divider.bests, size: 84, track: pop.ink),
                      ]),
                      Expanded(
                          child: fan.isEmpty
                              ? Center(
                                  child: Text('No cards here yet',
                                      style: TextStyle(color: pop.haze)))
                              : _Fan(pockets: fan, onOpen: onOpen)),
                      Text(
                          top != null
                              ? 'Top card · ${top.song.title}'
                              : 'Score ${ChartBests.levelTopMinCharts} '
                                  'charts here and your top one turns '
                                  'negative.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: pop.haze)),
                      const SizedBox(height: 10),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('${divider.collected}/${divider.total}',
                                style: FloorPop.readout(24,
                                    color: scheme.onSurface)),
                            const SizedBox(width: 8),
                            Text('COLLECTED', style: caps),
                          ]),
                    ]))));
  }
}

// Cards fanned from their foot, the first in front and upright.
class _Fan extends StatelessWidget {
  const _Fan({required this.pockets, required this.onOpen});
  final List<BinderPocket> pockets;
  final ValueChanged<BinderPocket> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final side = math.min(box.maxHeight - 16, box.maxWidth * .46);
        Widget card(BinderPocket pocket, double turn, double shift) =>
            Transform.translate(
                offset: Offset(shift * side, 0),
                child: Transform.rotate(
                    angle: turn,
                    alignment: Alignment.bottomCenter,
                    child: SizedBox.square(
                        dimension: side,
                        child: _Pocket(pocket: pocket, onOpen: onOpen))));
        return Center(
            child: Stack(alignment: Alignment.center, children: [
          if (pockets.length > 2) card(pockets[2], .16, .42),
          if (pockets.length > 1) card(pockets[1], -.16, -.42),
          card(pockets[0], 0, 0),
        ]));
      });
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.sheet, required this.onOpen, this.focus});
  final BinderSheet sheet;
  final ValueChanged<BinderPocket> onOpen;
  final ({String song, String difficulty})? focus;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return DecoratedBox(
        decoration: BoxDecoration(
            color: pop.riser, borderRadius: BorderRadius.circular(20)),
        child: Padding(
            padding: const EdgeInsets.all(_kPad),
            child: LayoutBuilder(builder: (context, constraints) {
              // Three by three, captions under each, square pockets that fit.
              final side = ((constraints.maxWidth - _kGap * 2) / 3).clamp(
                  0.0, (constraints.maxHeight - _kGap * 2) / 3 - _kCaption);
              return Wrap(spacing: _kGap, runSpacing: _kGap, children: [
                for (final pocket in sheet.pockets)
                  SizedBox(
                      width: side,
                      height: side + _kCaption,
                      child: Column(children: [
                        SizedBox.square(
                            dimension: side,
                            child: _Pocket(
                                pocket: pocket,
                                onOpen: onOpen,
                                focused: pocket.song.name == focus?.song &&
                                    pocket.difficulty == focus?.difficulty)),
                        const SizedBox(height: 3),
                        DifficultyLabel(
                            difficulty: pocket.difficulty,
                            height: _kCaption - 5),
                      ])),
              ]);
            })));
  }
}

// A sleeve: the card when collected, else the chart's jacket as a ghost.
class _Pocket extends StatelessWidget {
  const _Pocket(
      {required this.pocket, required this.onOpen, this.focused = false});
  final BinderPocket pocket;
  final ValueChanged<BinderPocket> onOpen;
  // Picked out, as the chart the binder was opened on.
  final bool focused;

  static const _grey = ColorFilter.matrix([
    .2126, .7152, .0722, 0, 0, //
    .2126, .7152, .0722, 0, 0,
    .2126, .7152, .0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final art =
        SongArtwork(songName: pocket.song.name, title: pocket.song.title);
    final card = pocket.card;
    final Widget sleeve;
    if (card == null) {
      sleeve = Semantics(
          label: '${pocket.song.title}, not collected',
          child: DecoratedBox(
              decoration: BoxDecoration(
                  color: pop.stage,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: pop.line)),
              child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Opacity(
                      opacity: .18,
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: ColorFiltered(
                              colorFilter: _grey, child: art))))));
    } else {
      sleeve = GestureDetector(
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
    if (!focused) return sleeve;
    return DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FloorPop.volt, width: 2.5)),
        child: sleeve);
  }
}
