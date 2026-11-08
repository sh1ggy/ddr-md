/// Name: SessionPage
/// Parent: Layout
/// Description: Home tab: sync e-amusement scores, start a session at a
/// venue, play it credit by credit (cabinet + side), and see the timing logged
/// in each; the gear opens Settings.
library;

import 'dart:async';

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/nav_bar.dart';
import 'package:ddr_md/components/session/count_in.dart';
import 'package:ddr_md/components/session/eamuse_sync_card.dart';
import 'package:ddr_md/components/session/goal_card.dart';
import 'package:ddr_md/components/session/session_wrap.dart';
import 'package:ddr_md/components/session/visits.dart';
import 'package:ddr_md/components/song/song_page.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/session_goal.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  SessionGoal? _goal;
  late bool _broadcast = widget.newSession
      ? Settings.getInt(Settings.circleLiveDefaultKey) == 1
      : CircleState.broadcasting;
  late bool _showLocation = Settings.getInt(widget.newSession
          ? Settings.circleLocationDefaultKey
          : Settings.circleShowLocationKey) ==
      1;

  bool get _startsNow => widget.past == null;

  @override
  void dispose() {
    super.dispose();
  }

  /// Counts in over the whole screen, then starts the session.
  Future<void> _countIn() async {
    if (await showCountIn(context) && mounted) await _go();
  }

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
    final circles = context.read<CircleState>();
    if (widget.newSession) {
      await session.start(_venue!, _cabinet!, _side, goal: _goal);
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
    // Sent in the background, so the credit starts on time.
    if (_startsNow ||
        (widget.editing?.id == session.credit?.id &&
            CircleState.broadcasting)) {
      final credit = session.credit!;
      if (_startsNow && !_broadcast) {
        circles.endBroadcast();
      } else {
        if (widget.newSession) {
          await Settings.setInt(
              Settings.circleShowLocationKey, _showLocation ? 1 : 0);
        }
        circles.broadcast(
            session.session!.venue.name, credit.number, sideLabel(credit.side));
      }
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
    return SingleChildScrollView(
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
          if (widget.newSession)
            ListTile(
              contentPadding: const EdgeInsets.only(top: 8),
              leading: Icon(_goal?.kind.icon ?? Icons.flag_outlined,
                  color: _goal?.kind.color),
              title: Text(_goal?.title ?? 'Set a goal'),
              subtitle: _goal == null
                  ? const Text('What are you here to work on?')
                  : Text(_goal!.target == null
                      ? 'Open-ended'
                      : 'Target: ${_goal!.target}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await showGoalSheet(context, _goal);
                if (picked != null) setState(() => _goal = picked.$1);
              },
            ),
          if (widget.newSession && CircleState.available)
            Column(children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.only(top: 8),
                secondary: const Icon(Icons.podcasts),
                title: const Text('Broadcast to my circle'),
                subtitle: Text(context.watch<CircleState>().id == null
                    ? 'Set up your circle on the Circle tab first'
                    : _broadcast
                        ? 'Friends can see your credits and cheer you on'
                        : 'Just you this time'),
                value: context.watch<CircleState>().id != null && _broadcast,
                onChanged: context.read<CircleState>().id == null
                    ? null
                    : (on) => setState(() => _broadcast = on),
              ),
              if (_broadcast && context.read<CircleState>().id != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(_showLocation
                      ? Icons.location_on_outlined
                      : Icons.location_off_outlined),
                  title: const Text('Show my location'),
                  subtitle: Text(_showLocation
                      ? (_venue?.name ?? 'Your selected venue')
                      : 'Your venue stays private'),
                  value: _showLocation,
                  onChanged: (on) => setState(() => _showLocation = on),
                ),
            ]),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: _cabinet == null
                ? null
                : widget.newSession
                    ? _countIn
                    : _go,
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: const GlassHeader(),
        title: const PageTitle('Home'),
        actions: [
          HeaderButton(
              tooltip: 'Trends',
              icon: const Icon(Icons.insights),
              onPressed: () => context.push('/home/trends')),
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
          : Builder(
              builder: (context) => ListView(
                    padding:
                        clearOfBars(context, const EdgeInsets.only(bottom: 24)),
                    children: const [
                      BeatIn(child: StartSessionCard()),
                      BeatIn(index: 1, child: EamuseSyncCard()),
                      BeatIn(index: 2, child: LastSessionCard()),
                    ],
                  )),
    );
  }
}

