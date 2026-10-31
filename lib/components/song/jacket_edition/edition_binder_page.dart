/// Name: EditionBinderPage
/// Parent: DevelopmentPage, BestRings (from the level list)
/// Description: The player's cards as a binder, in the profile's play style:
/// a cover for each level, highest first, with its charts' bests as the
/// level list's rings and its best cards fanned out, then sheets of every
/// chart at that level in title order, six across and as many rows as the
/// screen holds. Jackets alone, like a binder's sleeves. A chart without a
/// best is an empty pocket, its jacket a ghost, so the gaps show. Tapping a
/// card opens it.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/session/session_wrap.dart' show CardTally;
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/best_rings.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyNames;
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/version_group.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // The negative, when this is the hardest level played: its top score.
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
                hardestTop: ChartBests.hardestTop(song.name, mode, value)),
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
              top: pockets
                  .where((p) => p.card?.hardestTop ?? false)
                  .firstOrNull),
          for (var i = 0; i < pockets.length; i += perSheet)
            BinderSheet(level,
                pockets.sublist(i, (i + perSheet).clamp(0, pockets.length)),
                start: i),
        ];
      }(),
  ];
}

/// A chart's pocket, by song and in-game difficulty name.
typedef BinderChart = ({String song, String difficulty});

class EditionBinderPage extends StatefulWidget {
  const EditionBinderPage(
      {super.key,
      this.level,
      this.song,
      this.difficulty,
      this.arrivals = const {},
      this.haul = const []});

  /// The level to open on, else the highest.
  final int? level;

  /// A chart to open on the sheet of, its pocket picked out.
  final String? song, difficulty;

  /// Cards a session just collected or upgraded, each with what its pocket
  /// held before (null when empty). They slot into their pockets as their
  /// sheet comes up.
  final Map<BinderChart, EditionFacts?> arrivals;

  /// What those cards gained, tallied under the sheets while they arrive.
  final List<CardGain> haul;

  @override
  State<EditionBinderPage> createState() => _EditionBinderPageState();
}

class _EditionBinderPageState extends State<EditionBinderPage> {
  late Modes _mode = context.read<SongState>().modes;
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
  // Arrivals already in their pockets.
  final _landed = <BinderChart>{};
  // Turning to each sheet with arrivals in turn, until the player turns one.
  bool _touring = true;
  // Sheets' jackets decoding, by page, so a sheet the tour turns to comes up
  // whole rather than fading its jackets in under the cards landing.
  final _warmed = <int, Future<void>>{};
  // With cards arriving, held back until the sheet it opens on is warm.
  late bool _shown = widget.arrivals.isEmpty;
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
    if (at == null && widget.arrivals.isNotEmpty) {
      page = pages.indexWhere(
          (p) => p is BinderSheet && p.pockets.any((c) => _arriving(c)));
    }
    if (page < 0 && at == null && focus != null) {
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
    _warmed.clear();
    _settle(page);
    if (widget.arrivals.isNotEmpty) _warmArrivals(page);
    return pages;
  }

  Future<void> _warm(int page) => _warmed[page] ??= switch (_pages![page]) {
        final BinderSheet s => Future.wait([
            for (final p in s.pockets)
              precacheImage(SongArtwork.image(p.song.name), context,
                  onError: (_, __) {})
          ]),
        _ => Future.value(),
      };

  // The sheet it opens on first, then each other sheet with arrivals ahead
  // of the tour.
  Future<void> _warmArrivals(int page) async {
    final pages = _pages;
    await _warm(page);
    if (!mounted || _pages != pages) return;
    if (!_shown) setState(() => _shown = true);
    for (final (i, p) in pages!.indexed) {
      if (!mounted || _pages != pages) return;
      if (p is BinderSheet && p.pockets.any(_arriving)) await _warm(i);
    }
  }

  static BinderChart _chart(BinderPocket p) =>
      (song: p.song.name, difficulty: p.difficulty);

