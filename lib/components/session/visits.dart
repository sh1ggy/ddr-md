/// Name: Visits
/// Parent: SessionPage
/// Description: Sessions on Home, each a visit put together by
/// [buildVisits]: the last one as a card (summary, plays, timing), the rest
/// as rows, and a page per session with everything in it. A set no session
/// covers asks "Where was this?", and picking a venue records a session over
/// it.
library;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/session/session_page.dart';
import 'package:ddr_md/components/session/session_summary.dart';
import 'package:ddr_md/components/song/card_heading.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/visit_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

typedef VisitData = ({
  List<Visit> visits,
  ScoreModel model,
  // Each session's logged timing plays, by session id.
  Map<String, List<TimingPlay>> timing,
  // Each session's credits, newest first, by session id.
  Map<String, List<Credit>> credits,
  // The last credit played, which the next session starts like.
  Credit? lastCredit,
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
    timing: await _timingFixed(visits, sessions),
    credits: {
      for (final s in sessions) s.id: await DatabaseProvider.getCredits(s.id),
    },
    lastCredit: await DatabaseProvider.getLatestCredit(),
  );
}

/// Each session's timing plays, after storing the chart they were really
/// played on for those whose synced play was on another.
Future<Map<String, List<TimingPlay>>> _timingFixed(
    List<Visit> visits, List<PlaySession> sessions) async {
  Future<Map<String, List<TimingPlay>>> load() async => {
        for (final s in sessions)
          s.id: await DatabaseProvider.getSessionPlays(s.id),
      };
  final timing = await load();
  final fixes = [
    for (final v in visits)
      if (v.session case final s?)
        ...timingFixes(reconcileTiming(v.plays, timing[s.id] ?? []).$2),
  ];
  for (final (t, difficulty) in fixes) {
    await DatabaseProvider.setTimingDifficulty(t.id, difficulty);
  }
  return fixes.isEmpty ? timing : await load();
}

String _path(Visit v) => '/home/sessions/${v.key}';

/// Home's latest session with plays (or the latest at all before any sync):
/// its summary and first plays, then the sessions before it.
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
        final others = [
          for (final v in data.visits)
            if (v != visit) v
        ];
        if (visit == null && sync.charts == 0) {
          return others.isEmpty
              ? const SizedBox.shrink()
              : HomeCard(
                  title: 'Past sessions',
                  icon: Icons.place_outlined,
                  onMore: others.length > _SessionsSection.shown
                      ? () => context.push('/home/sessions')
                      : null,
                  children: [
                    _SessionsSection(others, model: data.model, header: false)
                  ],
                );
        }
        if (visit == null) {
          // Synced before plays were kept: one more sync fills the history.
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
              _SessionsSection(others, model: data.model),
            ],
          );
        }
        return HomeCard(
          title: visit.session?.venue.name ?? 'Last session',
          icon: Icons.place,
          heading: visit.session == null ? _WhereHeading(visit) : null,
          onMore: () => context.push(_path(visit)),
          children: [
            CardSubtitle(
                '${visitSpan(visit.start, visit.end)} · ${playCount(visit.plays.length)}'),
            SessionSummaryBody(
              data.model.summarize(visit.plays),
              plays: visit.plays,
              timed: visit.session != null,
              timing: data.timing[visit.session?.id],
              credits: data.credits[visit.session?.id] ?? [],
              onPlay: (p) => context.push(
                  '${_path(visit)}?play=${p.playedAt.millisecondsSinceEpoch}'),
            ),
            const SizedBox(height: 8),
            TopPlays(plays: visit.plays, bests: data.model.bests),
            _SessionsSection(others, model: data.model),
          ],
        );
      },
    );
  }
}

/// The latest few of [visits] as tiles, under a divider and the Past
/// sessions heading unless [header] is off (the card then carries both).
class _SessionsSection extends StatelessWidget {
  const _SessionsSection(this.visits,
      {required this.model, this.header = true});

  final List<Visit> visits;
  final ScoreModel model;
  final bool header;

  static const shown = 3;

  @override
  Widget build(BuildContext context) {
    if (visits.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header) ...[
          // Spaced like the card's own edges: its bottom padding above the
          // line, its top padding over the heading below.
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Divider(height: 1),
          ),
          SizedBox(
            height: 44,
            child: Row(children: [
              const Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child:
                      CardHeading('Past sessions', icon: Icons.place_outlined),
                ),
              ),
              if (visits.length > shown)
                TextButton(
                    onPressed: () => context.push('/home/sessions'),
                    child: const Text('See more')),
            ]),
          ),
        ],
        for (final v in visits.take(shown)) VisitTile(v, model: model),
      ],
    );
  }
}

