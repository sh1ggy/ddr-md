/// Name: DifficultyListPage
/// Parent: Main
/// Description: Rendering out difficulty folders and preparing
/// song list and favourites list to pass to children widgets.
library;

import 'dart:math' show max;
import 'dart:ui' show ImageFilter;

import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/theme.dart';
import 'package:ddr_md/components/song/difficulty_label.dart'
    show LevelNumber, kGreyLevel;
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/arcade/arcade_grid_view.dart';
import 'package:ddr_md/components/songlist/arcade/song_sections.dart';
import 'package:ddr_md/components/settings/score_overview_page.dart';
import 'package:ddr_md/components/songlist/best_rings.dart';
import 'package:ddr_md/components/songlist/favlist_page.dart';
import 'package:ddr_md/components/songlist/filter_tray.dart';
import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/songlist/song_search_page.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/components/songlist/sort_menu_button.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:provider/provider.dart';

export 'package:ddr_md/components/songlist/song_item.dart';

class DifficultyListPage extends StatefulWidget {
  const DifficultyListPage({super.key});
  @override
  State<DifficultyListPage> createState() => _DifficultyListPageState();
}

class _DifficultyListPageState extends State<DifficultyListPage> {
  Future<List<SongItem>>? _songItemsPromise;
  int favCount = 0;
  SongFilter _filter = const SongFilter();
  SongFilterAxis? _activeFilterPanel;

  // Renders the songlist as the arcade jacket grid instead of the plain list.
  bool _gridMode = Settings.getInt(Settings.songlistViewModeKey) == 1;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchBarFocus = FocusNode(canRequestFocus: false);

  // Back from a song, where a favourite or score may have changed.
  void refreshRows() async {
    Modes mode = Provider.of<SongState>(context, listen: false).modes;
    final (favList, _) = await (
      DatabaseProvider.getAllFavorites(mode),
      ChartBests.load(mode)
    ).wait;
    setState(() {
      favCount = favList.length;
    });
  }

  String versionFilterSummary() {
    if (_filter.versionBuckets.isEmpty) return 'All';
    if (_filter.versionBuckets.length == 1) {
      return _filter.versionBuckets.first;
    }
    return '${_filter.versionBuckets.length} selected';
  }

  String nameFilterSummary() {
    return _filter.nameBucket ?? 'All';
  }

  bool get hasActiveFilters => !_filter.isEmpty;

  void clearAllFilters(Modes mode, SortType sortType) {
    setState(() {
      _filter = const SongFilter();
    });
    regenSongItems(mode, sortType);
  }

  /// Applies [next] and rebuilds the list. The sort is left alone — like the
  /// cabinet, filtering narrows what is shown without reordering it.
  void _applyFilter(SongFilter next, SongState songState) {
    setState(() {
      _filter = next;
    });
    regenSongItems(songState.modes, songState.sortType);
  }

  void _toggleLevel(int level, SongState songState) {
    final Set<int> levels = Set<int>.of(_filter.levels);
    if (!levels.remove(level)) levels.add(level);
    _applyFilter(
      SongFilter(
        levels: levels,
        versionBuckets: _filter.versionBuckets,
        nameBucket: _filter.nameBucket,
        favouritesOnly: _filter.favouritesOnly,
      ),
      songState,
    );
  }

  void _toggleFavouritesOnly(SongState songState) {
    _applyFilter(
      SongFilter(
        levels: _filter.levels,
        versionBuckets: _filter.versionBuckets,
        nameBucket: _filter.nameBucket,
        favouritesOnly: !_filter.favouritesOnly,
      ),
      songState,
    );
  }

  void _toggleVersionBucket(String bucket, SongState songState) {
    final Set<String> buckets = Set<String>.of(_filter.versionBuckets);
    if (!buckets.remove(bucket)) buckets.add(bucket);
    _applyFilter(
      SongFilter(
        levels: _filter.levels,
        versionBuckets: buckets,
        nameBucket: _filter.nameBucket,
        favouritesOnly: _filter.favouritesOnly,
      ),
      songState,
    );
  }