  bool _arriving(BinderPocket p) =>
      p.card != null &&
      widget.arrivals.containsKey(_chart(p)) &&
      !_landed.contains(_chart(p));

  // Once a sheet's arrivals are in, on to the next sheet with any.
  void _landedOn(Set<BinderChart> charts) {
    setState(() => _landed.addAll(charts));
    final pages = _pages!;
    final next = pages.indexWhere(
        (p) => p is BinderSheet && p.pockets.any((c) => _arriving(c)));
    if (next < 0) {
      HapticFeedback.mediumImpact();
      return;
    }
    if (!_touring) return;
    Future.wait([Future.delayed(FloorPop.beat), _warm(next)]).then((_) {
      if (!mounted || !_touring || !_controller.hasClients) return;
      if ((next - _page).abs() == 1) {
        _controller.animateToPage(next,
            duration: FloorPop.beat, curve: FloorPop.settle);
      } else {
        _controller.jumpToPage(next);
      }
    });
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Follows the profile's style, staying on the level's cover.
    final mode = context.watch<SongState>().modes;
    if (mode == _mode) return;
    if (_at case final at?) _at = (level: at.level, start: -1);
    _mode = mode;
    _focus = null;
    _ready = false;
    _pages = _perSheet = null;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Scaffold(
        appBar: AppBar(title: const Text('Binder')),
        // No spinner flashing up as cards come in, just the sheet once it's
        // ready.
        body: !_ready
            ? widget.arrivals.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : null
            : SafeArea(
                top: false,
                child: LayoutBuilder(builder: (context, box) {
                  const tabs = 44.0, footer = 28.0, margin = 8.0;
                  final haul = widget.haul.isEmpty ? 0.0 : 52.0;
                  final width = math.min(box.maxWidth, _kPageMaxWidth);
                  final grid = _grid(
                      width - 32 - 2 * _kPad,
                      box.maxHeight -
                          tabs -
                          footer -
                          haul -
                          2 * margin -
                          2 * _kPad);
                  final pages = _paginate(grid.rows * _kColumns);
                  if (!_shown) return const SizedBox.shrink();
                  // Levels with cards still to slot in, marked on their tab.
                  final waiting = {
                    for (final p in pages)
                      if (p is BinderSheet &&
                          p.pockets.any((c) => _arriving(c)))
                        p.level
                  };
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
                                          label: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                LevelNumber(
                                                    level: p.level,
                                                    difficulty: 'EXPERT',
                                                    height: 16),
                                                if (waiting.contains(p.level))
                                                  Container(
                                                      width: 7,
                                                      height: 7,
                                                      margin:
                                                          const EdgeInsets.only(
                                                              left: 5),
                                                      decoration:
                                                          const BoxDecoration(
                                                              color:
                                                                  FloorPop.volt,
                                                              shape: BoxShape
                                                                  .circle)),
                                              ]),
                                          // To the sheet a card is coming
                                          // into, else the cover.
                                          onSelected: (_) =>
                                              _controller.jumpToPage(math.max(
                                                  i,
                                                  pages.indexWhere((s) =>
                                                      s is BinderSheet &&
                                                      s.level == p.level &&
                                                      s.pockets
                                                          .any(_arriving)))))),
                            ])),
                    Expanded(
                        child: SizedBox(
                            width: width,
                            child: NotificationListener<
                                    ScrollStartNotification>(
                                onNotification: (n) {
                                  if (n.dragDetails != null) _touring = false;
                                  return false;
                                },
                                child: PageView.builder(
                                    key: ObjectKey(_controller),
                                    // The sheets either side built ahead, so
                                    // a turn doesn't wait on their cards.
                                    allowImplicitScrolling: true,
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
                                              key: ValueKey((s.level, s.start)),
                                              sheet: s,
                                              side: grid.side,
                                              showing: i == _page,
                                              focus: _focus,
                                              arrivals: {
                                                for (final c in s.pockets)
                                                  if (_arriving(c))
                                                    _chart(c): widget
                                                        .arrivals[_chart(c)],
                                              },
                                              fresh: {
                                                for (final MapEntry(
                                                      :key,
                                                      :value
                                                    )
                                                    in widget.arrivals.entries)
                                                  if (value == null) key
                                              },
                                              onLanded: _landedOn,
                                              onOpen: _open),
                                        }))))),
                    if (widget.haul.isNotEmpty)
                      SizedBox(
                          height: haul,
                          child: Center(
                              child: CardTally(widget.haul, height: 30))),
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

