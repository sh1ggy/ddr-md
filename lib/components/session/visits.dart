/// Name: Visits
/// Parent: SessionPage
/// Description: Sessions on Home, each a visit put together by
/// [buildVisits]: the last one as a card (summary, plays, timing), the rest
/// as rows, and a page per session with everything in it. A set no session
/// covers asks "Where was this?", and picking a venue records a session over
/// it.
library;

import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/session/session_page.dart';
import 'package:ddr_md/components/session/session_summary.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/visit_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

typedef VisitData = ({
  List<Visit> visits,
  ScoreModel model,
  // Each session's logged timing plays, by session id.
  Map<String, List<TimingPlay>> timing,
});

(int, int)? _loadedFor;
Future<VisitData>? _loaded;

/// Every visit, loaded once per sync or session change and shared by the
/// views showing them.
Future<VisitData> visitsFor(BuildContext context) {
  final key = (
    context.select<EamuseSyncState, int>((s) => s.revision),
    context.select<SessionState, int>((s) => s.revision),
  );
  if (key != _loadedFor) {
    _loadedFor = key;
    _loaded = _load(context.read<SessionState>().session?.id);
  }
  return _loaded!;
}

Future<VisitData> _load(String? activeId) async {
  final plays = await DatabaseProvider.getRecentPlays();
  final sessions = await DatabaseProvider.getSessions();
  final visits = buildVisits(
      plays, sessions, await DatabaseProvider.getLastCredits(),
      activeId: activeId);
  return (
    visits: visits,
    model: ScoreModel(
      plays,
      await DatabaseProvider.getScoreRecords(ScoreRecordSource.eamuse),
      (song, mode, difficulty) => chartOf(song, mode, difficulty).level,
    ),
    timing: {
      for (final s in sessions)
        s.id: await DatabaseProvider.getSessionPlays(s.id),
    },
  );
}

String _path(Visit v) => '/home/sessions/${v.key}';

double? _meanTiming(List<TimingPlay>? plays) => plays == null || plays.isEmpty
    ? null
    : plays.map((t) => t.averageMs).reduce((a, b) => a + b) / plays.length;

/// Home's latest session with plays (or the latest at all before any sync):
/// its summary and first plays.
class LastSessionCard extends StatelessWidget {
  const LastSessionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<EamuseSyncState>();
    return FutureBuilder<VisitData>(
      future: visitsFor(context),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        final visit = data.visits.where((v) => v.plays.isNotEmpty).firstOrNull;
        if (visit == null) {
          // Synced before plays were kept: one more sync fills the history.
          if (sync.charts == 0) return const SizedBox.shrink();
          final signedOut = sync.status == EamuseStatus.signedOut;
          return HomeCard(
            title: 'Last session',
            icon: Icons.insights,
            children: [
              Row(children: [
                Expanded(
                    child: Text(signedOut
                        ? 'Sign in above to load your plays'
                        : 'Plays not loaded yet')),
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
        return HomeCard(
          title: visit.session?.venue.name ?? 'Last session',
          icon: visit.session == null ? Icons.insights : Icons.place,
          onMore: () => context.push(_path(visit)),
          children: [
            CardSubtitle(
                '${visitSpan(visit.start, visit.end)} · ${playCount(visit.plays.length)}'),
            if (visit.session == null) _WhereButton(visit),
            SessionSummaryBody(
              data.model.summarize(visit.plays),
              plays: visit.plays,
              timed: visit.session != null,
              timingMs: _meanTiming(data.timing[visit.session?.id]),
            ),
            const SizedBox(height: 8),
            PlayGrid(plays: visit.plays, bests: data.model.bests, rows: 1),
          ],
        );
      },
    );
  }
}

/// Picks the venue a set was played at and records a session over it.
class _WhereButton extends StatelessWidget {
  const _WhereButton(this.visit, {this.onAdded});

  final Visit visit;
  final void Function(PlaySession)? onAdded;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        avatar: const Icon(Icons.add_location_alt_outlined, size: 18),
        label: const Text('Where was this?'),
        onPressed: () async {
          final session = await showModalBottomSheet<PlaySession>(
            context: context,
            builder: (_) => _VenueSheet(visit),
          );
          if (session != null && context.mounted) {
            context.read<SessionState>().changed();
            onAdded?.call(session);
          }
        },
      ),
    );
  }
}

class _VenueSheet extends StatefulWidget {
  const _VenueSheet(this.visit);

  final Visit visit;

  @override
  State<_VenueSheet> createState() => _VenueSheetState();
}

class _VenueSheetState extends State<_VenueSheet> {
  List<Venue>? _venues;

  @override
  void initState() {
    super.initState();
    DatabaseProvider.getVenues().then((v) => setState(() => _venues = v));
  }

  Future<void> _pick(Venue venue) async {
    final session = await DatabaseProvider.addPastSession(
        venue, widget.visit.start, widget.visit.end);
    if (mounted) Navigator.pop(context, session);
  }