  void _selectNameBucket(String? bucket, SongState songState) {
    _applyFilter(
      SongFilter(
        levels: _filter.levels,
        versionBuckets: _filter.versionBuckets,
        nameBucket: bucket,
        favouritesOnly: _filter.favouritesOnly,
      ),
      songState,
    );
  }

  void toggleFilterPanel(SongFilterAxis panel) {
    setState(() {
      _activeFilterPanel = _activeFilterPanel == panel ? null : panel;
    });
  }

  /// The chart [song]'s row stands for under an active level filter: its
  /// hardest chart among the filtered levels, since that is the one the filter
  /// was reaching for. A song charting both 18 and 19 reads as its 19 rather
  /// than appearing twice.
  SongItem _filteredChartItem(SongInfo song, Modes mode, bool isFav) {
    final Difficulty difficulty =
        mode == Modes.singles ? song.singles : song.doubles;
    final charts = difficulty.chartsByIndex
        .where((c) => c.level >= 1 && c.level <= constants.maxDifficulty)
        .where((c) => _filter.levels.contains(c.level))
        .toList();
    if (charts.isEmpty) {
      // No chart in this mode; it sorts into the NO CHART folder.
      return SongItem(songInfo: song, isFav: isFav);
    }
    final chart = charts.reduce((a, b) => b.level > a.level ? b : a);
    return SongItem(
      songInfo: song,
      isFav: isFav,
      difficultyIndex: chart.index,
      level: chart.level,
    );
  }

  /// The best on every chart the list shows: a row's own chart, or every
  /// chart of a song row.
  static List<ChartBest?> _listedBests(List<SongItem> items, Modes mode) => [
        for (final item in items)
          for (final index in item.difficultyIndex != null
              ? [item.difficultyIndex!]
              : (mode == Modes.singles
                      ? item.songInfo.singles
                      : item.songInfo.doubles)
                  .chartsByIndex
                  .map((c) => c.index))
            ChartBests.at(item.songInfo, mode, index),
      ];

  static String _countLabel(int count, SortType sortType) {
    final String noun = sortType == SortType.level ? 'chart' : 'song';
    return '$count $noun${count == 1 ? '' : 's'}';
  }

  Future<List<SongItem>> generateSongItems(
      Modes mode, SortType sortType, bool descending) async {
    final (favList, _) = await (
      DatabaseProvider.getAllFavorites(mode),
      ChartBests.ensure(mode)
    ).wait;
    setState(() {
      favCount = favList.length;
    });

    // One row per song, except under the level sort, where a row stands for a
    // chart: a song sits in every level folder it charts. Off that sort a level
    // filter still scopes the row to the chart it was reaching for, so the row
    // opens there.
    final Set<String> favTitles = {for (final fav in favList) fav.songTitle};
    List<SongItem> songItems = [];
    for (SongInfo song in Songs.list) {
      // Resolved before the filter runs — the favourites axis needs it.
      bool isFav = favTitles.contains(song.titletranslit);
      if (!_filter.matches(song, mode, isFav: isFav)) {
        continue;
      }

      if (sortType == SortType.level) {
        songItems.addAll(
            chartItemsFor(song, mode, isFav: isFav, levels: _filter.levels));
      } else {
        songItems.add(_filter.levels.isEmpty
            ? SongItem(songInfo: song, isFav: isFav)
            : _filteredChartItem(song, mode, isFav));
      }
    }

    final int sign = descending ? -1 : 1;
    if (sortType == SortType.level) {
      // Level lives here rather than in compareSongInfo because it needs the
      // mode to know which chart set to read.
      songItems.sort((a, b) {
        final byLevel =
            sign * levelForItem(a, mode).compareTo(levelForItem(b, mode));
        return byLevel != 0
            ? byLevel
            : compareSongInfo(a.songInfo, b.songInfo, SortType.title);
      });
    } else {
      songItems.sort((a, b) => compareSongInfo(a.songInfo, b.songInfo, sortType,
          descending: descending));
    }
    return songItems;
  }

