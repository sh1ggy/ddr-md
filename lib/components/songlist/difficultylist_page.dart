/// Name: DifficultyListPage
/// Parent: Main
/// Description: Rendering out difficulty folders and preparing
/// song list and favourites list to pass to children widgets.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/favlist_page.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/components/songlist/sort_menu_button.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:provider/provider.dart';

class SongItem {
  SongItem({
    required this.songInfo,
    required this.isFav,
    this.defaultDifficultyIndex,
  });

  SongInfo songInfo;
  bool isFav;
  // chosenDifficulty index to open the song at, when a single level filter
  // is active and matches one of this song's difficulty types.
  int? defaultDifficultyIndex;
}

enum _ActiveFilterPanel {
  name,
  level,
  version,
}

class DifficultyListPage extends StatefulWidget {
  const DifficultyListPage({super.key});
  @override
  State<DifficultyListPage> createState() => _DifficultyListPageState();
}

class _DifficultyListPageState extends State<DifficultyListPage> {
  Future<List<SongItem>>? _songItemsPromise;
  final List<SongInfo> _searchResults = [];
  int favCount = 0;
  final Set<int> _selectedLevels = <int>{};
  final Set<String> _selectedVersionBuckets = <String>{};
  String? _selectedNameBucket;
  _ActiveFilterPanel? _activeFilterPanel;

  static const List<String> _versionBuckets = <String>[
    'Classic (1st - X3)',
    'White (2013 - A)',
    'Gold (A20 - World)',
  ];

  static const List<String> _nameBuckets = <String>[
    'a (hiragana)',
    '#',
    'a-c',
    'd-f',
    'g-i',
    'j-l',
    'm-o',
    'p-r',
    's-u',
    'v-z',
  ];

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

  List<int> songLevels(SongInfo song, Modes mode) {
    final Difficulty songDifficulty =
        mode == Modes.singles ? song.singles : song.doubles;
    return <int?>[
      songDifficulty.beginner,
      songDifficulty.easy,
      songDifficulty.medium,
      songDifficulty.hard,
      songDifficulty.challenge,
    ]
        .whereType<int>()
        .where((level) => level >= 1 && level <= constants.maxDifficulty)
        .toSet()
        .toList();
  }

  String versionBucketFor(String version) {
    const classic = <String>{
      'DDR',
      'DDR 2nd',
      'DDR 3rd',
      'DDR 4th',
      'DDR 5th',
      'DDR MAX',
      'DDR MAX2',
      'DDR EXTREME',
      'DDR SuperNOVA',
      'DDR SuperNOVA2',
      'DDR X',
      'DDR X2',
      'DDR X3',
    };
    const white = <String>{
      'DDR 2013',
      'DDR 2014',
      'DDR A',
    };
    const gold = <String>{
      'DDR A20',
      'DDR A20 PLUS',
      'DDR A3',
      'DDR World',
    };

    if (classic.contains(version)) return 'Classic (1st - X3)';
    if (white.contains(version)) return 'White (2013 - A)';
    if (gold.contains(version)) return 'Gold (A20 - World)';
    return 'Classic (1st - X3)';
  }

  String nameBucketFor(SongInfo song) {
    final String title = song.title.trim();
    // Treat this bucket as "contains Japanese" anywhere in title.
    if (title.isNotEmpty &&
        RegExp(r'[\u3040-\u30FF\u4E00-\u9FFF\uFF66-\uFF9F]')
            .hasMatch(title)) {
      return 'a (hiragana)';
    }

    final String key =
        (song.titletranslit.isNotEmpty ? song.titletranslit : song.title)
            .trim()
            .toLowerCase();
    if (key.isEmpty) return '#';

    final String first = key[0];
    if (!RegExp(r'[a-z]').hasMatch(first)) return '#';
    if ('abc'.contains(first)) return 'a-c';
    if ('def'.contains(first)) return 'd-f';
    if ('ghi'.contains(first)) return 'g-i';
    if ('jkl'.contains(first)) return 'j-l';
    if ('mno'.contains(first)) return 'm-o';
    if ('pqr'.contains(first)) return 'p-r';
    if ('stu'.contains(first)) return 's-u';
    return 'v-z';
  }