const _kPageMaxWidth = 520.0, _kColumns = 6;
// A sheet's padding and the gap between pockets.
const _kPad = 10.0, _kGap = 8.0;

// The rows of square pockets that fill a sheet's [width] by [height], at
// least three, and their side: as wide as six across allow, shrunk a touch
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
                              : 'Your top score at your hardest level '
                                  'turns negative.',
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

class _Sheet extends StatefulWidget {
  const _Sheet(
      {super.key,
      required this.sheet,
      required this.side,
      required this.onOpen,
      this.showing = true,
      this.focus,
      this.arrivals = const {},
      this.fresh = const {},
      this.onLanded});
  final BinderSheet sheet;
  // A pocket's side, from [_grid].
  final double side;
  final ValueChanged<BinderPocket> onOpen;
  // In view, not just built ahead: its arrivals wait for it.
  final bool showing;
  final ({String song, String difficulty})? focus;
  // Its cards still to slot in, with what their pockets held before.
  final Map<BinderChart, EditionFacts?> arrivals;
  // Charts whose card is new, tagged once in.
  final Set<BinderChart> fresh;
  final ValueChanged<Set<BinderChart>>? onLanded;

  @override
  State<_Sheet> createState() => _SheetState();
}

// The sheet's arrivals rise in from below one after another, each over what
// its pocket held, the pocket glowing as it goes in.
class _SheetState extends State<_Sheet> with SingleTickerProviderStateMixin {
  // Kept until the parent takes the arrivals in, then cleared so the sheet
  // carries on as it is rather than being built again.
  late List<int> _order = [
    for (final (i, p) in widget.sheet.pockets.indexed)
      if (widget.arrivals
          .containsKey((song: p.song.name, difficulty: p.difficulty)))
        i
  ];
  late final AnimationController _clock;
  int _in = 0;

  // The last card's glow fades out before the clock stops.
  static const _lead = .15, _flight = .35, _fade = .12;

  Interval _interval(int n) {
    final step = (1 - _lead - _flight - _fade) / math.max(1, _order.length - 1);
    return Interval(_lead + n * step, _lead + n * step + _flight,
        curve: Curves.easeOutBack);
  }

