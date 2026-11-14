/// Name: ScoresTab
/// Parent: HistoryPage
/// Description: Tab that displays the timeline of saved scores for the
/// current song, most recent first, under the best on each chart synced from
/// e-amusement; tapping a best opens that chart's play history. Scores are
/// added from the OCR pages.
library;

import 'package:ddr_md/components/song/scores/score_card.dart';
import 'package:ddr_md/components/song/scores/score_details_page.dart';
import 'package:ddr_md/components/song/scores/score_history.dart';
import 'package:ddr_md/components/song_json.dart' show Modes;
import 'package:ddr_md/helpers.dart'
    show difficultyOptions, kInGameDifficultyColors;
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ScoresTab extends StatefulWidget {
  const ScoresTab({
    super.key,
  });

  @override
  State<ScoresTab> createState() => ScoresTabState();
}

class ScoresTabState extends State<ScoresTab> {
  Future<List<Score>>? _scoresPromise;
  List<ScoreRecord> _records = [];
  Map<String, List<RecentPlay>> _plays = {};

  void _refreshScores() {
    var songState = Provider.of<SongState>(context, listen: false);
    setState(() {
      _scoresPromise = DatabaseProvider.getAllScoresBySong(
          songState.songInfo!.titletranslit, songState.modes);
    });
    DatabaseProvider.getScoreRecordsBySong(
            songState.songInfo!.name, songState.modes)
        .then((records) {
      final order = kInGameDifficultyColors.keys.toList();
      records.sort((a, b) =>
          order.indexOf(a.difficulty).compareTo(order.indexOf(b.difficulty)));
      if (mounted) setState(() => _records = records);
    });
    DatabaseProvider.getRecentPlaysBySong(
            songState.songInfo!.name, songState.modes)
        .then((plays) {
      final byChart = <String, List<RecentPlay>>{};
      for (final p in plays.where((p) => p.score != null)) {
        (byChart[p.difficulty] ??= []).add(p);
      }
      if (mounted) setState(() => _plays = byChart);
    });
  }

  // Opens the tapped score's details page; the score may be edited there, so
  // re-query when the route pops.
  Future<void> _openDetails(Score score) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScoreDetailsPage(score: score),
    ));
    if (mounted) _refreshScores();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((timeStamp) => _refreshScores());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
      child: FutureBuilder(
        future: _scoresPromise,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: Text('Loading...'));
          }
          if (snapshot.data!.isEmpty && _records.isEmpty) {
            return const Center(child: Text('No scores...'));
          }
          final scores = snapshot.data!;
          final header = _records.isNotEmpty ? 1 : 0;
          return ListView.builder(
            itemCount: header + scores.length,
            itemBuilder: (context, i) {
              if (i < header) return _RecordsCard(_records, _plays);
              final score = scores[i - header];
              return ScoreCard(score: score, onTap: () => _openDetails(score));
            },
          );
        },
      ),
    );
  }
}

/// Best per chart from e-amusement (and any typed-in records).
class _RecordsCard extends StatelessWidget {
  final List<ScoreRecord> records;
  final Map<String, List<RecentPlay>> plays;
  const _RecordsCard(this.records, this.plays);

  @override
  Widget build(BuildContext context) {
    final songState = Provider.of<SongState>(context, listen: false);
    final levels = {
      for (final (name, level) in difficultyOptions(
          songState.modes == Modes.singles
              ? songState.songInfo!.singles
              : songState.songInfo!.doubles))
        name: level
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('Best',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary)),
            ),
            const SizedBox(height: 6),
            for (final (i, r) in records.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ScoreRecordRow(
                  record: r,
                  level: levels[r.difficulty],
                  onTap: () => showScoreHistory(
                      context,
                      [
                        for (final r in records)
                          (
                            record: r,
                            level: levels[r.difficulty],
                            plays: plays[r.difficulty] ?? const <RecentPlay>[]
                          )
                      ],
                      i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
