/// Name: SongPage
/// Parent: Router (/songs/song/:name)
/// Description: Page that displays selected song information
library;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/song/history_page.dart';
import 'package:ddr_md/components/song/notes/chart_preview_page.dart';
import 'package:ddr_md/components/song/scores/score_card.dart';
import 'package:ddr_md/components/song/song_chart.dart';
import 'package:ddr_md/components/song/song_details.dart';
import 'package:ddr_md/components/song/song_patterns.dart';
import 'package:ddr_md/components/song/song_player_sync.dart';
import 'package:ddr_md/components/song/song_bpm.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/pattern_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// The song page's reorderable sections, in their default top-to-bottom order.
/// The declaration order IS the default layout, and each name is the id
/// persisted to [Settings.songSectionOrderKey] — so renaming a value resets
/// that section's saved position.
///
/// The page header and the Chart Preview row are absent: both are pinned above
/// the reorderable list and cannot be moved.
enum SongSection {
  speedMod,
  sync,
  playerSync,
  patterns,
  bpmGraph,
  latestScore,
  latestNote,
}

/// The saved section order, repaired against the sections this build of the
/// app actually knows about: ids no longer in [SongSection] are dropped, and
/// any section missing from the saved list is appended in its default
/// position. Returns the default order when nothing is saved.
List<SongSection> readSongSectionOrder() {
  final saved = Settings.getString(Settings.songSectionOrderKey);
  if (saved.isEmpty) return SongSection.values.toList();

  final byName = {for (final s in SongSection.values) s.name: s};
  final order = <SongSection>[];
  for (final id in saved.split(',')) {
    final section = byName[id];
    if (section != null && !order.contains(section)) order.add(section);
  }
  for (final section in SongSection.values) {
    if (!order.contains(section)) order.add(section);
  }
  return order;
}

/// [order] with the section at [oldIndex] of [visible] moved to [newIndex] of
/// [visible], as a new list.
///
/// The lists differ because sections with nothing to show are not rendered: the
/// user drags among [visible], but the saved layout is the full [order]. The
/// move is resolved against the dragged card's new NEIGHBOUR rather than a raw
/// index, so hidden sections keep their relative placement.
///
/// [newIndex] is a final position (as delivered by `onReorderItem`), not an
/// insertion point.
List<SongSection> reorderSongSections({
  required List<SongSection> order,
  required List<SongSection> visible,
  required int oldIndex,
  required int newIndex,
}) {
  if (oldIndex == newIndex) return List<SongSection>.from(order);

  final moved = visible[oldIndex];
  final target = visible[newIndex];
  final next = List<SongSection>.from(order);
  next.remove(moved);
  final anchor = next.indexOf(target);
  next.insert(newIndex > oldIndex ? anchor + 1 : anchor, moved);
  return next;
}

class SongPage extends StatefulWidget {
  const SongPage({super.key});

  @override
  State<SongPage> createState() => _SongPageState();
}

class _SongPageState extends State<SongPage> {
  // Late initialisation of chart-related data
  late bool _isBpmChange;
  late Chart _chart;
  late int _chosenReadSpeed;
  late int _nearestModIndex;

  Favorite? favorite;
  Note? latestNote;
  Score? latestScore;
  List<ScoreRecord> records = [];

  late List<SongSection> _sectionOrder;

  // The hero's title flies up into the header as the page scrolls. The hero
  // keeps an invisible copy for layout; the one drawn over the page moves
  // between the two spots with the scroll.
  final _scroll = ScrollController();
  final _stackKey = GlobalKey();
  final _titleKey = GlobalKey();
  // Where the hero's title sits in the page stack at scroll 0.
  Rect? _titleRest;

