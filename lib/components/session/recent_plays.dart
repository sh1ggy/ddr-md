/// Name: RecentPlays
/// Parent: SessionPage
/// Description: The e-amusement plays a sync has seen, newest first, grouped
/// into sets: runs of plays with no break longer than [kSetBreak], so one
/// visit to the arcade reads as one set. Home shows the latest few under
/// [RecentPlaysCard]; [RecentPlaysPage] has every one kept.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song/scores/score_card.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

const kSetBreak = Duration(hours: 1);

/// [plays] (newest first) split wherever two plays are more than [gap] apart.
List<List<RecentPlay>> groupPlaySets(List<RecentPlay> plays,
    [Duration gap = kSetBreak]) {
  final sets = <List<RecentPlay>>[];
  for (final p in plays) {
    if (sets.isEmpty || sets.last.last.playedAt.difference(p.playedAt) > gap) {
      sets.add([p]);
    } else {
      sets.last.add(p);
    }
  }
  return sets;
}

typedef _Loaded = ({List<RecentPlay> plays, Map<String, int?> bests});

Future<_Loaded> _load({int? limit}) async => (
      plays: await DatabaseProvider.getRecentPlays(limit: limit),
      bests: {
        for (final r
            in await DatabaseProvider.getScoreRecords(ScoreRecordSource.eamuse))
          r.id: r.score
      },
    );

/// Home's latest set, a few plays of it, and a way to the rest.
class RecentPlaysCard extends StatelessWidget {
  const RecentPlaysCard({super.key});

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<EamuseSyncState>();
    return FutureBuilder<_Loaded>(
      key: ValueKey(sync.revision),
      // Enough to hold the latest set's start for its header.
      future: _load(limit: 50),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        if (data.plays.isEmpty) {
          // Synced before plays were kept: one more sync fills the history.
          if (sync.charts == 0) return const SizedBox.shrink();
          final signedOut = sync.status == EamuseStatus.signedOut;
          return Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: ListTile(
              title: const Text('Recent plays'),
              subtitle: Text(
                  signedOut ? 'Sign in above to load them' : 'Not loaded yet'),
              trailing: signedOut
                  ? null
                  : FilledButton.tonal(
                      onPressed: sync.status == EamuseStatus.syncing
                          ? null
                          : sync.sync,
                      child: const Text('Load'),
                    ),
            ),
          );
        }
        final latest = groupPlaySets(data.plays).first;
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                      child: Text('Recent plays',
                          style: Theme.of(context).textTheme.titleMedium)),
                  TextButton(
                    onPressed: () => context.push('/home/recent'),
                    child: const Text('See more'),
                  ),
                ]),
                _SetHeader(latest),
                for (final p in latest.take(_shown))
                  _PlayRow(play: p, best: data.bests[p.recordId]),
              ],
            ),
          ),
        );
      },
    );
  }
}

class RecentPlaysPage extends StatelessWidget {
  const RecentPlaysPage({super.key});

  @override
  Widget build(BuildContext context) {
    final revision = context.select<EamuseSyncState, int>((s) => s.revision);
    return Scaffold(
      appBar: AppBar(title: const Text('Recent plays')),
      body: FutureBuilder<_Loaded>(
        key: ValueKey(revision),
        future: _load(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) return const SizedBox.shrink();
          if (data.plays.isEmpty) {
            return const Center(child: Text('No plays synced yet.'));
          }
          final sets = groupPlaySets(data.plays);
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              for (final set in sets)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SetHeader(set),
                        for (final p in set)
                          _PlayRow(play: p, best: data.bests[p.recordId]),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _time(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

/// A set's day, time span and how many plays and new bests it holds.
class _SetHeader extends StatelessWidget {
  const _SetHeader(this.set);

  final List<RecentPlay> set;

  @override
  Widget build(BuildContext context) {
    final start = set.last.playedAt.toLocal();
    final end = set.first.playedAt.toLocal();
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
    final day = switch (days) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => formatPlayDate(start),
    };
    final span =
        set.length == 1 ? _time(start) : '${_time(start)}–${_time(end)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$day · $span · ${set.length} ${set.length == 1 ? 'play' : 'plays'}',
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _PlayRow extends StatelessWidget {
  const _PlayRow({required this.play, required this.best});

  final RecentPlay play;
  // The chart's synced best, to mark the play that set it.
  final int? best;

  @override
  Widget build(BuildContext context) {
    final song = Songs.list.where((s) => s.name == play.song).firstOrNull;
    final charts = song == null
        ? null
        : (play.mode == Modes.singles ? song.singles : song.doubles);
    final types = charts?.availableTypes ?? const <String>[];
    final index =
        types.indexWhere((t) => kInGameDifficultyNames[t] == play.difficulty);
    final level = index < 0 ? null : charts!.toJson()[types[index]] as int?;
    final isBest = play.score != null && best != null && play.score! >= best!;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: song == null
          ? null
          : () {
              final songState = context.read<SongState>();
              if (songState.modes != play.mode) songState.setMode(play.mode);
              context.push(songPath(song, difficulty: index < 0 ? 0 : index));
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text(song?.title ?? play.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (isBest)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('BEST',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary)),
                ),
              const SizedBox(width: 8),
              Text(_time(play.playedAt.toLocal()),
                  style: TextStyle(fontSize: 12, color: muted)),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              Text(play.mode == Modes.singles ? 'SP' : 'DP',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: muted)),
              const SizedBox(width: 6),
              DifficultyLabel(
                  difficulty: play.difficulty,
                  level: level,
                  height: kSongListLevelHeight),
              const Spacer(),
              if (play.score != null)
                ScoreBadges(score: play.score!, dense: true),
            ]),
          ],
        ),
      ),
    );
  }
}
