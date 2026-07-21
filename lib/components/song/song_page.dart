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

  // Initialise chosen read speed.
  @override
  void initState() {
    super.initState();
    _chosenReadSpeed = Settings.getInt(Settings.chosenReadSpeedKey);
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
          _chart = songInfo.charts[
              chosenDifficulty.clamp(0, songInfo.charts.length - 1)];
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

    return FutureBuilder<SongSteps?>(
      future: _stepsFuture,
      builder: (context, snapshot) {
        final steps = snapshot.data?.chartFor(mode, diffKey);
        if (steps == null || steps.notes.isEmpty) {
          return const SizedBox.shrink();
        }
        return Card(
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
                    title: songInfo.title,
                    songLength: songInfo.songLength,
                    chartBpm: _chart.dominantBpm,
                    bpms: _chart.bpms,
                    stops: _chart.stops,
                  ),
                ),
              );
            },
            child: ListTile(
              leading: Icon(
                Icons.play_circle_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text(
                "Chart Preview",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                "Open scrolling chart for this difficulty",
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    return SafeArea(
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
                    SongBpm(
                        nearestModIndex: _nearestModIndex,
                        isBpmChange: _isBpmChange,
                        chart: _chart),
                    _buildChartPreviewButton(songState),
                    SongRadarChart(
                      radar: songState.songInfo!.radarFor(
                        songState.modes, songState.chosenDifficulty)),
                    if (_isBpmChange || _chart.stops.isNotEmpty)
                      SongChart(
                          context: context,
                          songInfo: songState.songInfo,
                          chart: _chart),
                    if (latestScore != null)
                      GestureDetector(
                        onTap: () => openHistory(HistoryPage.scoresTab),
                        child: ScoreCard(
                            score: latestScore!, header: "Latest Score"),
                      )
                    else
                      GestureDetector(
                        onTap: () => openHistory(HistoryPage.scoresTab),
                        child: const NoScoreCard(),
                      ),
                    if (latestNote != null)
                      GestureDetector(
                        onTap: () => openHistory(HistoryPage.notesTab),
                        child: Card(
                          child: ListTile(
                            title: Column(
                              children: [
                                Text(
                                  "Latest Note",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                ),
                                Text(
                                  latestNote!.contents,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  formatDate(DateTime.parse(latestNote!.createdAt)),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                ),
                              ]
                                  .expand(
                                      (x) => [const SizedBox(height: 10), x])
                                  .skip(1)
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                  ]
                      .expand((x) => [const SizedBox(height: 10), x])
                      .skip(1)
                      .toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