  void _measureTitle() {
    final title = _titleKey.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (title == null || stack == null || !title.attached) return;
    final scrolled = _scroll.hasClients ? _scroll.offset : 0.0;
    final rest = (title.localToGlobal(Offset.zero, ancestor: stack) +
            Offset(0, scrolled)) &
        title.size;
    if (rest != _titleRest) setState(() => _titleRest = rest);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Lazily-loaded per-song note streams for the scrolling chart preview. Keyed
  // by song name so it reloads only when the song changes, not on every
  // difficulty/mode toggle (one file holds all difficulties).
  String? _stepsSongName;
  Future<SongSteps?>? _stepsFuture;

  void _loadStepsFor(SongInfo songInfo) {
    if (_stepsSongName == songInfo.name) return;
    _stepsSongName = songInfo.name;
    _stepsFuture = StepsLoader.load(songInfo.name);
  }

  // Same lazy per-song load as the steps, held as a value so the section can
  // be left out entirely when there is no analysis.
  String? _patternsSongName;
  SongPatterns? _patterns;

  Future<void> _loadPatternsFor(SongInfo songInfo) async {
    if (_patternsSongName == songInfo.name) return;
    _patternsSongName = songInfo.name;
    _patterns = null;
    final patterns = await PatternsLoader.load(songInfo.name);
    if (!mounted || _patternsSongName != songInfo.name) return;
    setState(() => _patterns = patterns);
  }

  void initFav(String songTitleTranslit, Modes mode) async {
    Favorite? initFav =
        await DatabaseProvider.getFavoriteBySong(songTitleTranslit, mode);
    setState(() {
      favorite = initFav;
    });
  }

  void initNote(String songTitleTranslit, Modes mode) async {
    Note? initNote =
        await DatabaseProvider.getLatestNoteBySong(songTitleTranslit, mode);
    if (!mounted) return;
    setState(() {
      latestNote = initNote;
    });
  }

  void initScore(String songTitleTranslit, Modes mode) async {
    Score? initScore =
        await DatabaseProvider.getLatestScoreBySong(songTitleTranslit, mode);
    if (!mounted) return;
    final song = Provider.of<SongState>(context, listen: false).songInfo;
    final initRecords = song == null
        ? <ScoreRecord>[]
        : await DatabaseProvider.getScoreRecordsBySong(song.name, mode);
    if (!mounted) return;
    setState(() {
      latestScore = initScore;
      records = initRecords;
    });
  }

  // Navigate to the history page on the given tab, then refresh the
  // latest note/score cards on return.
  Future<void> openHistory(int tab) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (context) => HistoryPage(initialTab: tab)));
    if (!mounted) return;
    var songState = Provider.of<SongState>(context, listen: false);
    var songInfo = songState.songInfo;
    if (songInfo == null) return;
    initNote(songInfo.titletranslit, songState.modes);
    initScore(songInfo.titletranslit, songState.modes);
  }

  // Initialise chosen read speed and the saved section layout.
  @override
  void initState() {
    super.initState();
    _chosenReadSpeed = Settings.getInt(Settings.chosenReadSpeedKey);
    _sectionOrder = readSongSectionOrder();
  }

  // The indices address [visible], not the full order — see
  // [reorderSongSections].
  void _onReorder(List<SongSection> visible, int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final next = reorderSongSections(
      order: _sectionOrder,
      visible: visible,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );

    HapticFeedback.mediumImpact();
    setState(() => _sectionOrder = next);
    Settings.setString(
        Settings.songSectionOrderKey, next.map((s) => s.name).join(','));
  }

  // Latching onto when this class's dependencies change
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SongState songState = Provider.of<SongState>(context);
    SongInfo? songInfo = songState.songInfo;
    int chosenDifficulty = songState.chosenDifficulty;

    if (songInfo != null) {
      _loadStepsFor(songInfo);
      _loadPatternsFor(songInfo);
      initFav(songInfo.titletranslit, songState.modes);
      initNote(songInfo.titletranslit, songState.modes);
      initScore(songInfo.titletranslit, songState.modes);
      // Set variables based on state
      setState(() {
        _chart = songInfo.chartAt(songState.modes, chosenDifficulty);
        _isBpmChange = _chart.trueMax != _chart.trueMin;
        _nearestModIndex = findNearestReadSpeed(
            _chart.dominantBpm, constants.mods, _chosenReadSpeed);
      });
    }
  }

  // Button that opens the scrolling chart preview on its own page for the
  // currently selected mode + difficulty. Stays hidden until the (lazily
  // loaded) step file resolves and confirms this difficulty actually has notes,
  // so songs the pipeline hasn't generated steps for show no button.
  Widget _buildChartPreviewButton(SongState songState) {
    final songInfo = songState.songInfo;
    if (songInfo == null) return const SizedBox.shrink();

    final mode = songState.modes;
    final available =
        (mode == Modes.singles ? songInfo.singles : songInfo.doubles)
            .availableTypes;
    if (available.isEmpty) return const SizedBox.shrink();
    final diffKey =
        available[songState.chosenDifficulty.clamp(0, available.length - 1)];

    return FutureBuilder<SongSteps?>(
      future: _stepsFuture,
      builder: (context, snapshot) {
        final steps = snapshot.data?.chartFor(mode, diffKey);
        final ready = steps != null && steps.notes.isNotEmpty;
        final pop = FloorPop.of(context);
        // The page's two actions, pinned under it: open the chart, or scan a
        // result straight after playing it.
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Expanded(
                child: VoltButton(
                  onPressed: !ready
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChartPreviewPage.forChart(
                                  songInfo, mode, diffKey,
                                  stepsFuture: _stepsFuture),
                            ),
                          );
                        },
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.play_arrow_rounded, size: 26),
                    SizedBox(width: 8),
                    Text('Preview chart'),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: IconButton.filled(
                  tooltip: 'Scan a score',
                  style: IconButton.styleFrom(
                    backgroundColor: pop.riser,
                    elevation: 6,
                    shadowColor: Colors.black,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    fixedSize: const Size(56, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: () => context.go('/scan'),
                  icon: const Icon(Icons.document_scanner_outlined),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  // The synced best on the selected chart, if any.
  ScoreRecord? _bestOnChart(SongState songState) {
    final songInfo = songState.songInfo!;
    final available =
        (songState.modes == Modes.singles ? songInfo.singles : songInfo.doubles)
            .availableTypes;
    if (available.isEmpty) return null;
    final difficulty = kInGameDifficultyNames[
        available[songState.chosenDifficulty.clamp(0, available.length - 1)]];
    return records.where((r) => r.difficulty == difficulty).firstOrNull;
  }

  // The widget for one section, or null when this song has nothing to show
  // there (a constant-BPM song has no BPM Graph, and so on). Null sections are
  // left out of the reorderable list but keep their place in the saved order.
  Widget? _buildSection(SongSection section, SongState songState) {
    final songInfo = songState.songInfo!;
    switch (section) {
      case SongSection.speedMod:
        return SongBpm(
            nearestModIndex: _nearestModIndex,
            isBpmChange: _isBpmChange,
            chart: _chart);
      case SongSection.sync:
        return SongSyncChart(songInfo: songInfo, chart: _chart);
      case SongSection.playerSync:
        final available = (songState.modes == Modes.singles
                ? songInfo.singles
                : songInfo.doubles)
            .availableTypes;
        if (available.isEmpty) return null;
        return SongPlayerSync(
          songInfo: songInfo,
          chart: _chart,
          mode: songState.modes,
          difficulty: available[
              songState.chosenDifficulty.clamp(0, available.length - 1)],
        );
      case SongSection.patterns:
        final available = (songState.modes == Modes.singles
                ? songInfo.singles
                : songInfo.doubles)
            .availableTypes;
        if (available.isEmpty) return null;
        final chart = _patterns?.chartFor(
            songState.modes,
            available[
                songState.chosenDifficulty.clamp(0, available.length - 1)]);
        if (chart == null) return null;
        return SongPatternsCard(
            patterns: chart,
            chartKey: '${songInfo.name}|'
                '${songState.modes == Modes.singles ? "sp" : "dp"}|'
                '${available[songState.chosenDifficulty.clamp(0, available.length - 1)]}');
      case SongSection.bpmGraph:
        if (!_isBpmChange && _chart.stops.isEmpty) return null;
        return SongChart(context: context, songInfo: songInfo, chart: _chart);
      case SongSection.latestScore:
        return GestureDetector(
          onTap: () => openHistory(HistoryPage.scoresTab),
          child: LatestScoreLine(
              score: latestScore, best: _bestOnChart(songState)),
        );
      case SongSection.latestNote:
        if (latestNote == null) return null;
        return GestureDetector(
          onTap: () => openHistory(HistoryPage.notesTab),
          child: Card(
            child: ListTile(
              title: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sticky_note_2_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        "Latest Note",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                  ),
                  Text(
                    latestNote!.contents,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    formatDate(DateTime.parse(latestNote!.createdAt)),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ]
                    .expand((x) => [const SizedBox(height: 10), x])
                    .skip(1)
                    .toList(),
              ),
            ),
          ),
        );
    }
  }

  // The draggable stack of section cards. Long-press a card to pick it up; the
  // resulting order is saved app-wide.
  //
  // Nested inside the page's own SingleChildScrollView, so it shrink-wraps and
  // gives up scrolling to the parent — the whole page scrolls as one.
  Widget _buildReorderableSections(SongState songState) {
    final visible = <SongSection>[];
    final cards = <Widget>[];
    for (final section in _sectionOrder) {
      final card = _buildSection(section, songState);
      if (card == null) continue;
      visible.add(section);
      cards.add(
        // Keyed by section id, not list position, so the list can tell which
        // card moved.
        Padding(
          key: ValueKey(section),
          padding: const EdgeInsets.only(bottom: 10),
          child: card,
        ),
      );
    }

    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      // The cards already carry their own Material and shadow; the default
      // lift decoration would stack a second one on top mid-drag.
      proxyDecorator: (child, index, animation) => child,
      onReorderItem: (oldIndex, newIndex) =>
          _onReorder(visible, oldIndex, newIndex),
      children: [
        for (final (i, card) in cards.indexed)
          // Long-press rather than a visible grip: the cards are already
          // tappable, and a handle would compete with the chevron column.
          ReorderableDelayedDragStartListener(
            key: card.key,
            index: i,
            child: BeatIn(index: i, child: card),
          ),
      ],
    );
  }

  // The header's fill and the title over it, both following the scroll: the
  // title leaves its hero spot as the page moves and lands beside the back
  // button, shrinking to header size, by the time the jacket has scrolled
  // away. A title that wraps in the hero hands over to one ellipsised line on
  // the way.
  List<Widget> _buildFlyingTitle(String title) {
    final rest = _titleRest;
    if (rest == null) return const [];
    const travel = 96.0;
    const scale = 16 / 20;
    final style =
        FloorPop.display(20, color: Theme.of(context).colorScheme.onSurface);
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    // Clear of the back button on the left and the two actions on the right.
    final header = Rect.fromLTWH(
        kToolbarHeight,
        top + (kToolbarHeight - style.fontSize! * style.height! * scale) / 2,
        width - kToolbarHeight - 2 * (44 + 8) - 16,
        kToolbarHeight);
    return [
      AnimatedBuilder(
        animation: _scroll,
        builder: (context, _) {
          final scrolled = _scroll.hasClients ? _scroll.offset : 0.0;
          final t =
              FloorPop.settle.transform((scrolled / travel).clamp(0.0, 1.0));
          final at = Offset.lerp(
              rest.topLeft - Offset(0, scrolled), header.topLeft, t)!;
          final oneLine = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
          return Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top + kToolbarHeight,
              child: IgnorePointer(child: GlassHeader(amount: t)),
            ),
            Positioned(
              left: at.dx,
              top: at.dy,
              child: IgnorePointer(
                child: Transform.scale(
                  scale: 1 + (scale - 1) * t,
                  alignment: Alignment.topLeft,
                  child: Stack(children: [
                    Opacity(
                      opacity: 1 - oneLine,
                      child: SizedBox(
                          width: rest.width, child: Text(title, style: style)),
                    ),
                    Opacity(
                      opacity: oneLine,
                      child: SizedBox(
                        width: header.width / scale,
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ]);
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureTitle();
    });
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: SafeArea(
        top: false,
        // The page runs under the floating tab bar and clears it itself.
        bottom: false,
        child: LayoutBuilder(builder: (context, constraints) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(
              // The header is floating buttons over the page, not a bar that
              // cuts it off: the hero and cards scroll on under them.
              extendBodyBehindAppBar: true,
              appBar:
                  AppBar(backgroundColor: Colors.transparent, actions: <Widget>[
                HeaderButton(
                    icon: Icon(
                      favorite == null ? Icons.star_border : Icons.star,
                      color: favorite == null ? null : FloorPop.sun,
                    ),
                    tooltip: favorite == null ? "Favourite" : "Unfavourite",
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      SongInfo? songStateInfo = songState.songInfo;
                      if (songStateInfo == null) {
                        return;
                      }
                      if (favorite == null) {
                        Favorite fav = Favorite(
                            id: 0,
                            isFav: true,
                            songTitle: songStateInfo.titletranslit,
                            mode: songState.modes);
                        await DatabaseProvider.addFavorite(fav);
                        setState(() {
                          favorite = fav;
                        });
                      } else {
                        await DatabaseProvider.deleteFavorite(favorite!);
                        setState(() {
                          favorite = null;
                        });
                      }
                      if (context.mounted) {
                        showToast(context, "Favourite updated");
                      }
                    }),
                HeaderButton(
                  icon: const Icon(Icons.history),
                  tooltip: "History",
                  onPressed: () => openHistory(HistoryPage.notesTab),
                )
              ]),
              // The actions float over the page rather than cutting it off:
              // the scroll runs under them and ends clear of them.
              body: Stack(key: _stackKey, children: [
                SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    children: [
                      SongDetails(
                          songInfo: songState.songInfo!,
                          chart: _chart,
                          titleKey: _titleKey,
                          hideTitle: _titleRest != null),
                      Padding(
                        // Below the hero, so clear of the tab bar only.
                        padding: EdgeInsets.fromLTRB(12, 4, 12,
                            96 + MediaQuery.paddingOf(context).bottom),
                        child: _buildReorderableSections(songState),
                      ),
                    ],
                  ),
                ),
                ..._buildFlyingTitle(songState.songInfo!.title),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildChartPreviewButton(songState),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}