/// The heading of a set no session covers: tap to pick the venue it was
/// played at, which records a session over it.
class _WhereHeading extends StatelessWidget {
  const _WhereHeading(this.visit, {this.onAdded});

  final Visit visit;
  final void Function(PlaySession)? onAdded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        textStyle: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      icon: Icon(Icons.add_location_alt_outlined, color: scheme.primary),
      label: const Text('Where was this?'),
      onPressed: () async {
        final session = await showModalBottomSheet<PlaySession>(
          context: context,
          useRootNavigator: true,
          builder: (_) => _VenueSheet(visit),
        );
        if (session != null && context.mounted) {
          context.read<SessionState>().changed();
          onAdded?.call(session);
        }
      },
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

/// Home's way into a session: one tap starts on the cab and side last
/// played; "Somewhere else" opens the full start sheet.
class StartSessionCard extends StatelessWidget {
  const StartSessionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<VisitData>(
      future: visitsFor(context),
      builder: (context, snapshot) {
        final last = snapshot.data?.lastCredit;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          decoration:
              pop.stripes(color: pop.stage, radius: BorderRadius.circular(26)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Transform.rotate(
                    angle: -0.07, child: const PadGlyph(size: 46, lit: true)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AT THE ARCADE?', style: pop.label),
                      const SizedBox(height: 2),
                      Text('Start a session',
                          style: FloorPop.display(21, color: scheme.onSurface)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              VoltButton(
                height: 62,
                radius: 20,
                tooltip: last == null ? 'Start session' : null,
                onPressed: () async {
                  if (last == null) {
                    await showStartSessionSheet(context);
                    return;
                  }
                  await context.read<SessionState>().start(
                      Venue(last.cabinet.venueId, last.cabinet.venueName),
                      last.cabinet,
                      last.side);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(children: [
                    const Icon(Icons.play_arrow_rounded, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(last == null ? 'Start' : 'Start here'),
                          if (last != null)
                            Text(
                              '${last.cabinet.label} · ${sideLabel(last.side)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: kTextFont,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
              if (last != null)
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      minimumSize: const Size(44, 44)),
                  onPressed: () => showStartSessionSheet(context, last: last),
                  child: const Text('Somewhere else'),
                ),
              if (last == null) const SizedBox(height: 10),
            ],
          ),
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
class VisitTile extends StatefulWidget {
  const VisitTile(this.visit, {super.key, required this.model});

  final Visit visit;
  final ScoreModel model;

  @override
  State<VisitTile> createState() => _VisitTileState();
}

class _VisitTileState extends State<VisitTile> {
  // Swiped away: gone at once, since the list only drops it once the
  // sessions reload, and a dismissed Dismissible can't stay in the tree.
  bool _dismissed = false;

  @override
  void didUpdateWidget(VisitTile old) {
    super.didUpdateWidget(old);
    // The list's tiles aren't keyed, so this state can be handed another
    // session once the deleted one is gone.
    if (old.visit.key != widget.visit.key) _dismissed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final visit = widget.visit;
    final model = widget.model;
    final scheme = Theme.of(context).colorScheme;
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
                        ? FloorPop.of(context).up
                        : FloorPop.of(context).down,
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
                onDismissed: (_) {
                  setState(() => _dismissed = true);
                  _delete(context, visit);
                },
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
            padding: clearOfBars(context, const EdgeInsets.all(12)),
            children: [
              ListTile(
                  leading: const Icon(Icons.insights),
                  title: const Text('Trends'),
                  subtitle: const Text('Your progress over weeks'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/home/trends')),
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
/// its credits. Opens scrolled to the credit of [play] when given.
class VisitPage extends StatefulWidget {
  const VisitPage({super.key, required this.visitKey, this.play});

  final String visitKey;
  // When the play to show was played, in ms since the epoch.
  final int? play;

  @override
  State<VisitPage> createState() => _VisitPageState();
}

class _VisitPageState extends State<VisitPage> {
  final _creditKeys = <int, GlobalKey>{};
  late int? _pending = widget.play;
  // The credit just jumped to, lit for a moment.
  int? _lit;

  /// Scrolls to the credit in [groups] holding the play from [at] and
  /// lights it.
  void _jump(List<(Credit?, List<RecentPlay>)> groups, int at) {
    final i = groups.indexWhere(
        (g) => g.$2.any((p) => p.playedAt.millisecondsSinceEpoch == at));
    if (i < 0) return;
    setState(() => _lit = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_creditKeys[i]?.currentContext case final c?) {
        Scrollable.ensureVisible(c,
            alignment: 0.1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _lit == i) setState(() => _lit = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visitKey = widget.visitKey;
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
        final credits = data.credits[visit.session?.id] ?? [];
        final (played, matched) = reconcileTiming(visit.plays, timing);
        final groups = groupByCredit(played, credits, matched);
        if (_pending case final at?) {
          _pending = null;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _jump(groups, at));
        }
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
          body: Builder(
              builder: (context) => ListView(
                    padding:
                        clearOfBars(context, const EdgeInsets.only(bottom: 24)),
                    children: [
                      HomeCard(
                        title: 'Summary',
                        icon: Icons.insights,
                        heading: visit.session == null
                            ? _WhereHeading(visit,
                                onAdded: (s) =>
                                    context.replace('/home/sessions/${s.id}'))
                            : null,
                        children: [
                          CardSubtitle(
                              '${visitSpan(visit.start, visit.end)} · ${playCount(visit.plays.length)}'),
                          if (visit.plays.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                  'No synced plays: sync after your set to '
                                  'add them.'),
                            )
                          else
                            SessionSummaryBody(
                              data.model.summarize(visit.plays),
                              plays: visit.plays,
                              timed: visit.session != null,
                              timing: timing,
                              detailed: true,
                              credits: credits,
                              onPlay: (p) => _jump(
                                  groups, p.playedAt.millisecondsSinceEpoch),
                            ),
                        ],
                      ),
                      if (visit.plays.isNotEmpty || timing.isNotEmpty)
                        HomeCard(
                          title: 'Plays',
                          icon: Icons.history,
                          children: [
                            for (final (i, (credit, plays)) in groups.indexed)
                              _CreditGroup(
                                  key:
                                      _creditKeys.putIfAbsent(i, GlobalKey.new),
                                  lit: _lit == i,
                                  credit: credit,
                                  plays: plays,
                                  bests: data.model.bests,
                                  timing: matched,
                                  onEdit: switch (visit.session) {
                                    final session? => () => showEditCreditSheet(
                                        context,
                                        session: session,
                                        credit: credit,
                                        last: credits.firstOrNull,
                                        startedAt: plays.lastOrNull?.playedAt ??
                                            credit!.startedAt),
                                    null => null,
                                  }),
                          ],
                        ),
                    ],
                  )),
        );
      },
    );
  }
}

/// One credit's plays beside a narrow rail: its number, side and songs
/// played, on a bar in the primary colour (outlined and numbered "?" for a
/// credit that wasn't logged). The cabinet, when the venue has more than
/// one, is the number's tooltip. Tapping the rail runs [onEdit], to log the
/// credit or fix its cabinet and side.
class _CreditGroup extends StatelessWidget {
  const _CreditGroup(
      {super.key,
      this.lit = false,
      required this.credit,
      required this.plays,
      required this.bests,
      required this.timing,
      this.onEdit});

  final Credit? credit;
  final List<RecentPlay> plays;
  final Map<String, int?> bests;
  final Map<RecentPlay, TimingPlay> timing;
  final VoidCallback? onEdit;
  // Just jumped to from the strip.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final c = credit;
    final bar = c == null ? scheme.outlineVariant : scheme.primary;
    final small = text.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: lit ? scheme.primary.withValues(alpha: 0.15) : null,
        border: Border(left: BorderSide(color: bar, width: 3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: onEdit,
          child: SizedBox(
            width: 25,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(children: [
                Tooltip(
                  message:
                      c == null || c.cabinet.name.isEmpty ? '' : c.cabinet.name,
                  child: Text(c == null ? '?' : '${c.number}',
                      style: text.titleSmall?.copyWith(
                          color: c == null ? scheme.onSurfaceVariant : bar,
                          fontWeight: FontWeight.w800)),
                ),
                if (c != null)
                  Text(c.side == PadSide.p1 ? 'P1' : 'P2', style: small),
                Text('${plays.length}/$kSongsPerCredit', style: small),
              ]),
            ),
          ),
        ),
        Expanded(
          child: plays.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('No synced plays', style: small))
              : PlayGrid(plays: plays, bests: bests, timing: timing),
        ),
      ]),
    );
  }
}
