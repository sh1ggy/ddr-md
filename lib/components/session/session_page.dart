/// Name: SessionPage
/// Parent: Layout
/// Description: Home tab: sync e-amusement scores, start a session at a
/// venue, play it credit by credit (cabinet + side), and see the timing logged
/// in each; the gear opens Settings.
library;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/nav_bar.dart';
import 'package:ddr_md/components/session/eamuse_sync_card.dart';
import 'package:ddr_md/components/session/visits.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

String sideLabel(PadSide side) => side == PadSide.p1 ? '1P' : '2P';

String signedMs(double ms) =>
    '${ms >= 0 ? '+' : ''}${ms.toStringAsFixed(1)} ms';

/// Pick a venue and side, then start the session on its first credit.
/// [last] preselects the cab and side it was played on.
Future<void> showStartSessionSheet(BuildContext context, {Credit? last}) =>
    showModalBottomSheet(
      context: context,
      // Over the floating tab bar, wherever it's opened from.
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _CreditSheet(newSession: true, last: last),
    );

/// Start the running session's next credit, on the same cabinet and side
/// unless changed.
Future<void> showNewCreditSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      // Over the floating tab bar, wherever it's opened from.
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => const _CreditSheet(newSession: false),
    );

/// Log a credit of a past [session] after the fact, or fix [credit]'s
/// cabinet and side. A new one starts at [startedAt], and takes the cab and
/// side of [last] to begin with.
Future<void> showEditCreditSheet(BuildContext context,
        {required PlaySession session,
        Credit? credit,
        Credit? last,
        required DateTime startedAt}) =>
    showModalBottomSheet(
      context: context,
      // Over the floating tab bar, wherever it's opened from.
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _CreditSheet(
          newSession: false,
          past: session,
          editing: credit,
          last: credit ?? last,
          startedAt: startedAt),
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

Future<String?> askName(BuildContext context, String title, String hint) {
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
  const _CreditSheet(
      {required this.newSession,
      this.last,
      this.past,
      this.editing,
      this.startedAt});

  final bool newSession;
  final Credit? last;
  // A session's credit logged or fixed after the fact, not a new one now.
  final PlaySession? past;
  final Credit? editing;
  final DateTime? startedAt;

  @override
  State<_CreditSheet> createState() => _CreditSheetState();
}

class _CreditSheetState extends State<_CreditSheet> {
  List<Venue> _venues = [];
  Venue? _venue;
  List<Cabinet> _cabinets = [];
  Cabinet? _cabinet;
  late PadSide _side = widget.last?.side ?? context.read<SessionState>().side;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionState>();
    if (widget.newSession) {
      DatabaseProvider.getVenues().then((v) {
        setState(() => _venues = v);
        final cabinet = widget.last?.cabinet;
        final last = v.where((v) => v.id == cabinet?.venueId).firstOrNull;
        if (last != null) {
          _pickVenue(last, keep: cabinet);
        } else if (v.length == 1) {
          _pickVenue(v.first);
        }
      });
    } else if (widget.past case final past?) {
      _pickVenue(past.venue, keep: widget.last?.cabinet);
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
    final name = await askName(context, 'New venue', 'e.g. Round1 Ludo');
    if (name == null || name.isEmpty || _venues.any((v) => v.name == name)) {
      return;
    }
    final venue = await DatabaseProvider.addVenue(name);
    setState(() => _venues = [..._venues, venue]);
    await _pickVenue(venue);
  }

  Future<void> _addCabinet() async {
    final name = await askName(context, 'Another cab here', 'e.g. Cab 2');
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
    } else if (widget.past case final past?) {
      final e = widget.editing;
      await session.saveCredit(Credit(
        id: e?.id,
        sessionId: past.id,
        number: e?.number ?? 0,
        cabinet: _cabinet!,
        side: _side,
        startedAt: e?.startedAt ?? widget.startedAt!,
      ));
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
        : widget.past != null
            ? widget.editing == null
                ? 'Log credit'
                : 'Credit ${widget.editing!.number}'
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
            child: Text(widget.newSession
                ? 'Start'
                : widget.past != null
                    ? widget.editing == null
                        ? 'Log credit'
                        : 'Save'
                    : 'Start $title'),
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

  static const _header = [EamuseSyncCard(), LastSessionCard()];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return Scaffold(
      appBar: AppBar(
        title: const PageTitle('Home'),
        actions: [
          HeaderButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/home/settings'),
          ),
        ],
      ),
      // The cards scroll with the session below them.
      body: session.active
          ? _ActiveSession(session: session, header: _header)
          : ListView(
              padding:
                  clearOfTabBar(context, const EdgeInsets.only(bottom: 24)),
              children: const [
                BeatIn(child: EamuseSyncCard()),
                BeatIn(index: 1, child: StartSessionCard()),
                BeatIn(index: 2, child: LastSessionCard()),
              ],
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
          padding: clearOfTabBar(context, const EdgeInsets.only(bottom: 12)),
          children: [
            BeatIn(
                child: _LiveSessionCard(session: session, plays: plays.length)),
            ...header,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
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

/// The running session, first on Home: where and since when, the credit in
/// big type with its cab and side (tap to swap), and the next credit.
class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard({required this.session, required this.plays});

  final SessionState session;
  final int plays;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    final credit = session.credit!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(18),
      decoration: pop
          .stripes(color: pop.stage, radius: BorderRadius.circular(26))
          .copyWith(
        border:
            Border.all(color: FloorPop.volt.withValues(alpha: 0.55), width: 2),
        boxShadow: [
          BoxShadow(
              color: FloorPop.volt.withValues(alpha: 0.12), blurRadius: 26)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const LivePulse(),
                    const SizedBox(width: 6),
                    Text(
                        'LIVE · SINCE ${formatTime12(session.session!.startedAt).toUpperCase()}',
                        style: pop.label.copyWith(color: pop.voltText)),
                  ]),
                  const SizedBox(height: 4),
                  Text(session.session!.venue.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FloorPop.display(18, color: scheme.onSurface)
                          .copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Discard session',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDelete(context, 'Discard this session?',
                    'Its credits and every play logged in them go too.')) {
                  await session.discard();
                }
              },
            ),
            OutlinedButton(onPressed: session.end, child: const Text('End')),
          ]),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BeatSwap(
                    child: Text('CREDIT ${credit.number}',
                        key: ValueKey(credit.number),
                        style: FloorPop.readout(38, color: scheme.onSurface)),
                  ),
                  const SizedBox(height: 6),
                  // Tapping the credit starts the next one, for a side or cab
                  // swap.
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => showNewCreditSheet(context),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _CreditPill(credit.cabinet.name.isEmpty
                            ? 'Main cab'
                            : credit.cabinet.name),
                        _CreditPill(sideLabel(credit.side)),
                        _CreditPill(plays == 1 ? '1 play' : '$plays plays'),
                        Icon(Icons.swap_horiz, size: 18, color: pop.haze),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 112,
              child: VoltButton(
                height: 72,
                radius: 20,
                onPressed: () => showNewCreditSheet(context),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add, size: 26),
                  Text('Credit ${credit.number + 1}',
                      style: const TextStyle(
                          fontFamily: kTextFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// One fact about the running credit as a small pill.
class _CreditPill extends StatelessWidget {
  const _CreditPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: FloorPop.of(context).riser,
            borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );
}