  bool songMatchesFilters(SongInfo song, Modes mode) {
    final bool levelMatch = _selectedLevels.isEmpty ||
        songLevels(song, mode).any((int level) => _selectedLevels.contains(level));

    final bool versionMatch = _selectedVersionBuckets.isEmpty ||
        _selectedVersionBuckets.contains(versionBucketFor(song.version));

    final bool nameMatch =
        _selectedNameBucket == null || _selectedNameBucket == nameBucketFor(song);

    return levelMatch && versionMatch && nameMatch;
  }

  String levelFilterSummary() {
    if (_selectedLevels.isEmpty) return 'All';
    final sorted = _selectedLevels.toList()..sort();
    if (sorted.length == 1) return 'Level ${sorted.first}';
    return '${sorted.length} selected';
  }

  String versionFilterSummary() {
    if (_selectedVersionBuckets.isEmpty) return 'All';
    if (_selectedVersionBuckets.length == 1) {
      return _selectedVersionBuckets.first;
    }
    return '${_selectedVersionBuckets.length} selected';
  }

  String nameFilterSummary() {
    return _selectedNameBucket ?? 'All';
  }

  bool get hasActiveFilters =>
      _selectedLevels.isNotEmpty ||
      _selectedVersionBuckets.isNotEmpty ||
      _selectedNameBucket != null;

  void clearAllFilters(Modes mode, SortType sortType) {
    setState(() {
      _selectedLevels.clear();
      _selectedVersionBuckets.clear();
      _selectedNameBucket = null;
    });
    regenSongItems(mode, sortType);
  }

  void toggleFilterPanel(_ActiveFilterPanel panel) {
    setState(() {
      _activeFilterPanel = _activeFilterPanel == panel ? null : panel;
    });
  }

  int primaryLevelFor(SongInfo song, Modes mode) {
    final levels = songLevels(song, mode);
    if (levels.isEmpty) return constants.maxDifficulty + 1;
    levels.sort();
    return levels.first;
  }

