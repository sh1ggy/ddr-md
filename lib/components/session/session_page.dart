/// Name: SessionPage
/// Parent: Layout
/// Description: Home tab: sync e-amusement scores, start a session at a
/// venue, play it credit by credit (cabinet + side), and see the timing logged
/// in each; the gear opens Settings.
library;

import 'package:ddr_md/components/session/eamuse_sync_card.dart';
import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

String sideLabel(PadSide side) => side == PadSide.p1 ? '1P' : '2P';

String signedMs(double ms) =>
    '${ms >= 0 ? '+' : ''}${ms.toStringAsFixed(1)} ms';

/// Pick a venue and side, then start the session on its first credit.
Future<void> showStartSessionSheet(BuildContext context) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreditSheet(newSession: true),
    );

/// Start the running session's next credit, on the same cabinet and side
/// unless changed.
Future<void> showNewCreditSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreditSheet(newSession: false),
    );

Future<bool> confirmDelete(
        BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ??
    false;

Future<String?> _askName(BuildContext context, String title, String hint) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add')),
      ],
    ),
  );
}

class _CreditSheet extends StatefulWidget {
  const _CreditSheet({required this.newSession});

  final bool newSession;

  @override
  State<_CreditSheet> createState() => _CreditSheetState();
}

class _CreditSheetState extends State<_CreditSheet> {
  List<Venue> _venues = [];
  Venue? _venue;
  List<Cabinet> _cabinets = [];
  Cabinet? _cabinet;
  late PadSide _side = context.read<SessionState>().side;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionState>();
    if (widget.newSession) {
      DatabaseProvider.getVenues().then((v) {
        setState(() => _venues = v);
        if (v.length == 1) _pickVenue(v.first);
      });
    } else {
      _pickVenue(session.session!.venue, keep: session.cabinet);
    }
  }

  Future<void> _pickVenue(Venue venue, {Cabinet? keep}) async {
    final cabinets = await DatabaseProvider.getCabinets(venue.id);
    setState(() {
      _venue = venue;
      _cabinets = cabinets;
      _cabinet = cabinets.where((c) => c.id == keep?.id).firstOrNull ??
          cabinets.firstOrNull;
    });
  }

  Future<void> _addVenue() async {
    final name = await _askName(context, 'New venue', 'e.g. Round1 Ludo');
    if (name == null || name.isEmpty || _venues.any((v) => v.name == name)) {
      return;
    }
    final venue = await DatabaseProvider.addVenue(name);
    setState(() => _venues = [..._venues, venue]);
    await _pickVenue(venue);
  }

  Future<void> _addCabinet() async {
    final name = await _askName(context, 'Another cab here', 'e.g. Cab 2');
    if (name == null || name.isEmpty) return;
    final cabinet = await DatabaseProvider.addCabinet(_venue!, name);
    setState(() {
      _cabinets = [..._cabinets, cabinet];
      _cabinet = cabinet;
    });
  }

  Future<void> _deleteVenue(Venue venue) async {
    if (!await confirmDelete(context, 'Delete ${venue.name}?',
        'Its cabs, sessions and every play logged there go too.')) {
      return;
    }
    await DatabaseProvider.deleteVenue(venue.id);
    setState(() {
      _venues = [..._venues.where((v) => v.id != venue.id)];
      if (_venue?.id == venue.id) {
        _venue = null;
        _cabinets = [];
        _cabinet = null;
      }
    });
  }

  Future<void> _deleteCabinet(Cabinet cabinet) async {
    if (!await confirmDelete(context, 'Delete ${cabinet.label}?',
        'Its credits, pins and every play logged on it go too.')) {
      return;
    }
    await DatabaseProvider.deleteCabinet(cabinet.id);
    setState(() {
      _cabinets = [..._cabinets.where((c) => c.id != cabinet.id)];
      if (_cabinet?.id == cabinet.id) _cabinet = _cabinets.firstOrNull;
    });
  }

  Future<void> _go() async {
    final session = context.read<SessionState>();
    if (widget.newSession) {
      await session.start(_venue!, _cabinet!, _side);
    } else {
      await session.newCredit(_cabinet!, _side);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionState>();
    final title = widget.newSession
        ? 'Start session'
        : 'Credit ${(session.credit?.number ?? 0) + 1}';
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const Text('Long-press a venue or cab to delete it',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          if (widget.newSession)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final v in _venues)
                  GestureDetector(
                    onLongPress: () => _deleteVenue(v),
                    child: ChoiceChip(
                      label: Text(v.name),
                      selected: _venue?.id == v.id,
                      onSelected: (_) => _pickVenue(v),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('New venue'),
                  onPressed: _addVenue,
                ),
              ],
            ),
          // Most venues have one cab, so the picker only shows for two+.
          if (_venue != null)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_cabinets.length > 1)
                  for (final c in _cabinets)
                    GestureDetector(
                      // The running credit's cab stays: the session needs it.
                      onLongPress: c.id == session.cabinet?.id
                          ? null
                          : () => _deleteCabinet(c),
                      child: ChoiceChip(
                        label: Text(c.name.isEmpty ? 'Main cab' : c.name),
                        selected: _cabinet?.id == c.id,
                        onSelected: (_) => setState(() => _cabinet = c),
                      ),
                    ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Another cab here'),
                  onPressed: _addCabinet,
                ),
              ],
            ),
          const SizedBox(height: 8),
          SegmentedButton<PadSide>(
            segments: [
              for (final s in PadSide.values)
                ButtonSegment(value: s, label: Text(sideLabel(s))),
            ],
            selected: {_side},
            onSelectionChanged: (s) => setState(() => _side = s.first),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _cabinet == null ? null : _go,
            child: Text(widget.newSession ? 'Start' : 'Start $title'),
          ),
        ],
      ),
    );
  }
}

