/// Name: ScoresTab
/// Parent: HistoryPage
/// Description: Tab that displays the timeline of saved scores for the
/// current song, most recent first, under the best on each chart synced from
/// e-amusement. Scores are added from the OCR pages.
library;

import 'package:ddr_md/components/song/scores/score_card.dart';
import 'package:ddr_md/components/song/scores/score_details_page.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyColors;
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
          return ListView(
            children: [
              if (_records.isNotEmpty) _RecordsCard(_records),
              for (final score in snapshot.data!)
                ScoreCard(score: score, onTap: () => _openDetails(score)),
            ],
          );
        },
      ),
    );
  }
}

/// Best per chart from e-amusement (and any typed-in records).
class _RecordsCard extends StatelessWidget {
  final List<ScoreRecord> records;
  const _RecordsCard(this.records);

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Best', style: Theme.of(context).textTheme.titleSmall),
            for (final r in records)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  SizedBox(
                      width: 90,
                      child: Text(r.difficulty,
                          style: TextStyle(
                              color: kInGameDifficultyColors[r.difficulty]))),
                  Expanded(
                      child: Text([
                    '${r.score ?? '-'}',
                    r.rank,
                    if (r.clearLamp != null) r.clearLamp!.name.toUpperCase(),
                    if (r.flareRank.isNotEmpty) 'Flare ${r.flareRank}',
                  ].join('  '))),
                  Text(
                      r.source == ScoreRecordSource.eamuse ? 'e-amu' : 'manual',
                      style: small),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