  void _tick() {
    final landed = [
      for (var n = 0; n < _order.length; n++)
        if (_clock.value >= _interval(n).end) n
    ].length;
    if (landed > _in) HapticFeedback.lightImpact();
    _in = landed;
  }

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 500 + 420 * _order.length))
      ..addListener(_tick);
    if (widget.showing) _start();
  }

  void _start() {
    if (_order.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _clock.isAnimating || _clock.isCompleted) return;
      if (MediaQuery.of(context).disableAnimations) _clock.value = 1;
      _clock.forward().whenComplete(() {
        if (mounted) widget.onLanded?.call(widget.arrivals.keys.toSet());
      });
    });
  }

  @override
  void didUpdateWidget(_Sheet old) {
    super.didUpdateWidget(old);
    if (widget.arrivals.isEmpty) _order = const [];
    if (widget.showing && !old.showing) _start();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final side = widget.side;
    final pockets = widget.sheet.pockets;
    BinderChart chart(BinderPocket p) =>
        (song: p.song.name, difficulty: p.difficulty);
    // Each pocket keyed by its chart and built the same way whether its card
    // is flying in or settled, so landing changes nothing on screen. The
    // arrivals go last, to fly over the rest.
    final arriving = {for (final (n, i) in _order.indexed) i: n};
    Widget slot(int i) {
      final pocket = pockets[i];
      final n = arriving[i];
      final before = widget.arrivals[chart(pocket)];
      return Positioned(
          key: ValueKey(chart(pocket)),
          left: (i % _kColumns) * (side + _kGap),
          top: (i ~/ _kColumns) * (side + _kGap),
          width: side,
          height: side,
          child: Stack(clipBehavior: Clip.none, children: [
            // What it held, under the card coming in.
            if (n != null && before != null)
              Positioned.fill(
                  key: const ValueKey('before'),
                  child: RepaintBoundary(
                      child: _Pocket(pocket: (
                    song: pocket.song,
                    difficulty: pocket.difficulty,
                    best: null,
                    card: before
                  ), onOpen: (_) {}, dimmed: true))),
            Positioned.fill(
                key: const ValueKey('card'),
                child: AnimatedBuilder(
                    animation: _clock,
                    builder: (context, child) {
                      var t = 1.0, glow = 0.0;
                      if (n != null) {
                        final interval = _interval(n);
                        t = interval.transform(_clock.value);
                        glow = _clock.value < interval.end
                            ? 0.0
                            : 1 -
                                ((_clock.value - interval.end) / _fade)
                                    .clamp(0.0, 1.0);
                      }
                      return Opacity(
                          opacity: t <= 0 ? 0 : 1,
                          child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.translationValues(
                                  0, (1 - t) * 420, 0)
                                ..rotateZ((1 - t) * .3)
                                ..scaleByDouble(
                                    1 + .4 * (1 - t), 1 + .4 * (1 - t), 1, 1),
                              child: DecoratedBox(
                                  decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        if (glow > 0)
                                          BoxShadow(
                                              color: FloorPop.volt
                                                  .withValues(alpha: glow),
                                              blurRadius: 18,
                                              spreadRadius: 2 + 6 * (1 - glow)),
                                      ]),
                                  child: child)));
                    },
                    child: RepaintBoundary(
                        child: _Pocket(
                            pocket: pocket,
                            onOpen: widget.onOpen,
                            fresh: widget.fresh.contains(chart(pocket)),
                            focused: pocket.song.name == widget.focus?.song &&
                                pocket.difficulty ==
                                    widget.focus?.difficulty)))),
          ]));
    }

    final rows = (pockets.length + _kColumns - 1) ~/ _kColumns;
    return DecoratedBox(
        decoration: BoxDecoration(
            color: FloorPop.of(context).riser,
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
            padding: const EdgeInsets.all(_kPad),
            child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                    width: _kColumns * side + (_kColumns - 1) * _kGap,
                    height: math.max(0, rows * side + (rows - 1) * _kGap),
                    child: Stack(clipBehavior: Clip.none, children: [
                      for (var i = 0; i < pockets.length; i++)
                        if (!arriving.containsKey(i)) slot(i),
                      for (final i in _order) slot(i),
                    ])))));
  }
}

// A sleeve: the card when collected, else the chart's jacket as a ghost.
class _Pocket extends StatelessWidget {
  const _Pocket(
      {required this.pocket,
      required this.onOpen,
      this.focused = false,
      this.dimmed = false,
      this.fresh = false});
  final BinderPocket pocket;
  final ValueChanged<BinderPocket> onOpen;
  // Picked out, as the chart the binder was opened on.
  final bool focused;
  // What a pocket held, under the card coming in to it.
  final bool dimmed;
  // A card just collected, tagged NEW.
  final bool fresh;

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
              aura: false,
              child: art));
    }
    if (dimmed) return Opacity(opacity: .5, child: sleeve);
    if (fresh) {
      return Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: sleeve),
        Positioned(
            left: -4,
            top: -6,
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: FloorPop.volt,
                    borderRadius: BorderRadius.circular(5)),
                child: Text('NEW',
                    style: FloorPop.display(9, color: FloorPop.onVolt)))),
      ]);
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
