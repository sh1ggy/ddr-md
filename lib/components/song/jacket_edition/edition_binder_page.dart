/// Name: EditionBinderPage
/// Parent: DevelopmentPage
/// Description: Every chart the player has a best on, as its card, filed by
/// level, highest first. Each level leads with its negative (the top score
/// there), then the rest by score. Tapping a card opens it.
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

typedef _Card = ({SongInfo song, EditionFacts facts});

class EditionBinderPage extends StatefulWidget {
  const EditionBinderPage({super.key});
  @override
  State<EditionBinderPage> createState() => _EditionBinderPageState();
}

class _EditionBinderPageState extends State<EditionBinderPage> {
  late Modes _mode = context.read<SongState>().modes;
  // Cards by level, highest level first.
  List<(int, List<_Card>)>? _levels;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = _mode;
    setState(() => _levels = null);
    await ChartBests.ensure(mode);
    if (!mounted || mode != _mode) return;
    final levels = <int, List<_Card>>{};
    for (final song in Songs.list) {
      final json =
          (mode == Modes.singles ? song.singles : song.doubles).toJson();
      for (final MapEntry(:key, :value) in kInGameDifficultyNames.entries) {
        final level = json[key];
        final best = ChartBests.forChart(song.name, mode, value);
        if (level is! int || best == null) continue;
        levels.putIfAbsent(level, () => []).add((
          song: song,
          facts: EditionFacts(
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
    for (final cards in levels.values) {
      cards.sort((a, b) => a.facts.levelTop != b.facts.levelTop
          ? (a.facts.levelTop ? -1 : 1)
          : (b.facts.score ?? -1).compareTo(a.facts.score ?? -1));
    }
    setState(() => _levels = [
          for (final level in levels.keys.toList()..sort((a, b) => b - a))
            (level, levels[level]!)
        ]);
  }

  @override
  Widget build(BuildContext context) {
    final options = editionPreferences();
    final card = (
      borderId: options.borderId,
      effects: true,
      motion: false,
      modeStamp: false,
      gradeStamp: false,
      difficultyStamp: false,
      tierSuffix: false
    );
    final levels = _levels;
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
        body: levels == null
            ? const Center(child: CircularProgressIndicator())
            : levels.isEmpty
                ? const Center(
                    child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No cards yet. Charts you have a best on '
                            'land here, filed by level.')))
                : CustomScrollView(slivers: [
                    for (final (level, cards) in levels) ...[
                      SliverToBoxAdapter(
                          child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 20, 16, 10),
                              child: Row(children: [
                                LevelNumber(
                                    level: level,
                                    difficulty: 'EXPERT',
                                    height: 20),
                                const SizedBox(width: 10),
                                Text('${cards.length} '
                                    '${cards.length == 1 ? 'card' : 'cards'}'),
                              ]))),
                      SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 104,
                                      mainAxisSpacing: 14,
                                      crossAxisSpacing: 14),
                              itemCount: cards.length,
                              itemBuilder: (context, i) {
                                final (:song, :facts) = cards[i];
                                return GestureDetector(
                                    onTap: () => showEditionViewer(context,
                                        facts: facts,
                                        options: (
                                          borderId: card.borderId,
                                          effects: options.effects,
                                          motion: options.motion,
                                          modeStamp: false,
                                          gradeStamp: false,
                                          difficultyStamp: false,
                                          tierSuffix: false
                                        ),
                                        artwork: SongArtwork(
                                            songName: song.name,
                                            title: song.title,
                                            fullResolution: true,
                                            fade: Duration.zero)),
                                    child: CompactJacketEdition(
                                        facts: facts,
                                        options: card,
                                        child: SongArtwork(
                                            songName: song.name,
                                            title: song.title)));
                              })),
                    ],
                    const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                  ]));
  }
}