  Future<void> _add() async {
    final name = await askName(context, 'New venue', 'e.g. Round1 Ludo');
    if (name == null || name.isEmpty) return;
    await _pick(_venues?.where((v) => v.name == name).firstOrNull ??
        await DatabaseProvider.addVenue(name));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Where was this?',
              style: Theme.of(context).textTheme.titleLarge),
          CardSubtitle(
              '${visitSpan(widget.visit.start, widget.visit.end)} · ${playCount(widget.visit.plays.length)}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final v in _venues ?? <Venue>[])
                ActionChip(label: Text(v.name), onPressed: () => _pick(v)),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('New venue'),
                onPressed: _add,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Home's Sessions card: start one, and the latest few.
class SessionsCard extends StatelessWidget {
  const SessionsCard({super.key});

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VisitData>(
      future: visitsFor(context),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final visits = data?.visits ?? [];
        return HomeCard(
          title: 'Sessions',
          icon: Icons.place_outlined,
          onMore: visits.length > _shown
              ? () => context.push('/home/sessions')
              : null,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start session'),
              onPressed: () => showStartSessionSheet(context),
            ),
            if (visits.isNotEmpty) const SizedBox(height: 6),
            for (final v in visits.take(_shown))
              VisitTile(v, model: data!.model),
          ],
        );
      },
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, Visit v) => confirmDelete(
    context,
    'Delete this session?',
    v.plays.isEmpty
        ? 'Its credits and every play logged in them go too.'
        : 'Its venue, credits and timing go; its synced plays stay.');

Future<void> _delete(BuildContext context, Visit v) async {
  final session = context.read<SessionState>();
  await DatabaseProvider.deleteSession(v.session!.id);
  session.changed();
}

/// A session in a rounded tile: venue, when, plays and how they went against
/// usual. Tap for its page; swipe one with a venue to delete it.
class VisitTile extends StatelessWidget {
  const VisitTile(this.visit, {super.key, required this.model});

  final Visit visit;
  final ScoreModel model;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gap = visit.plays.isEmpty ? null : model.summarize(visit.plays).gap;
    final tile = Material(
      color: scheme.surfaceContainerHighest,
      child: ListTile(
        dense: true,
        onTap: () => context.push(_path(visit)),
        title: Text(visit.session?.venue.name ?? 'Where was this?',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontStyle: visit.session == null ? FontStyle.italic : null,
                color: visit.session == null ? scheme.onSurfaceVariant : null)),
        subtitle: Text('${visitSpan(visit.start, visit.end)} · '
            '${visit.plays.isEmpty ? 'no synced plays' : playCount(visit.plays.length)}'),
        trailing: gap == null
            ? null
            : Text(
                '${gap >= 0 ? '+' : '−'}${(gap.abs() / 1000).toStringAsFixed(1)}k',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: gap >= 0
                        ? (isDark
                            ? Colors.green.shade300
                            : Colors.green.shade700)
                        : scheme.error,
                    fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: visit.session == null
            ? tile
            : Dismissible(
                key: ValueKey(visit.key),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) => _confirmDelete(context, visit),
                onDismissed: (_) => _delete(context, visit),
                child: tile,
              ),
      ),
    );
  }
}

/// Every session, newest first.
class SessionsPage extends StatelessWidget {
  const SessionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return HomeSubpage(
      title: 'Sessions',
      body: FutureBuilder<VisitData>(
        future: visitsFor(context),
        builder: (context, snapshot) {
          final data = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final v in data?.visits ?? <Visit>[])
                VisitTile(v, model: data!.model),
            ],
          );
        },
      ),
    );
  }
}

/// One session: how it went, every synced play, and the timing logged in
/// its credits.
class VisitPage extends StatelessWidget {
  const VisitPage({super.key, required this.visitKey});

  final String visitKey;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VisitData>(
      future: visitsFor(context),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final visit = data?.visits.where((v) => v.key == visitKey).firstOrNull;
        if (data == null || visit == null) {
          return HomeSubpage(
            title: 'Session',
            body: data == null
                ? const SizedBox.shrink()
                : const Center(child: Text('This session is gone.')),
          );
        }
        final timing = data.timing[visit.session?.id] ?? [];
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return HomeSubpage(
          title: visit.session?.venue.name ?? 'Session',
          actions: [
            if (visit.session != null)
              IconButton(
                tooltip: 'Delete session',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await _confirmDelete(context, visit) && context.mounted) {
                    await _delete(context, visit);
                    if (context.mounted) context.pop();
                  }
                },
              ),
          ],
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              HomeCard(
                title: 'Summary',
                icon: Icons.insights,
                children: [
                  CardSubtitle(
                      '${visitSpan(visit.start, visit.end)} · ${playCount(visit.plays.length)}'),
                  if (visit.session == null)
                    _WhereButton(visit,
                        onAdded: (s) =>
                            context.replace('/home/sessions/${s.id}')),
                  if (visit.plays.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('No synced plays: sync after your set to '
                          'add them.'),
                    )
                  else
                    SessionSummaryBody(
                      data.model.summarize(visit.plays),
                      plays: visit.plays,
                      timed: visit.session != null,
                      timingMs: _meanTiming(timing),
                    ),
                ],
              ),
              if (visit.plays.isNotEmpty)
                HomeCard(
                  title: 'Plays',
                  icon: Icons.history,
                  children: [
                    PlayGrid(plays: visit.plays, bests: data.model.bests),
                  ],
                ),
              if (timing.isNotEmpty)
                HomeCard(
                  title: 'Timing',
                  icon: Icons.timer_outlined,
                  children: [
                    for (final p in timing)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.song),
                        subtitle: Text(
                            '${kInGameDifficultyNames[p.difficulty] ?? p.difficulty}'
                            ' · ${p.mode.name}'),
                        trailing: Text(
                          '${p.averageMs.abs().toStringAsFixed(1)} '
                          '${p.averageMs < 0 ? 'FAST' : 'SLOW'}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: p.averageMs < 0
                                ? kFastColor(isDark)
                                : kSlowColor(isDark),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
