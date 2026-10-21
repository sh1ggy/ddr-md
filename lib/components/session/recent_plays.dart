/// Name: RecentPlays
/// Parent: SessionPage
/// Description: The e-amusement plays a sync has seen, newest first, grouped
/// into sets: runs of plays with no break longer than [kSetBreak], so one
/// visit to the arcade reads as one set. Home shows the latest few under
/// [RecentPlaysCard]; [RecentPlaysPage] has every one kept.
library;

import 'dart:math';

import 'package:ddr_md/components/song/card_heading.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/content_store.dart';
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

/// The song a chart's [song] name matched, the chart's index among the
/// mode's difficulties (-1 when not found) and its level.
({SongInfo? song, int index, int? level}) chartOf(
    String? song, Modes mode, String difficulty) {
  final info = Songs.list.where((s) => s.name == song).firstOrNull;
  final charts = info == null
      ? null
      : (mode == Modes.singles ? info.singles : info.doubles);
  final types = charts?.availableTypes ?? const <String>[];
  final index =
      types.indexWhere((t) => kInGameDifficultyNames[t] == difficulty);
  final level = index < 0 ? null : charts!.toJson()[types[index]] as int?;
  return (song: info, index: index, level: level);
}

({SongInfo? song, int index, int? level}) playChart(RecentPlay play) =>
    chartOf(play.song, play.mode, play.difficulty);

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
          return HomeCard(
            title: 'Recent plays',
            icon: Icons.history,
            children: [
              Row(children: [
                Expanded(
                    child: Text(signedOut
                        ? 'Sign in above to load them'
                        : 'Not loaded yet')),
                if (!signedOut)
                  FilledButton.tonal(
                    onPressed:
                        sync.status == EamuseStatus.syncing ? null : sync.sync,
                    child: const Text('Load'),
                  ),
              ]),
            ],
          );
        }
        final latest = groupPlaySets(data.plays).first;
        return HomeCard(
          title: 'Recent plays',
          icon: Icons.history,
          onMore: () => context.push('/home/recent'),
          children: [
            SetHeader(latest),
            _PlayGrid(plays: latest, bests: data.bests, rows: 2),
          ],
        );
      },
    );
  }
}

/// A Home card: a [CardHeading], See more when there's more to see, then
/// [children].
class HomeCard extends StatelessWidget {
  const HomeCard({
    super.key,
    required this.title,
    required this.icon,
    this.onMore,
    required this.children,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onMore;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 44,
              child: Row(children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CardHeading(title, icon: icon),
                  ),
                ),
                if (onMore != null)
                  TextButton(onPressed: onMore, child: const Text('See more')),
              ]),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A page pushed from Home, with the app's page header.
class HomeSubpage extends StatelessWidget {
  const HomeSubpage({super.key, required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.black,
        shadowColor: Colors.black,
        elevation: 2,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.blueGrey),
        title: Text(title,
            style: const TextStyle(
                fontSize: 20,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600)),
      ),
      body: body,
    );
  }
}

class RecentPlaysPage extends StatelessWidget {
  const RecentPlaysPage({super.key});

