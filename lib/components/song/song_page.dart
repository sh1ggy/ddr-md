/// Name: SongPage
/// Parent: SongListItem
/// Description: Page that displays selected song information
library;

import 'package:ddr_md/components/song/history_page.dart';
import 'package:ddr_md/components/song/notes/chart_preview_page.dart';
import 'package:ddr_md/components/song/scores/score_card.dart';
import 'package:ddr_md/components/song/song_chart.dart';
import 'package:ddr_md/components/song/song_details.dart';
import 'package:ddr_md/components/song/song_bpm.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:flutter/services.dart';
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
  grooveRadar,
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

  late List<SongSection> _sectionOrder;

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
    setState(() {
      latestNote = initNote;
    });
  }

  void initScore(String songTitleTranslit, Modes mode) async {
    Score? initScore =
        await DatabaseProvider.getLatestScoreBySong(songTitleTranslit, mode);
    setState(() {
      latestScore = initScore;
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
      initFav(songInfo.titletranslit, songState.modes);
      initNote(songInfo.titletranslit, songState.modes);
      initScore(songInfo.titletranslit, songState.modes);
      // Set variables based on state
      if (songInfo.perChart) {
        setState(() {
          _chart = songInfo
              .charts[chosenDifficulty.clamp(0, songInfo.charts.length - 1)];
        });
      } else {
        setState(() {
          // First index because no individual chart information
          _chart = songInfo.charts.first;
        });
      }
      setState(() {
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

    final difficultyLevel =
        (mode == Modes.singles ? songInfo.singles : songInfo.doubles)
            .toJson()[diffKey] as int?;
    final diffColor = difficultyColor(diffKey);
    // The in-game name (BASIC/DIFFICULT/EXPERT…), not the StepMania-style data
    // key — "medium" is a field name, never something a player sees.
    final diffLabel = kInGameDifficultyNames[diffKey] ??
        (diffKey.isEmpty
            ? ""
            : diffKey[0].toUpperCase() + diffKey.substring(1));

    return FutureBuilder<SongSteps?>(
      future: _stepsFuture,
      builder: (context, snapshot) {
        final steps = snapshot.data?.chartFor(mode, diffKey);
        if (steps == null || steps.notes.isEmpty) {
          return const SizedBox.shrink();
        }
        // Padded here rather than around the FutureBuilder so a song with no
        // generated steps leaves no gap above the sections below.
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChartPreviewPage(
                    stepsFuture: _stepsFuture!,
                    mode: mode,
                    difficultyKey: diffKey,
                    difficultyLevel: difficultyLevel,
                    title: songInfo.title,
                    songLength: songInfo.songLength,
                    chartBpm: _chart.dominantBpm,
                    minBpm: _chart.trueMin,
                    maxBpm: _chart.trueMax,
                    bpms: _chart.bpms,
                    stops: _chart.stops,
                    // The same measured sync this page's Sync card shows
                    // (cabinet block when present, else simfile), so ARCADE
                    // SYNC can report the song's own bias.
                    sync: songInfo.displaySyncFor(_chart),
                  ),
                ),
              );
            },
            child: ListTile(
              // Matches the ExpansionTile cards' tilePadding, so every section
              // header starts and ends on the same x.
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              // Same header shape as the Sync card.
              title: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    "Chart Preview",
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    difficultyLevel != null
                        ? "$diffLabel $difficultyLevel"
                        : diffLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: diffColor,
                    ),
                  ),
                ],
              ),
              // Not the neighbours' expand_more: this row pushes a route
              // instead of expanding in place.
              trailing: Icon(
                Icons.chevron_right,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
          ),
        );
      },
    );
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
        // Gated on what the card actually displays, not on the simfile block
        // alone — a song carrying only the cabinet fingerprint still has an
        // offset to recommend.
        if (songInfo.displaySyncFor(_chart) == null) return null;
        return SongSyncChart(songInfo: songInfo, chart: _chart);
      case SongSection.grooveRadar:
        final radar =
            songInfo.radarFor(songState.modes, songState.chosenDifficulty);
        if (radar == null) return null;
        return SongRadarChart(radar: radar);
      case SongSection.bpmGraph:
        if (!_isBpmChange && _chart.stops.isEmpty) return null;
        return SongChart(
            context: context, songInfo: songInfo, chart: _chart);
      case SongSection.latestScore:
        return GestureDetector(
          onTap: () => openHistory(HistoryPage.scoresTab),
          child: latestScore != null
              ? ScoreCard(score: latestScore!, header: "Latest Score")
              : const NoScoreCard(),
        );
      case SongSection.latestNote:
        if (latestNote == null) return null;
        return GestureDetector(
          onTap: () => openHistory(HistoryPage.notesTab),
          child: Card(
            child: ListTile(
              title: Column(
                children: [
                  Text(
                    "Latest Note",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary),
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
            child: card,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(
              appBar: AppBar(
                  surfaceTintColor: Colors.black,
                  shadowColor: Colors.black,
                  elevation: 2,
                  centerTitle: true,
                  title: const Text(
                    "Song",
                    style: TextStyle(
                        fontSize: 20,
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w600),
                  ),
                  iconTheme: const IconThemeData(color: Colors.blueGrey),
                  actions: <Widget>[
                    IconButton(
                        icon: Icon(
                          favorite == null ? Icons.star_border : Icons.star,
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
                    IconButton(
                      icon: const Icon(Icons.history),
                      tooltip: "History",
                      onPressed: () => openHistory(HistoryPage.notesTab),
                    )
                  ]),
              body: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: Column(
                    children: [
                      Text(
                        songState.songInfo!.title,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.1,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (songState.songInfo!.titletranslit.isNotEmpty &&
                          songState.songInfo!.titletranslit !=
                              songState.songInfo!.title)
                        Text(
                          songState.songInfo!.titletranslit,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.0,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      if (songState.songInfo!.artist.isNotEmpty)
                        Text(
                          songState.songInfo!.artist,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.0,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: 10),
                      SongDetails(songInfo: songState.songInfo!, chart: _chart),
                      const SizedBox(height: 10),
                      // Pinned above the draggable sections so the page's
                      // primary action always opens from the same place.
                      _buildChartPreviewButton(songState),
                      _buildReorderableSections(songState),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