  Future<List<SongItem>> generateSongItems(Modes mode, SortType sortType) async {
    List<Favorite> favList = await DatabaseProvider.getAllFavorites(mode);
    setState(() {
      favCount = favList.length;
    });

    // Only a single selected level unambiguously implies a difficulty type
    // to default to when opening a song.
    final int? filteredLevel =
        _selectedLevels.length == 1 ? _selectedLevels.first : null;

    List<SongItem> songItems = [];
    for (SongInfo song in Songs.list) {
      if (!songMatchesFilters(song, mode)) {
        continue;
      }
      bool isFav =
          favList.any((Favorite fav) => fav.songTitle == song.titletranslit);

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

    switch (sortType) {
      case SortType.level:
        songItems.sort((a, b) {
          final byLevel = primaryLevelFor(a.songInfo, mode)
              .compareTo(primaryLevelFor(b.songInfo, mode));
          return byLevel != 0
              ? byLevel
              : compareSongInfo(a.songInfo, b.songInfo, SortType.title);
        });
        break;
      case SortType.title:
        songItems.sort(
            (a, b) => compareSongInfo(a.songInfo, b.songInfo, SortType.title));
        break;
      case SortType.version:
        songItems.sort((a, b) =>
            compareSongInfo(a.songInfo, b.songInfo, SortType.version));
        break;
    }
    return songItems;
  }

  void regenSongItems(Modes mode, SortType sortType) {
    setState(() {
      _songItemsPromise = generateSongItems(mode, sortType);
    });
  }

  Modes? _lastGenMode;

  @override
  void initState() {
    super.initState();
    SongState songState = Provider.of<SongState>(context, listen: false);
    _lastGenMode = songState.modes;
    _songItemsPromise = Future<List<SongItem>>(
      () => generateSongItems(songState.modes, songState.sortType));
  }

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    // Mode is set on the settings page; rebuild the list when it changed
    // since this page last generated it.
    if (_lastGenMode != songState.modes) {
      _lastGenMode = songState.modes;
      _songItemsPromise = generateSongItems(songState.modes, songState.sortType);
    }
    return SafeArea(
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
                SortMenuButton(
                    onSorted: () =>
                        regenSongItems(songState.modes, songState.sortType)),
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
                return CustomScrollView(
                  slivers: <Widget>[
                    songSearchBar(),
                    SliverToBoxAdapter(
                      child: filterPanel(songState),
                    ),
                    SliverToBoxAdapter(
                      child: ListTile(
                        title: RichText(
                          text: TextSpan(
                            text: 'Favourites: ',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge!
                                    .color,
                                fontWeight: FontWeight.bold,
                                fontSize: 22),
                            children: <TextSpan>[
                              TextSpan(
                                  text:
                                      '$favCount song${favCount == 1 ? '' : 's'}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 19,
                                      color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const FavoriteListPage()));
                          regenSongItems(songState.modes, songState.sortType);
                        },
                      ),
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
                      ),
                    ),
                    if (songItems.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No songs match the selected filters.'),
                        ),
                      )
                    else
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

    Widget badge({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      bool compact = false,
    }) {
      return FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        visualDensity:
            compact ? const VisualDensity(horizontal: -2, vertical: -2) : null,
        side: BorderSide(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor),
        onSelected: (_) => onTap(),
      );
    }

    Widget filterTray() {
      if (_activeFilterPanel == null) return const SizedBox.shrink();

      if (_activeFilterPanel == _ActiveFilterPanel.level) {
        final levels = List<int>.generate(constants.maxDifficulty, (i) => i + 1);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final level in levels)
              badge(
                label: '$level',
                compact: true,
                selected: _selectedLevels.contains(level),
                onTap: () {
                  setState(() {
                    if (_selectedLevels.contains(level)) {
                      _selectedLevels.remove(level);
                    } else {
                      _selectedLevels.add(level);
                    }
                  });
                  regenSongItems(songState.modes, songState.sortType);
                },
              ),
            badge(
              label: 'X',
              compact: true,
              selected: false,
              onTap: () => clearAllFilters(songState.modes, songState.sortType),
            ),
          ],
        );
      }

      if (_activeFilterPanel == _ActiveFilterPanel.version) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final bucket in _versionBuckets)
              badge(
                label: bucket,
                selected: _selectedVersionBuckets.contains(bucket),
                onTap: () {
                  setState(() {
                    if (_selectedVersionBuckets.contains(bucket)) {
                      _selectedVersionBuckets.remove(bucket);
                    } else {
                      _selectedVersionBuckets.add(bucket);
                    }
                  });
                  regenSongItems(songState.modes, songState.sortType);
                },
              ),
            badge(
              label: 'X',
              selected: false,
              onTap: () => clearAllFilters(songState.modes, songState.sortType),
            ),
          ],
        );
      }

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          badge(
            label: 'All',
            selected: _selectedNameBucket == null,
            onTap: () {
              setState(() {
                _selectedNameBucket = null;
              });
              regenSongItems(songState.modes, songState.sortType);
            },
          ),
          for (final bucket in _nameBuckets)
            badge(
              label: bucket,
              selected: _selectedNameBucket == bucket,
              onTap: () {
                setState(() {
                  _selectedNameBucket = bucket;
                });
                regenSongItems(songState.modes, songState.sortType);
              },
            ),
        ],
      );
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
                topButton(
                  label: 'Name',
                  value: nameFilterSummary(),
                  active: _activeFilterPanel == _ActiveFilterPanel.name,
                  onPressed: () => toggleFilterPanel(_ActiveFilterPanel.name),
                ),
                const SizedBox(width: 8),
                topButton(
                  label: 'Level',
                  value: levelFilterSummary(),
                  active: _activeFilterPanel == _ActiveFilterPanel.level,
                  onPressed: () => toggleFilterPanel(_ActiveFilterPanel.level),
                ),
                const SizedBox(width: 8),
                topButton(
                  label: 'Version',
                  value: versionFilterSummary(),
                  active: _activeFilterPanel == _ActiveFilterPanel.version,
                  onPressed: () => toggleFilterPanel(_ActiveFilterPanel.version),
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