final _deleteBackground = Container(
  alignment: Alignment.centerRight,
  padding: const EdgeInsets.only(right: 16),
  color: Colors.red,
  child: const Icon(Icons.delete, color: Colors.white),
);

class SessionPage extends StatelessWidget {
  const SessionPage({super.key});

  static const _header = [EamuseSyncCard(), RecentPlaysCard()];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.black,
        shadowColor: Colors.black,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.blueGrey),
        title: const Text('Home',
            style: TextStyle(
                fontSize: 20,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/home/settings'),
          ),
        ],
      ),
      // The cards scroll with the session below them.
      body: session.active
          ? _ActiveSession(session: session, header: _header)
          : _NoSession(revision: session.revision, header: _header),
    );
  }
}

Future<bool> _confirmSessionDelete(BuildContext context) => confirmDelete(
    context,
    'Delete this session?',
    'Its credits and every play logged in them go too.');

Future<void> _deleteSession(BuildContext context, PlaySession s) async {
  final session = context.read<SessionState>();
  await DatabaseProvider.deleteSession(s.id);
  session.changed();
}

class _NoSession extends StatelessWidget {
  const _NoSession({required this.revision, required this.header});

  final int revision;
  final List<Widget> header;

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlaySession>>(
      key: ValueKey(revision),
      // One more than shown, to know whether there's more to see.
      future: DatabaseProvider.getSessions(limit: _shown + 1),
      builder: (context, snapshot) {
        final past = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ...header,
            HomeCard(
              title: 'Sessions',
              icon: Icons.place_outlined,
              onMore: past.length > _shown
                  ? () => context.push('/home/sessions')
                  : null,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start session'),
                  onPressed: () => showStartSessionSheet(context),
                ),
                if (past.isNotEmpty) const SizedBox(height: 6),
                for (final s in past.take(_shown)) _SessionTile(s),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A past session in a rounded tile; swipe or tap the bin to delete it.
class _SessionTile extends StatelessWidget {
  const _SessionTile(this.session);

  final PlaySession session;

  @override
  Widget build(BuildContext context) {
    final started = session.startedAt.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Dismissible(
          key: ValueKey(session.id),
          direction: DismissDirection.endToStart,
          background: _deleteBackground,
          confirmDismiss: (_) => _confirmSessionDelete(context),
          onDismissed: (_) => _deleteSession(context, session),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              dense: true,
              title: Text(session.venue.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle:
                  Text('${formatPlayDate(started)} · ${formatTime12(started)}'),
              trailing: IconButton(
                tooltip: 'Delete session',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await _confirmSessionDelete(context) && context.mounted) {
                    await _deleteSession(context, session);
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every past session, newest first.
class SessionsPage extends StatelessWidget {
  const SessionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final revision = context.select<SessionState, int>((s) => s.revision);
    return HomeSubpage(
      title: 'Sessions',
      body: FutureBuilder<List<PlaySession>>(
        key: ValueKey(revision),
        future: DatabaseProvider.getSessions(),
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.all(12),
          children: [for (final s in snapshot.data ?? []) _SessionTile(s)],
        ),
      ),
    );
  }
}

class _ActiveSession extends StatelessWidget {
  const _ActiveSession({required this.session, required this.header});

  final SessionState session;
  final List<Widget> header;

  @override
  Widget build(BuildContext context) {
    final id = session.session!.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<(List<Credit>, List<TimingPlay>)>(
      // Keyed on the revision so a logged or deleted play shows at once.
      key: ValueKey(session.revision),
      future: (
        DatabaseProvider.getCredits(id),
        DatabaseProvider.getSessionPlays(id),
      ).wait,
      builder: (context, snapshot) {
        final (credits, plays) = snapshot.data ?? (<Credit>[], <TimingPlay>[]);
        return ListView(
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            ...header,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      title: Text(session.session!.venue.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          'since ${formatDate(session.session!.startedAt)}'
                          ' · ${plays.length} ${plays.length == 1 ? 'play' : 'plays'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Discard session',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (await confirmDelete(
                                  context,
                                  'Discard this session?',
                                  'Its credits and every play logged in them go '
                                      'too.')) {
                                await session.discard();
                              }
                            },
                          ),
                          TextButton(
                            onPressed: session.end,
                            child: const Text('End'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.add),
                      label: Text('Credit ${session.credit!.number + 1}'),
                      onPressed: () => showNewCreditSheet(context),
                    ),
                  ),
                  for (final credit in credits) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 0, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Credit ${credit.number} · ${sideLabel(credit.side)}'
                              '${credit.cabinet.name.isEmpty ? '' : ' · ${credit.cabinet.name}'}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete credit',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              if (await confirmDelete(
                                  context,
                                  'Delete credit ${credit.number}?',
                                  'Every play logged in it goes too.')) {
                                await session.deleteCredit(credit);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    if (!plays.any((p) => p.creditId == credit.id))
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Nothing logged yet.',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    for (final p in plays.where((p) => p.creditId == credit.id))
                      Dismissible(
                        key: ValueKey(p.id),
                        direction: DismissDirection.endToStart,
                        background: _deleteBackground,
                        onDismissed: (_) async {
                          await DatabaseProvider.deleteTimingPlay(p.id);
                          session.changed();
                        },
                        child: ListTile(
                          dense: true,
                          title: Text(p.song),
                          subtitle: Text(
                              '${kInGameDifficultyNames[p.difficulty] ?? p.difficulty}'
                              ' · ${p.mode.name} · played on '
                              '${p.syncUsedMs >= 0 ? '+' : ''}${p.syncUsedMs.round()} ms'),
                          trailing: Text(
                            '${p.averageMs.abs().toStringAsFixed(1)} '
                            '${p.averageMs < 0 ? 'FAST' : 'SLOW'}\n'
                            '± ${p.variationMs.toStringAsFixed(1)}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: p.averageMs < 0
                                  ? kFastColor(isDark)
                                  : kSlowColor(isDark),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