  void regenSongItems(Modes mode, SortType sortType) {
    setState(() {
      _songItemsPromise = generateSongItems(
          mode, sortType, context.read<SongState>().sortDescending);
    });
  }

  Modes? _lastGenMode;
  int? _lastSyncRevision;

  /// New songs or chart fixes were applied while this page was open.
  void _onContentUpdated() {
    final songState = context.read<SongState>();
    regenSongItems(songState.modes, songState.sortType);
  }

  @override
  void initState() {
    super.initState();
    SongState songState = Provider.of<SongState>(context, listen: false);
    _lastGenMode = songState.modes;
    _lastSyncRevision = context.read<EamuseSyncState>().revision;
    _songItemsPromise = Future<List<SongItem>>(() => generateSongItems(
        songState.modes, songState.sortType, songState.sortDescending));
    ContentStore.revision.addListener(_onContentUpdated);
  }

  @override
  void dispose() {
    ContentStore.revision.removeListener(_onContentUpdated);
    _searchController.dispose();
    _searchBarFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    // Mode is set on the settings page; rebuild the list when it changed
    // since this page last generated it.
    if (_lastGenMode != songState.modes) {
      _lastGenMode = songState.modes;
      _songItemsPromise = generateSongItems(
          songState.modes, songState.sortType, songState.sortDescending);
    }
    // A sync on Home, or a relink after a content update, changed the bests
    // while this tab stayed alive behind it.
    final syncRevision =
        context.select<EamuseSyncState, int>((s) => s.revision);
    if (_lastSyncRevision != syncRevision) {
      _lastSyncRevision = syncRevision;
      refreshRows();
    }
    final Widget page = SafeArea(
      top: false,
      // The list runs under the floating tab bar and clears it itself.
      bottom: false,
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              flexibleSpace: const GlassHeader(),
              title: PageTitle(
                'Songs',
                // Rows are charts under the level sort and songs everywhere
                // else, so the noun follows the rows.
                trailing: FutureBuilder<List<SongItem>>(
                  future: _songItemsPromise,
                  builder: (context, snapshot) => snapshot.hasData
                      ? Text(
                          _countLabel(
                              snapshot.data!.length, songState.sortType),
                          style: TextStyle(
                              color: FloorPop.of(context).haze,
                              fontWeight: FontWeight.w600,
                              fontSize: 14))
                      : const SizedBox.shrink(),
                ),
              ),
              actions: <Widget>[
                HeaderButton(
                  icon: Icon(ChartBests.shown
                      ? Icons.military_tech
                      : Icons.military_tech_outlined),
                  tooltip: ChartBests.shown ? 'Hide bests' : 'Show bests',
                  onPressed: () async {
                    await Settings.setInt(Settings.songlistHideStatsKey,
                        ChartBests.shown ? 1 : 0);
                    setState(() {});
                  },
                ),
                HeaderButton(
                  icon: Icon(_gridMode ? Icons.view_list : Icons.grid_view),
                  tooltip: _gridMode ? 'List view' : 'Grid view',
                  onPressed: _toggleViewMode,
                ),
              ],
            ),
            // The list and grid read the padding to end clear of the bars;
            // the floating search adds its height to it.
            body: Builder(builder: (context) {
              final mq = MediaQuery.of(context);
              return Stack(children: [
                MediaQuery(
                    data: mq.copyWith(
                        padding: mq.padding
                            .copyWith(bottom: mq.padding.bottom + 58)),
                    child: FutureBuilder<List<SongItem>>(
                      future: _songItemsPromise,
                      builder: (context, snapshot) {
                        // The first build waits a frame or two on the favourites
                        // query; blank reads better than a spinner flashing up.
                        if (!snapshot.hasData) return const SizedBox.shrink();

                        final List<SongItem> songItems = snapshot.data!;
                        // Search, filters, favourites and the count read the same in
                        // both views, so they are built once and handed to whichever
                        // body is showing.
                        final List<Widget> headerSlivers = <Widget>[
                          SliverToBoxAdapter(
                              child: SizedBox(
                                  height: MediaQuery.paddingOf(context).top)),
                          SliverToBoxAdapter(
                            child: filterPanel(
                                songState,
                                hasActiveFilters && ChartBests.shown
                                    ? _listedBests(songItems, songState.modes)
                                    : null),
                          ),
                          if (songItems.isEmpty)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                    'No songs match the selected filters.'),
                              ),
                            ),
                        ];

                        if (_gridMode) {
                          return ArcadeGridView(
                            songItems: songItems,
                            sortType: songState.sortType,
                            mode: songState.modes,
                            descending: songState.sortDescending,
                            leadingSlivers: headerSlivers,
                            regenFavsCallback: () => regenSongItems(
                                songState.modes, songState.sortType),
                          );
                        }

                        return CustomScrollView(
                          slivers: <Widget>[
                            ...headerSlivers,
                            if (songItems.isNotEmpty)
                              // Every row is the same height, so the list lays out by
                              // arithmetic instead of measuring rows it scrolls past.
                              SliverPrototypeExtentList.builder(
                                prototypeItem: SongListItem(
                                  songInfo: songItems.first.songInfo,
                                  isFav: false,
                                  isSearch: false,
                                  // Rows standing for a chart are cards, a
                                  // little taller.
                                  difficultyIndex:
                                      songItems.first.difficultyIndex,
                                ),
                                itemBuilder: (context, index) {
                                  final SongItem songItem = songItems[index];
                                  return SongListItem(
                                    songInfo: songItem.songInfo,
                                    isFav: songItem.isFav,
                                    isSearch: false,
                                    difficultyIndex: songItem.difficultyIndex,
                                    regenFavsCallback: refreshRows,
                                  );
                                },
                                itemCount: songItems.length,
                              ),
                            SliverToBoxAdapter(
                              child: SizedBox(
                                  height:
                                      MediaQuery.paddingOf(context).bottom + 8),
                            ),
                          ],
                        );
                      },
                    )),
                Positioned(
                    left: 0, right: 0, bottom: 0, child: songSearchBar()),
              ]);
            }),
          ),
        );
      }),
    );

    // Both views run on the app's own theme, so the grid is a layout choice
    // rather than a separate skin: the shared search bar, filter chips and
    // app bar look identical whichever body is showing.
    return page;
  }

  void _toggleViewMode() {
    setState(() {
      _gridMode = !_gridMode;
    });
    Settings.setInt(Settings.songlistViewModeKey, _gridMode ? 1 : 0);
  }

  /// The favourites chip: tap filters the list to favourites, long press opens
  /// the dedicated favourites page.
  Widget favouritesButton(SongState songState) {
    final bool active = _filter.favouritesOnly;
    return Tooltip(
      message: active
          ? 'Showing favourites only — long press to open the list'
          : 'Favourites only — long press to open the list',
      child: GestureDetector(
        onLongPress: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const FavoriteListPage()),
          );
          regenSongItems(songState.modes, songState.sortType);
        },
        child: _FilterPill(
          set: active,
          onPressed: () => _toggleFavouritesOnly(songState),
          children: [
            Icon(active ? Icons.star : Icons.star_border,
                size: 18, color: active ? Colors.redAccent : null),
            const SizedBox(width: 6),
            Text('$favCount'),
          ],
        ),
      ),
    );
  }

  Widget filterPanel(SongState songState, List<ChartBest?>? bests) {
    Widget topButton({
      required String label,
      required String value,
      required bool active,
      required VoidCallback onPressed,
    }) {
      final pop = FloorPop.of(context);
      final bool set = value != 'All';
      return _FilterPill(
        set: set,
        open: active,
        onPressed: onPressed,
        children: [
          Text('$label ',
              style: TextStyle(
                  fontWeight: FontWeight.w500, color: set ? null : pop.haze)),
          Text(value),
          const SizedBox(width: 2),
          AnimatedRotation(
            turns: active ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.expand_more, size: 18),
          ),
        ],
      );
    }

    Widget filterTray() {
      if (_activeFilterPanel == null) return const SizedBox.shrink();
      final Modes mode = songState.modes;
      final SongFilterAxis axis = _activeFilterPanel!;

      switch (axis) {
        case SongFilterAxis.version:
          return FilterTray(
            options: <FilterOption>[
              for (final bucket in kVersionBuckets)
                FilterOption(
                  label: bucket,
                  selected: _filter.versionBuckets.contains(bucket),
                  onTap: () => _toggleVersionBucket(bucket, songState),
                ),
              FilterOption(
                label: 'X',
                selected: false,
                onTap: () => clearAllFilters(mode, songState.sortType),
              ),
            ],
          );

        case SongFilterAxis.name:
          return FilterTray(
            options: <FilterOption>[
              FilterOption(
                label: 'All',
                selected: _filter.nameBucket == null,
                onTap: () => _selectNameBucket(null, songState),
              ),
              for (final bucket in kNameBuckets)
                FilterOption(
                  label: bucket,
                  selected: _filter.nameBucket == bucket,
                  onTap: () => _selectNameBucket(bucket, songState),
                ),
            ],
          );
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Level is the filter reached for most, so every level sits out in
          // the open rather than behind a pill.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _LevelGrid(
              isSelected: _filter.levels.contains,
              onTap: (level) => _toggleLevel(level, songState),
              spare: bests == null
                  ? null
                  // Opens the stats on the hardest level picked.
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ScoreOverviewPage(
                              mode: songState.modes,
                              level: _filter.levels.isEmpty
                                  ? null
                                  : _filter.levels.reduce(max)))),
                      child: BestRings(bests)),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(
              // Scrolls under the sort, which stays put on the right, fading
              // out before it.
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  colors: [Colors.black, Colors.black, Colors.transparent],
                  stops: [0, 0.88, 1],
                ).createShader(rect),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 16, right: 16),
                  child: Row(
                    children: <Widget>[
                      // Leads the row so it never hides under the sort.
                      if (hasActiveFilters) ...[
                        _FilterPill(
                          onPressed: () => clearAllFilters(
                              songState.modes, songState.sortType),
                          children: const [Icon(Icons.close, size: 18)],
                        ),
                        const SizedBox(width: 8),
                      ],
                      favouritesButton(songState),
                      const SizedBox(width: 8),
                      topButton(
                        label: 'Name',
                        value: nameFilterSummary(),
                        active: _activeFilterPanel == SongFilterAxis.name,
                        onPressed: () => toggleFilterPanel(SongFilterAxis.name),
                      ),
                      const SizedBox(width: 8),
                      topButton(
                        label: 'Version',
                        value: versionFilterSummary(),
                        active: _activeFilterPanel == SongFilterAxis.version,
                        onPressed: () =>
                            toggleFilterPanel(SongFilterAxis.version),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _SortPill(
                  onSorted: () =>
                      regenSongItems(songState.modes, songState.sortType)),
            ),
          ]),
          if (_activeFilterPanel != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: FloorPop.of(context).riser,
                borderRadius: BorderRadius.circular(16),
              ),
              child: filterTray(),
            ),
        ],
      ),
    );
  }

  // Floats above the tab bar within thumb reach, frosted like the header,
  // with the rows scrolling on under it. Read-only: a tap opens the search
  // page, whose field takes the keyboard.
  Widget songSearchBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: SearchBar(
                  controller: _searchController,
                  focusNode: _searchBarFocus,
                  readOnly: true,
                  onTap: () => Navigator.of(context).push(SongSearchPage.route(
                      _searchController,
                      regenFavsCallback: refreshRows)),
                  hintText: "Search song...",
                  constraints: const BoxConstraints(
                      maxWidth: 800.0, minHeight: 48.0, maxHeight: 48.0),
                  shape: const WidgetStatePropertyAll(StadiumBorder()),
                  backgroundColor: WidgetStatePropertyAll(
                      FloorPop.of(context).riser.withValues(alpha: 0.7)),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 14.0),
                  ),
                  leading: const Icon(Icons.search, size: 20),
                ))),
      ),
    );
  }
}