  @override
  Widget build(BuildContext context) {
    final revision = context.select<EamuseSyncState, int>((s) => s.revision);
    return HomeSubpage(
      title: 'Recent plays',
      body: FutureBuilder<_Loaded>(
        key: ValueKey(revision),
        future: _load(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) return const SizedBox.shrink();
          if (data.plays.isEmpty) {
            return const Center(child: Text('No plays synced yet.'));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final set in groupPlaySets(data.plays))
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SetHeader(set),
                        _PlayGrid(plays: set, bests: data.bests),
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

String _clock(DateTime t) =>
    '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')}';
String _period(DateTime t) => t.hour < 12 ? 'AM' : 'PM';
String _time(DateTime t) => formatTime12(t);

/// A set's day, time span and how many plays it holds.
class SetHeader extends StatelessWidget {
  const SetHeader(this.set, {super.key});

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
    // 3:12–5:03 PM, or 11:40 AM–1:05 PM across noon.
    final span = set.length == 1
        ? _time(start)
        : _period(start) == _period(end)
            ? '${_clock(start)}–${_time(end)}'
            : '${_time(start)}–${_time(end)}';
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

/// [plays] as cards in as many columns as fit, [rows] rows of them at most.
class _PlayGrid extends StatelessWidget {
  const _PlayGrid({required this.plays, required this.bests, this.rows});

  final List<RecentPlay> plays;
  final Map<String, int?> bests;
  final int? rows;

  static const _minWidth = 160.0;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final columns =
          max(1, ((box.maxWidth + _gap) / (_minWidth + _gap)).floor());
      final shown = rows == null ? plays : plays.take(columns * rows!).toList();
      return GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: _gap,
          crossAxisSpacing: _gap,
          mainAxisExtent: _PlayCard.height,
        ),
        itemCount: shown.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4),
        itemBuilder: (context, i) =>
            _PlayCard(play: shown[i], best: bests[shown[i].recordId]),
      );
    });
  }
}

/// One play: jacket with the title and chart beside it, then the score,
/// grade and time. A play that set the chart's best carries an up arrow in
/// its top-right corner.
class _PlayCard extends StatelessWidget {
  const _PlayCard({required this.play, required this.best});

  final RecentPlay play;
  // The chart's synced best, to mark the play that set it.
  final int? best;

  static const height = 92.0;

  @override
  Widget build(BuildContext context) {
    final (:song, :index, :level) = playChart(play);
    final isBest = play.score != null && best != null && play.score! >= best!;
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: song == null
            ? null
            : () {
                final songState = context.read<SongState>();
                if (songState.modes != play.mode) {
                  songState.setMode(play.mode);
                }
                context.push(songPath(song, difficulty: index < 0 ? 0 : index));
              },
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  _Jacket(song: play.song),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          // Clear of the badge.
                          padding: EdgeInsets.only(right: isBest ? 22 : 0),
                          child: Text(song?.title ?? play.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(children: [
                            Text(play.mode == Modes.singles ? 'SP' : 'DP',
                                style: muted.copyWith(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(width: 6),
                            DifficultyLabel(
                                difficulty: play.difficulty,
                                level: level,
                                height: kSongListLevelHeight),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ]),
                const Spacer(),
                Row(children: [
                  Expanded(
                    child: play.score == null
                        ? const SizedBox()
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _Score(play.score!),
                          ),
                  ),
                  const SizedBox(width: 6),
                  Text(_time(play.playedAt.toLocal()), style: muted),
                ]),
              ],
            ),
          ),
          if (isBest) const Positioned(top: 6, right: 6, child: BestBadge()),
        ]),
      ),
    );
  }
}

/// Marks a play that set the chart's best: an up arrow in a primary circle.
class BestBadge extends StatelessWidget {
  const BestBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Best score',
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration:
            BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        child:
            Icon(Icons.arrow_upward_rounded, size: 14, color: scheme.onPrimary),
      ),
    );
  }
}

/// A play's score and grade on one line, centred beside the row.
class _Score extends StatelessWidget {
  const _Score(this.score);

  final int score;

  @override
  Widget build(BuildContext context) {
    final grade = gradeForScore(score);
    final art = gradeIcon(grade);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(formatScore(score),
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()])),
      const SizedBox(width: 6),
      SizedBox(
        width: 34,
        height: 18,
        child: art != null
            ? Image.asset(art,
                fit: BoxFit.contain, alignment: Alignment.centerLeft)
            : Text(grade.label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ),
    ]);
  }
}

/// A song's jacket, or the song list's music note when it has none or the
/// play matched no song.
class _Jacket extends StatelessWidget {
  const _Jacket({required this.song});

  final String? song;

  static const _size = 40.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Icon(Icons.music_note, size: 24, color: scheme.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: _size,
        child: song == null
            ? fallback
            : Image(
                image: ContentStore.image('assets/jackets-160/$song.png'),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}
