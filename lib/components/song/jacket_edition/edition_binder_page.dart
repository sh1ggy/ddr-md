/// Name: EditionBinderPage
/// Parent: DevelopmentPage, BestRings (from the level list)
/// Description: The player's cards as a binder, one play style at a time:
/// a cover for each level, highest first, with its charts' bests as the
/// level list's rings and its best cards fanned out, then sheets of every
/// chart at that level in title order, three across and as many rows as the
/// screen holds. Jackets alone, like a binder's sleeves. A chart without a
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
  const BinderSheet(super.level, this.pockets, {this.start = 0});
  final List<BinderPocket> pockets;

  /// Where its first pocket falls among the level's charts.
  final int start;
}

/// Every chart of [mode] by level, highest first, as covers and sheets of
/// [perSheet] pockets. Reads [ChartBests], which must be loaded for [mode].
List<BinderPage> binderPages(Modes mode, {int perSheet = binderPockets}) {
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
          for (var i = 0; i < pockets.length; i += perSheet)
            BinderSheet(level,
                pockets.sublist(i, (i + perSheet).clamp(0, pockets.length)),
                start: i),
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
  bool _ready = false;
  // Paginated for [_perSheet] pockets, which follows the screen's height.
  List<BinderPage>? _pages;
  int? _perSheet;
  var _controller = PageController();
  int _page = 0;
  // Where the binder is open: a level and the first pocket in view, -1 for
  // its cover. Kept so repaginating stays put.
  ({int level, int start})? _at;
  // The chart opened on, until the style changes.
  late ({String song, String difficulty})? _focus =
      widget.song == null || widget.difficulty == null
          ? null
          : (song: widget.song!, difficulty: widget.difficulty!);

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
    setState(() {
      _ready = false;
      _pages = _perSheet = null;
    });
    await ChartBests.ensure(mode);
    if (!mounted || mode != _mode) return;
    setState(() => _ready = true);
  }

  // The pages for [perSheet] pockets, built afresh and opened where the
  // binder was when that changes.
  List<BinderPage> _paginate(int perSheet) {
    if (perSheet == _perSheet && _pages != null) return _pages!;
    final pages = binderPages(_mode, perSheet: perSheet);
    final at = _at, focus = _focus;
    var page = -1;
    if (at == null && focus != null) {
      page = pages.indexWhere((p) =>
          p is BinderSheet &&
          p.pockets.any((c) =>
              c.song.name == focus.song && c.difficulty == focus.difficulty));
    }
    if (page < 0 && at != null && at.start >= 0) {
      page = pages.indexWhere((p) =>
          p is BinderSheet &&
          p.level == at.level &&
          at.start >= p.start &&
          at.start < p.start + p.pockets.length);
    }
    if (page < 0) {
      page = math.max(
          0,
          pages.indexWhere((p) =>
              p is BinderDivider && p.level == (at?.level ?? widget.level)));
    }
    // The PageView takes a new controller at [page], the old one let go once
    // it's off it.
    final old = _controller;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _controller = PageController(initialPage: page);
    _pages = pages;
    _perSheet = perSheet;
    _settle(page);
    return pages;
  }

  void _settle(int page) {
    final p = _pages![page];
    _page = page;
    _at = (level: p.level, start: p is BinderSheet ? p.start : -1);
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
    final pop = FloorPop.of(context);
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
                  // Stays on the level's cover, in the other style.
                  onSelectionChanged: (s) {
                    if (_at case final at?) _at = (level: at.level, start: -1);
                    _mode = s.first;
                    _focus = null;
                    _load();
                  })),
        ]),
        body: !_ready
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                top: false,
                child: LayoutBuilder(builder: (context, box) {
                  const tabs = 44.0, footer = 28.0, margin = 8.0;
                  final width = math.min(box.maxWidth, _kPageMaxWidth);
                  final grid = _grid(width - 32 - 2 * _kPad,
                      box.maxHeight - tabs - footer - 2 * margin - 2 * _kPad);
                  final pages = _paginate(grid.rows * _kColumns);
                  final level = pages.isEmpty ? null : pages[_page].level;
                  final sheets = pages
                      .where((p) => p is BinderSheet && p.level == level)
                      .length;
                  final sheet = pages
                          .sublist(0, _page + 1)
                          .where((p) => p.level == level)
                          .length -
                      1;
                  return Column(children: [
                    // A tab for each level, to jump to its cover.
                    SizedBox(
                        height: tabs,
                        child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              for (final (i, p) in pages.indexed)
                                if (p is BinderDivider)
                                  Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                          showCheckmark: false,
                                          selected: p.level == level,
                                          label: LevelNumber(
                                              level: p.level,
                                              difficulty: 'EXPERT',
                                              height: 16),
                                          onSelected: (_) =>
                                              _controller.jumpToPage(i))),
                            ])),
                    Expanded(
                        child: SizedBox(
                            width: width,
                            child: PageView.builder(
                                key: ObjectKey(_controller),
                                controller: _controller,
                                itemCount: pages.length,
                                onPageChanged: (i) =>
                                    setState(() => _settle(i)),
                                itemBuilder: (context, i) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: margin),
                                    child: switch (pages[i]) {
                                      final BinderDivider d =>
                                        _Cover(divider: d, onOpen: _open),
                                      final BinderSheet s => _Sheet(
                                          sheet: s,
                                          side: grid.side,
                                          focus: _focus,
                                          onOpen: _open),
                                    })))),
                    SizedBox(
                        height: footer,
                        child: Center(
                            child: sheet == 0
                                ? null
                                : Text('$sheet/$sheets',
                                    style: FloorPop.readout(14,
                                        color: pop.haze)))),
                  ]);
                })));
  }
}

const _kPageMaxWidth = 520.0, _kColumns = 3;
// A sheet's padding and the gap between pockets.
const _kPad = 10.0, _kGap = 8.0;

// The rows of square pockets that fill a sheet's [width] by [height], at
// least three, and their side: as wide as three across allow, shrunk a touch
// where that leaves the last row short of the bottom.
({int rows, double side}) _grid(double width, double height) {
  final across = (width - (_kColumns - 1) * _kGap) / _kColumns;
  final rows = math.max(3, ((height + _kGap) / (across + _kGap)).round());
  return (
    rows: rows,
    side: math.max(0, math.min(across, (height - (rows - 1) * _kGap) / rows))
  );
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
        final side = math.min(box.maxHeight - 32, box.maxWidth * .52);
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
          if (pockets.length > 2) card(pockets[2], .16, .3),
          if (pockets.length > 1) card(pockets[1], -.16, -.3),
          card(pockets[0], 0, 0),
        ]));
      });
}

class _Sheet extends StatelessWidget {
  const _Sheet(
      {required this.sheet,
      required this.side,
      required this.onOpen,
      this.focus});
  final BinderSheet sheet;
  // A pocket's side, from [_grid].
  final double side;
  final ValueChanged<BinderPocket> onOpen;
  final ({String song, String difficulty})? focus;

  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
          color: FloorPop.of(context).riser,
          borderRadius: BorderRadius.circular(20)),
      child: Padding(
          padding: const EdgeInsets.all(_kPad),
          child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                  width: _kColumns * side + (_kColumns - 1) * _kGap,
                  child: Wrap(spacing: _kGap, runSpacing: _kGap, children: [
                    for (final pocket in sheet.pockets)
                      SizedBox.square(
                          dimension: side,
                          child: _Pocket(
                              pocket: pocket,
                              onOpen: onOpen,
                              focused: pocket.song.name == focus?.song &&
                                  pocket.difficulty == focus?.difficulty)),
                  ])))));
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
