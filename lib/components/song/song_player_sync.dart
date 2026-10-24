/// Name: SongPlayerSync
/// Parent: SongPage
/// Description: The sync this player should use on the chart, on the running
/// session's cabinet and side, with quick entry of a play's timing average
/// and variation.
library;

import 'package:ddr_md/components/session/session_page.dart';
import 'package:ddr_md/components/song/card_heading.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/components/song/song_difficulty_picker.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class SongPlayerSync extends StatefulWidget {
  const SongPlayerSync({
    super.key,
    required this.songInfo,
    required this.chart,
    required this.mode,
    required this.difficulty,
  });

  final SongInfo songInfo;
  final Chart chart;
  final Modes mode;
  final String difficulty;

  @override
  State<SongPlayerSync> createState() => _SongPlayerSyncState();
}

class _SongPlayerSyncState extends State<SongPlayerSync> {
  final _average = TextEditingController();
  final _variation = TextEditingController();
  bool _fast = true;
  bool _showAllHistory = false;
  // The sync the play was on, in whole ms like the cabinet setting. Follows
  // the computed sync until stepped.
  int? _playedOn;

  List<TimingPlay> _plays = [];
  double? _override;
  // What the plays and override were loaded for; reloaded when any changes.
  Object? _loadedFor;

  @override
  void dispose() {
    _average.dispose();
    _variation.dispose();
    super.dispose();
  }

  void _load(SessionState session) {
    final key = (
      session.cabinet!.id,
      session.side,
      session.revision,
      widget.songInfo.name,
      widget.mode,
      widget.difficulty,
    );
    if (key == _loadedFor) return;
    _loadedFor = key;
    () async {
      final plays = await DatabaseProvider.getTimingPlays(
          session.cabinet!.id, session.side);
      final override = await DatabaseProvider.getSyncOverride(
          session.cabinet!.id,
          session.side,
          widget.songInfo.name,
          widget.mode,
          widget.difficulty);
      if (!mounted || _loadedFor != key) return;
      setState(() {
        _plays = plays;
        _override = override;
      });
    }();
  }

  double? _parse(TextEditingController c) => double.tryParse(c.text.trim());

  PlayerSync _resolve(List<TimingPlay> plays, double songOffset) =>
      resolvePlayerSync(
        songOffset: songOffset,
        plays: plays,
        song: widget.songInfo.name,
        mode: widget.mode,
        difficulty: widget.difficulty,
        overrideMs: _override,
      );

  // The play the fields describe, before it's logged; null until both the
  // average and variation are filled in.
  TimingPlay? _pending(SessionState session, double songOffset, int playedOn) {
    final average = _parse(_average);
    final variation = _parse(_variation);
    if (average == null || variation == null) return null;
    return TimingPlay(
      playedAt: DateTime.now().toIso8601String(),
      creditId: session.credit!.id,
      cabinetId: session.cabinet!.id,
      side: session.side,
      song: widget.songInfo.name,
      mode: widget.mode,
      difficulty: widget.difficulty,
      songOffsetMs: songOffset,
      syncUsedMs: playedOn.toDouble(),
      averageMs: _fast ? -average.abs() : average.abs(),
      variationMs: variation.abs(),
    );
  }

  Future<void> _log(SessionState session, TimingPlay play) async {
    HapticFeedback.selectionClick();
    await DatabaseProvider.saveTimingPlay(play);
    _average.clear();
    _variation.clear();
    _playedOn = null;
    session.changed();
  }

  // Pin the stepper's value as this chart's sync, or unpin.
  Future<void> _togglePin(SessionState session, int playedOn) async {
    HapticFeedback.selectionClick();
    await DatabaseProvider.setSyncOverride(
        session.cabinet!.id,
        session.side,
        widget.songInfo.name,
        widget.mode,
        widget.difficulty,
        _override == null ? playedOn.toDouble() : null);
    _playedOn = null;
    session.changed();
  }

