/// Name: ScoresTab
/// Parent: HistoryPage
/// Description: Tab that displays the timeline of saved scores for the
/// current song, most recent first. Scores are added from the OCR pages.
library;

import 'package:ddr_md/components/song/scores/score_card.dart';
import 'package:ddr_md/components/song/scores/score_details_page.dart';
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

  void _refreshScores() {
    var songState = Provider.of<SongState>(context, listen: false);
    setState(() {
      _scoresPromise = DatabaseProvider.getAllScoresBySong(
          songState.songInfo!.titletranslit, songState.modes);
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
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) => _refreshScores());
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
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('No scores...'));
          }
          return ListView(
            children: snapshot.data!
                .map<Widget>((Score score) => ScoreCard(
                      score: score,
                      onTap: () => _openDetails(score),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}