class _ActiveSession extends StatefulWidget {
  const _ActiveSession({required this.session, required this.header});

  final SessionState session;
  final List<Widget> header;

  @override
  State<_ActiveSession> createState() => _ActiveSessionState();
}

class _ActiveSessionState extends State<_ActiveSession> {
  late int _revision = widget.session.revision;
  late Future<(List<Credit>, List<TimingPlay>, List<Heard>)> _load = _fetch();

  Future<(List<Credit>, List<TimingPlay>, List<Heard>)> _fetch() {
    final id = widget.session.session!.id;
    return (
      DatabaseProvider.getCredits(id),
      DatabaseProvider.getSessionPlays(id),
      DatabaseProvider.getSessionHeard(id),
    ).wait;
  }

  // Refetched on each revision, so a logged or deleted play shows at once;
  // the list keeps showing the last answer meanwhile rather than blinking.
  @override
  void didUpdateWidget(_ActiveSession old) {
    super.didUpdateWidget(old);
    if (widget.session.revision != _revision) {
      _revision = widget.session.revision;
      _load = _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final header = widget.header;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<(List<Credit>, List<TimingPlay>, List<Heard>)>(
      future: _load,
      builder: (context, snapshot) {
        final (credits, plays, heard) =
            snapshot.data ?? (<Credit>[], <TimingPlay>[], <Heard>[]);
        return ListView(
          padding: clearOfBars(context, const EdgeInsets.only(bottom: 12)),
          children: [
            BeatIn(child: _LiveSessionCard(session: session)),
            const BeatIn(index: 1, child: LiveGoalCard()),
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
                    HeardChips(heard: [
                      for (final h in heard)
                        if (h.creditId == credit.id) h
                    ]),
                    if (!plays.any((p) => p.creditId == credit.id) &&
                        !heard.any((h) => h.creditId == credit.id))
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

/// The running session, first on Home: since when, with its discard and
/// end, then where, and the credit in big type over its cab and side, each
/// changed right there. Scanning and the next credit are on the dock.
class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    final credit = session.credit!;
    Widget action(String tooltip, IconData icon, VoidCallback onPressed) =>
        IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          color: pop.haze,
          iconSize: 20,
          icon: Icon(icon),
          onPressed: onPressed,
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const LivePulse(),
            const SizedBox(width: 6),
            Text('LIVE', style: pop.label.copyWith(color: pop.voltText)),
            const SizedBox(width: 10),
            Icon(Icons.schedule, size: 13, color: pop.haze),
            const SizedBox(width: 3),
            Text(formatTime12(session.session!.startedAt).toUpperCase(),
                style: pop.label.copyWith(color: pop.haze)),
            const Spacer(),
            action('Discard session', Icons.delete_outline, () async {
              if (await confirmDelete(context, 'Discard this session?',
                  'Its credits and every play logged in them go too.')) {
                await session.discard();
              }
            }),
            action('End session', Icons.stop_circle_outlined,
                () => endSession(context)),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.place_outlined,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(session.session!.venue.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FloorPop.display(18, color: scheme.onSurface)
                            .copyWith(fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 12),
                BeatSwap(
                  child: Text('CREDIT ${credit.number}',
                      key: ValueKey(credit.number),
                      style: FloorPop.readout(38, color: scheme.onSurface)),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: _CreditTile(
                      icon: Icons.videogame_asset_outlined,
                      label: 'CAB',
                      onTap: _pickCabinet,
                      child: Row(children: [
                        Expanded(
                          child: Text(
                              credit.cabinet.name.isEmpty
                                  ? 'Main cab'
                                  : credit.cabinet.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        Icon(Icons.unfold_more, size: 18, color: pop.haze),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CreditTile(
                      icon: Icons.person_outline,
                      label: 'SIDE',
                      child: Row(children: [
                        for (final s in PadSide.values)
                          Expanded(
                            child: _SideSegment(
                                side: s, selected: s == credit.side),
                          ),
                      ]),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Puts the running credit on [cabinet] or [side], and tells the circle if
/// it's broadcasting.
Future<void> _changeCredit(BuildContext context,
    {Cabinet? cabinet, PadSide? side}) async {
  final session = context.read<SessionState>();
  final circles = context.read<CircleState>();
  final c = session.credit!;
  HapticFeedback.selectionClick();
  await session.saveCredit(Credit(
    id: c.id,
    sessionId: c.sessionId,
    number: c.number,
    cabinet: cabinet ?? c.cabinet,
    side: side ?? c.side,
    startedAt: c.startedAt,
  ));
  if (CircleState.broadcasting) {
    circles.broadcast(
        session.session!.venue.name, c.number, sideLabel(side ?? c.side));
  }
}

/// The venue's cabs in a menu under the cab pill, and one more.
Future<void> _pickCabinet(BuildContext context) async {
  final session = context.read<SessionState>();
  final venue = session.session!.venue;
  final current = session.credit!.cabinet;
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final at =
      box.localToGlobal(Offset(0, box.size.height + 4), ancestor: overlay);
  final cabinets = await DatabaseProvider.getCabinets(venue.id);
  if (!context.mounted) return;
  // A cab's id, or -1 for another cab.
  final picked = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
    items: [
      for (final c in cabinets)
        CheckedPopupMenuItem(
            value: c.id,
            checked: c.id == current.id,
            child: Text(c.name.isEmpty ? 'Main cab' : c.name)),
      const PopupMenuDivider(),
      const PopupMenuItem(
          value: -1,
          child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add),
              title: Text('Another cab here'))),
    ],
  );
  if (picked == null || picked == current.id || !context.mounted) return;
  final Cabinet cabinet;
  if (picked == -1) {
    final name = await askName(context, 'Another cab here', 'e.g. Cab 2');
    if (name == null || name.isEmpty || !context.mounted) return;
    cabinet = await DatabaseProvider.addCabinet(venue, name);
  } else {
    cabinet = cabinets.firstWhere((c) => c.id == picked);
  }
  if (context.mounted) await _changeCredit(context, cabinet: cabinet);
}

/// Half of the credit's settings row: a small label over its value, the
/// whole tile tappable with [onTap].
class _CreditTile extends StatelessWidget {
  const _CreditTile(
      {required this.icon,
      required this.label,
      required this.child,
      this.onTap});

  final IconData icon;
  final String label;
  final Widget child;
  // Given the tile's own context, for a menu under it.
  final void Function(BuildContext)? onTap;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Material(
      color: pop.riser,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: pop.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 13, color: pop.haze),
                const SizedBox(width: 4),
                Text(label, style: pop.label.copyWith(color: pop.haze)),
              ]),
              const SizedBox(height: 4),
              SizedBox(height: 30, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1P or 2P in the side tile, lit in Volt when it's the credit's.
class _SideSegment extends StatelessWidget {
  const _SideSegment({required this.side, required this.selected});

  final PadSide side;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : () => _changeCredit(context, side: side),
        child: AnimatedContainer(
          duration: FloorPop.sixteenth,
          curve: FloorPop.settle,
          margin: const EdgeInsets.only(right: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? FloorPop.volt : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(sideLabel(side),
              style: FloorPop.readout(15,
                  color: selected ? FloorPop.onVolt : pop.haze)),
        ),
      ),
    );
  }
}

/// Songs Song ID heard in a credit, as jacket chips that open the song.
class HeardChips extends StatelessWidget {
  const HeardChips({super.key, required this.heard});

  final List<Heard> heard;

  @override
  Widget build(BuildContext context) {
    final songs = [
      for (final h in heard)
        if (Songs.list.where((s) => s.name == h.song).firstOrNull
            case final song?)
          song
    ];
    if (songs.isEmpty) return const SizedBox.shrink();
    final pop = FloorPop.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final song in songs)
          Material(
            color: pop.riser,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                context.read<SongState>()
                  ..setSongInfo(song)
                  ..setChosenDifficulty(0);
                Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SongPage()));
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: SizedBox.square(
                        dimension: 34,
                        child: SongArtwork(
                            songName: song.name, title: song.title)),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.hearing, size: 14, color: pop.haze),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