  // This chart's plays on the cab + side, newest first: what was logged, the
  // sync it was played on, and the sync that play alone points to.
  List<Widget> _history(SessionState session, bool isDark) {
    final chartPlays = [
      for (final p in _plays)
        if (p.song == widget.songInfo.name &&
            p.mode == widget.mode &&
            p.difficulty == widget.difficulty)
          p
    ];
    if (chartPlays.isEmpty) return [];
    final shown = _showAllHistory ? chartPlays : chartPlays.take(5);
    String whole(double ms) => '${ms >= 0 ? '+' : ''}${ms.round()}';
    const small = TextStyle(fontSize: 12, color: Colors.grey);
    return [
      const Divider(),
      Row(
        children: [
          Text('History', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          if (chartPlays.length > 5)
            TextButton(
              onPressed: () =>
                  setState(() => _showAllHistory = !_showAllHistory),
              child: Text(_showAllHistory
                  ? 'Show less'
                  : 'Show all ${chartPlays.length}'),
            ),
        ],
      ),
      for (final p in shown)
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
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                    child: Text(formatDate(DateTime.parse(p.playedAt)),
                        style: small)),
                Text(
                  '${p.averageMs.abs().toStringAsFixed(1)} '
                  '${p.averageMs < 0 ? 'FAST' : 'SLOW'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: p.averageMs < 0
                        ? kFastColor(isDark)
                        : kSlowColor(isDark),
                  ),
                ),
                Text(' ± ${p.variationMs.toStringAsFixed(1)}', style: small),
                const SizedBox(width: 12),
                Text(
                  'on ${whole(p.syncUsedMs)} → '
                  '${whole(p.syncUsedMs - p.trueAverageMs)} ms',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final songOffset = songOffsetMs(widget.songInfo, widget.chart);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final outline = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(
          color: FloorPop.of(context).voltText.withValues(alpha: 0.55),
          width: 2),
    );
    if (!session.active) {
      return Card(
        shape: outline,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const CardHeading('Your Sync', icon: Icons.person_pin_circle),
          subtitle: const Text('Start a session to work out your own sync',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          trailing: TextButton(
            onPressed: () => showStartSessionSheet(context),
            // In the card's Volt, not the scheme's primary.
            style: TextButton.styleFrom(
                foregroundColor: FloorPop.of(context).voltText),
            child: const Text('Start'),
          ),
        ),
      );
    }

    _load(session);
    final current = _resolve(_plays, songOffset);
    final playedOn = _playedOn ?? current.ms.round();
    final pending = _pending(session, songOffset, playedOn);
    final shown =
        pending == null ? current : _resolve([pending, ..._plays], songOffset);
    final shownMs = shown.ms.round();

    final from = switch (shown.source) {
      SyncSource.override => 'pinned',
      SyncSource.chart => 'this chart',
      SyncSource.song => 'this song',
      SyncSource.cabinet => 'all songs',
      SyncSource.none => 'song offset, no plays yet',
    };
    final spread = shown.spreadMs == null
        ? ''
        : ' ± ${shown.spreadMs!.toStringAsFixed(1)}, ${shown.plays} '
            '${shown.plays == 1 ? 'play' : 'plays'}';
    final timingColor = _fast ? kFastColor(isDark) : kSlowColor(isDark);
    const dense = InputDecoration(isDense: true, suffixText: 'ms');

    // Outlined in Volt, the colour of the number it carries: the one card
    // that's about you on this cab right now.
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: outline,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const CardHeading('Your Sync', icon: Icons.person_pin_circle),
              const SizedBox(width: 10),
              Text(
                '${shownMs >= 0 ? '+' : ''}$shownMs ms',
                style:
                    FloorPop.readout(20, color: FloorPop.of(context).voltText),
              ),
              if (pending != null && _override == null)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('unsaved',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
            ],
          ),
          // Tapping the credit starts the next one, for a side or cab swap.
          subtitle: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                onTap: () => showNewCreditSheet(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${session.cabinet!.label} ${sideLabel(session.side)}'
                      ' · credit ${session.credit!.number}',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    Icon(Icons.swap_horiz,
                        size: 14, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
              Text(
                ' · $from$spread',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          children: [
            // Timing is kept per chart: pick the one played before logging.
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Text('Logging for',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 8),
                Expanded(
                  child: SongDifficultyPicker(
                      difficulty: widget.mode == Modes.singles
                          ? widget.songInfo.singles
                          : widget.songInfo.doubles),
                ),
              ]),
            ),
            // What the result screen showed.
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _average,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: dense.copyWith(hintText: 'timing avg'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _fast = !_fast),
                  child: Text(_fast ? 'FAST' : 'SLOW',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, color: timingColor)),
                ),
                Expanded(
                  child: TextField(
                    controller: _variation,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration:
                        dense.copyWith(hintText: 'variation', prefixText: '± '),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // The sync it was played on, then pin or log.
            Row(
              children: [
                const Text('played on',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove),
                  onPressed: () => setState(() => _playedOn = playedOn - 1),
                ),
                Text('${playedOn >= 0 ? '+' : ''}$playedOn ms',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => _playedOn = playedOn + 1),
                ),
                const Spacer(),
                IconButton(
                  tooltip: _override == null
                      ? 'Pin this sync for the chart'
                      : 'Unpin, go back to your averages',
                  icon: Icon(_override == null
                      ? Icons.push_pin_outlined
                      : Icons.push_pin),
                  onPressed: () => _togglePin(session, playedOn),
                ),
                FilledButton(
                  onPressed:
                      pending == null ? null : () => _log(session, pending),
                  child: const Text('Log'),
                ),
              ],
            ),
            ..._history(session, isDark),
          ],
        ),
      ),
    );
  }
}
