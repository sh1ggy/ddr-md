/// Name: DifficultyListPage
/// Parent: Main
/// Description: Rendering out difficulty folders and preparing
/// song list and favourites list to pass to children widgets.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/arcade/arcade_grid_view.dart';
import 'package:ddr_md/components/songlist/arcade/song_sections.dart';
import 'package:ddr_md/components/songlist/favlist_page.dart';
import 'package:ddr_md/components/songlist/filter_tray.dart';
import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/components/songlist/sort_menu_button.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
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
  final List<SongInfo> _searchResults = [];
  int favCount = 0;
  SongFilter _filter = const SongFilter();
  SongFilterAxis? _activeFilterPanel;

  // Renders the songlist as the arcade jacket grid instead of the plain list.
  bool _gridMode = Settings.getInt(Settings.songlistViewModeKey) == 1;

  // Below this similarity a result is considered noise and dropped, same
  // threshold spirit as the OCR title matcher.
  static const double _kMinSearchSimilarity = 0.3;

  // Search result handler; widgets are built lazily in suggestionsBuilder.
  // Ranks by normalized Levenshtein similarity (same as OCR title matching)
  // so close-but-not-exact spellings still sort to the top.
  void getMatch(String value) {
    value = value.trim();
    setState(() {
      _searchResults.clear();
      if (value == "") return;
      _searchResults.addAll(Songs.matchTitles(value, limit: Songs.list.length)
          .where((match) => match.similarity >= _kMinSearchSimilarity)
          .map((match) => match.song));
    });
  }

  void regenFavCount() async {
    Modes mode = Provider.of<SongState>(context, listen: false).modes;
    List<Favorite> favList = await DatabaseProvider.getAllFavorites(mode);
    setState(() {
      favCount = favList.length;
    });
  }

  String levelFilterSummary() {
    if (_filter.levels.isEmpty) return 'All';
    final sorted = _filter.levels.toList()..sort();
    if (sorted.length == 1) return 'Level ${sorted.first}';
    return '${sorted.length} selected';
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

  Future<List<SongItem>> generateSongItems(
      Modes mode, SortType sortType, bool descending) async {
    List<Favorite> favList = await DatabaseProvider.getAllFavorites(mode);
    setState(() {
      favCount = favList.length;
    });

    // Only a single selected level unambiguously implies a difficulty type
    // to default to when opening a song.
    final int? filteredLevel =
        _filter.levels.length == 1 ? _filter.levels.first : null;

    List<SongItem> songItems = [];
    for (SongInfo song in Songs.list) {
      // Resolved before the filter runs — the favourites axis needs it.
      bool isFav =
          favList.any((Favorite fav) => fav.songTitle == song.titletranslit);
      if (!_filter.matches(song, mode, isFav: isFav)) {
        continue;
      }

      final songDifficulty = mode == Modes.singles ? song.singles : song.doubles;
      final defaultDifficultyIndex = filteredLevel == null
          ? null
          : songDifficulty.chosenDifficultyForLevel(filteredLevel);

      songItems.add(SongItem(
        songInfo: song,
        isFav: isFav,
        defaultDifficultyIndex: defaultDifficultyIndex,
      ));
    }

    final int sign = descending ? -1 : 1;
    if (sortType == SortType.level) {
      // Level lives here rather than in compareSongInfo because it needs the
      // mode to know which chart set to read.
      songItems.sort((a, b) {
        final byLevel = sign *
            primaryLevelFor(a.songInfo, mode)
                .compareTo(primaryLevelFor(b.songInfo, mode));
        return byLevel != 0
            ? byLevel
            : compareSongInfo(a.songInfo, b.songInfo, SortType.title);
      });
    } else {
      songItems.sort((a, b) => compareSongInfo(
          a.songInfo, b.songInfo, sortType,
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

  @override
  void initState() {
    super.initState();
    SongState songState = Provider.of<SongState>(context, listen: false);
    _lastGenMode = songState.modes;
    _songItemsPromise = Future<List<SongItem>>(() => generateSongItems(
        songState.modes, songState.sortType, songState.sortDescending));
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
    final Widget page = SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              elevation: 2,
              title: const Text(
                'Songlist',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.blueGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: <Widget>[
                IconButton(
                  icon: Icon(_gridMode ? Icons.view_list : Icons.grid_view),
                  tooltip: _gridMode ? 'List view' : 'Grid view',
                  onPressed: _toggleViewMode,
                ),
              ],
              iconTheme: const IconThemeData(color: Colors.blueGrey),
            ),
            body: FutureBuilder<List<SongItem>>(
              future: _songItemsPromise,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final List<SongItem> songItems = snapshot.data!;
                // Search, filters, favourites and the count read the same in
                // both views, so they are built once and handed to whichever
                // body is showing.
                final List<Widget> headerSlivers = <Widget>[
                  songSearchBar(),
                  SliverToBoxAdapter(
                    child: filterPanel(songState),
                  ),
                  SliverToBoxAdapter(
                    child: ListTile(
                      title: Text(
                        '${songItems.length} song${songItems.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge!.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      trailing: SortMenuButton(
                          onSorted: () => regenSongItems(
                              songState.modes, songState.sortType)),
                    ),
                  ),
                  if (songItems.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No songs match the selected filters.'),
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
                    regenFavsCallback: () =>
                        regenSongItems(songState.modes, songState.sortType),
                  );
                }

                return CustomScrollView(
                  slivers: <Widget>[
                    ...headerSlivers,
                    if (songItems.isNotEmpty)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final SongItem songItem = songItems[index];
                            return SongListItem(
                              songInfo: songItem.songInfo,
                              isFav: songItem.isFav,
                              isSearch: false,
                              defaultDifficultyIndex:
                                  songItem.defaultDifficultyIndex,
                              regenFavsCallback: regenFavCount,
                            );
                          },
                          childCount: songItems.length,
                        ),
                      ),
                  ],
                );
              },
            ),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
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
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            shape: const StadiumBorder(),
            side: BorderSide(color: active ? scheme.primary : Theme.of(context).dividerColor),
            backgroundColor:
                active ? scheme.primary.withValues(alpha: 0.12) : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onPressed: () => _toggleFavouritesOnly(songState),
          icon: Icon(
            active ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: active ? Colors.redAccent : null,
          ),
          label: Text('$favCount'),
        ),
      ),
    );
  }

  Widget filterPanel(SongState songState) {
    Widget topButton({
      required String label,
      required String value,
      required bool active,
      required VoidCallback onPressed,
    }) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        onPressed: onPressed,
        child: Text('$label: $value'),
      );
    }

    Widget filterTray() {
      if (_activeFilterPanel == null) return const SizedBox.shrink();
      final Modes mode = songState.modes;
      final SongFilterAxis axis = _activeFilterPanel!;

      switch (axis) {
        case SongFilterAxis.level:
          return FilterTray(
            compact: true,
            options: <FilterOption>[
              for (int level = 1; level <= constants.maxDifficulty; level++)
                FilterOption(
                  label: '$level',
                  selected: _filter.levels.contains(level),
                  onTap: () => _toggleLevel(level, songState),
                ),
              FilterOption(
                label: 'X',
                selected: false,
                onTap: () => clearAllFilters(mode, songState.sortType),
              ),
            ],
          );

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
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
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
                  label: 'Level',
                  value: levelFilterSummary(),
                  active: _activeFilterPanel == SongFilterAxis.level,
                  onPressed: () => toggleFilterPanel(SongFilterAxis.level),
                ),
                const SizedBox(width: 8),
                topButton(
                  label: 'Version',
                  value: versionFilterSummary(),
                  active: _activeFilterPanel == SongFilterAxis.version,
                  onPressed: () => toggleFilterPanel(SongFilterAxis.version),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onPressed: hasActiveFilters
                      ? () => clearAllFilters(songState.modes, songState.sortType)
                      : null,
                  icon: const Icon(Icons.close),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ),
          if (_activeFilterPanel != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(14),
              ),
              child: filterTray(),
            ),
        ],
      ),
    );
  }

  SliverAppBar songSearchBar() {
    return SliverAppBar(
      floating: true,
      pinned: true,
      backgroundColor: Colors.transparent,
      flexibleSpace: SearchAnchor(
          isFullScreen: true,
          viewOnSubmitted: (value) {
            FocusScope.of(context).unfocus();
          },
          viewOnChanged: (value) => getMatch(value),
          viewHintText: "Search song...",
          builder: (BuildContext context, SearchController controller) {
            return SearchBar(
              controller: controller,
              onTap: () {
                controller.openView();
              },
              onChanged: (value) {
                controller.openView();
                getMatch(value);
              },
              hintText: "Search song...",
              constraints: const BoxConstraints(
                  minWidth: 360.0, maxWidth: 800.0, minHeight: 56.0),
              shape: WidgetStateProperty.all(const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              )),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(vertical: 5.0, horizontal: 20.0),
              ),
              leading: const Icon(Icons.search),
            );
          },
          suggestionsBuilder:
              (BuildContext context, SearchController controller) {
            if (_searchResults.isEmpty || controller.text == "") {
              return List.empty();
            }
            return _searchResults.map((song) => SongListItem(
                  songInfo: song,
                  isFav: false,
                  isSearch: true,
                  regenFavsCallback: regenFavCount,
                ));
          }),
    );
  }
}