/// A filter-row pill on a riser; [set] fills it when its filter narrows the
/// list, [open] rings it while its tray is showing.
class _FilterPill extends StatelessWidget {
  const _FilterPill(
      {required this.children,
      required this.onPressed,
      this.set = false,
      this.open = false});

  final List<Widget> children;
  final VoidCallback? onPressed;
  final bool set;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fg = set ? scheme.onPrimary : scheme.onSurface;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 36,
      decoration: ShapeDecoration(
        color: set ? scheme.primary : pop.riser,
        shape: StadiumBorder(
            side: BorderSide(
                color: open ? scheme.primary : Colors.transparent,
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignOutside)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: IconTheme.merge(
              data: IconThemeData(color: fg),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                    color: fg,
                    fontFamily: kTextFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
                child: Row(mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every level at once in two rows of ten, 1–10 over 11–19, so none is ever
/// scrolled out of reach. Picked levels light up on a tile; the rest grey out.
/// [spare] takes the slot after the last level.
class _LevelGrid extends StatelessWidget {
  const _LevelGrid({required this.isSelected, required this.onTap, this.spare});

  final bool Function(int level) isSelected;
  final ValueChanged<int> onTap;
  final Widget? spare;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    final bool any =
        [for (int l = 1; l <= constants.maxDifficulty; l++) l].any(isSelected);

    Widget cell(int level) {
      if (level > constants.maxDifficulty) {
        return Expanded(
            child: Center(
                child: level == constants.maxDifficulty + 1 ? spare : null));
      }
      final bool on = isSelected(level);
      final number =
          LevelNumber(level: level, difficulty: 'EXPERT', height: 18);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: AnimatedContainer(
            duration: FloorPop.sixteenth,
            height: 34,
            decoration: BoxDecoration(
              color: on ? scheme.primary : pop.stage,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onTap(level),
                // Nothing picked means every level counts, so none greys out.
                child: Center(
                    child: on || !any
                        ? number
                        : Opacity(
                            opacity: 0.4,
                            child: ColorFiltered(
                                colorFilter: kGreyLevel, child: number))),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: pop.riser,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        for (final start in const [1, 11])
          Row(children: [for (int l = start; l < start + 10; l++) cell(l)]),
      ]),
    );
  }
}

/// The sort as one pill: the key cycles on the left, the arrow flips the
/// order on the right.
class _SortPill extends StatelessWidget {
  const _SortPill({required this.onSorted});

  final VoidCallback onSorted;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final songState = context.watch<SongState>();
    final bool descending = songState.sortDescending;
    const style = TextStyle(
        fontFamily: kTextFont, fontWeight: FontWeight.w700, fontSize: 14);
    return Material(
      color: pop.riser,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 36,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          InkWell(
            onTap: () {
              songState.setSortType(nextSortType(songState.sortType));
              onSorted();
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 8),
              child: Row(children: [
                Icon(Icons.sort, size: 18, color: pop.haze),
                const SizedBox(width: 6),
                Text(sortLabel(songState.sortType), style: style),
              ]),
            ),
          ),
          Container(width: 1, height: 18, color: pop.line),
          InkWell(
            onTap: () {
              songState.setSortDescending(!descending);
              onSorted();
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 12),
              child: Tooltip(
                message: descending ? 'Descending' : 'Ascending',
                child: Icon(
                    descending ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
