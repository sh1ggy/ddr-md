/// Name: SessionPage
/// Parent: Layout
/// Description: Home tab: start a session on a named cabinet and pad side,
/// and see the timing logged in it.
library;

import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

String sideLabel(PadSide side) => side == PadSide.p1 ? '1P' : '2P';

String signedMs(double ms) =>
    '${ms >= 0 ? '+' : ''}${ms.toStringAsFixed(1)} ms';

/// Pick a cabinet (or name a new one) and a side, then start the session.
Future<void> showStartSessionSheet(BuildContext context) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _StartSessionSheet(),
    );

class _StartSessionSheet extends StatefulWidget {
  const _StartSessionSheet();

  @override
  State<_StartSessionSheet> createState() => _StartSessionSheetState();
}

class _StartSessionSheetState extends State<_StartSessionSheet> {
  List<Cabinet> _cabinets = [];
  Cabinet? _cabinet;
  late PadSide _side = context.read<SessionState>().side;

  @override
  void initState() {
    super.initState();
    DatabaseProvider.getCabinets().then((c) => setState(() {
          _cabinets = c;
          _cabinet = c.length == 1 ? c.first : null;
        }));
  }

  Future<void> _addCabinet() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New cabinet'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Round1 Ludo #1'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add')),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || _cabinets.any((c) => c.name == trimmed)) return;
    final cabinet = await DatabaseProvider.addCabinet(trimmed);
    setState(() {
      _cabinets = [..._cabinets, cabinet];
      _cabinet = cabinet;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Start session', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in _cabinets)
                ChoiceChip(
                  label: Text(c.name),
                  selected: _cabinet?.id == c.id,
                  onSelected: (_) => setState(() => _cabinet = c),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('New cabinet'),
                onPressed: _addCabinet,
              ),
            ],
          ),
          const SizedBox(height: 12),
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
            onPressed: _cabinet == null
                ? null
                : () {
                    context.read<SessionState>().start(_cabinet!, _side);
                    Navigator.pop(context);
                  },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

class SessionPage extends StatelessWidget {
  const SessionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: session.active
          ? _ActiveSession(session: session)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Start a session on the cabinet and side you\'re playing, '
                      'then log each play\'s timing average and variation from '
                      'its song page.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start session'),
                      onPressed: () => showStartSessionSheet(context),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ActiveSession extends StatelessWidget {
  const _ActiveSession({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final cabinet = session.cabinet!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<List<TimingPlay>>(
      // Keyed on the revision so a logged or deleted play shows at once.
      key: ValueKey(session.revision),
      future: DatabaseProvider.getTimingPlays(cabinet.id, session.side),
      builder: (context, snapshot) {
        final plays = snapshot.data ?? [];
        final started = session.startedAt;
        final thisSession = [
          for (final p in plays)
            if (started == null ||
                !DateTime.parse(p.playedAt).isBefore(started))
              p
        ];
        final correction = plays.isEmpty ? null : weightedPersonal(plays);
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ListTile(
                title: Text('${cabinet.name} · ${sideLabel(session.side)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text([
                  if (started != null) 'since ${formatDate(started)}',
                  correction == null
                      ? 'no plays on this cab yet'
                      : 'your correction ${signedMs(correction.$1)} '
                          '± ${correction.$2.toStringAsFixed(1)} '
                          '(${plays.length} plays)',
                ].join('\n')),
                trailing: TextButton(
                  onPressed: session.end,
                  child: const Text('End'),
                ),
              ),
            ),
            if (thisSession.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Nothing logged this session yet. Open a song and fill in '
                  'Your Sync after a play.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            for (final p in thisSession)
              Dismissible(
                key: ValueKey(p.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) async {
                  await DatabaseProvider.deleteTimingPlay(p.id);
                  session.changed();
                },
                child: ListTile(
                  title: Text(p.song),
                  subtitle: Text(
                      '${kInGameDifficultyNames[p.difficulty] ?? p.difficulty}'
                      ' · ${p.mode.name} · played on ${p.syncUsedMs >= 0 ? '+' : ''}${p.syncUsedMs.round()} ms'),
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
        );
      },
    );
  }
}
