/// Name: TimingEditSheet
/// Parent: SongPlayerSync, PlayGrid, SessionSummaryBody
/// Description: Fixes a logged play's timing after the fact: its average,
/// FAST or SLOW, variation and the sync it was played on, or deletes it.
library;

import 'package:ddr_md/constants.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Opens the sheet on [play]; saving or deleting reloads everything that
/// shows timing.
Future<void> showTimingEditSheet(BuildContext context, TimingPlay play) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Over the tab bar, not under it.
      useRootNavigator: true,
      showDragHandle: true,
      builder: (_) => _TimingEditSheet(play, context.read<SessionState>()),
    );

class _TimingEditSheet extends StatefulWidget {
  const _TimingEditSheet(this.play, this.session);

  final TimingPlay play;
  final SessionState session;

  @override
  State<_TimingEditSheet> createState() => _TimingEditSheetState();
}

class _TimingEditSheetState extends State<_TimingEditSheet> {
  late final _average = TextEditingController(
      text: widget.play.averageMs.abs().toStringAsFixed(1));
  late final _variation =
      TextEditingController(text: widget.play.variationMs.toStringAsFixed(1));
  late bool _fast = widget.play.averageMs < 0;
  late int _playedOn = widget.play.syncUsedMs.round();

  @override
  void dispose() {
    _average.dispose();
    _variation.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) => double.tryParse(c.text.trim());

  Future<void> _save() async {
    final p = widget.play;
    final average = _parse(_average)!, variation = _parse(_variation)!;
    HapticFeedback.selectionClick();
    await DatabaseProvider.saveTimingPlay(TimingPlay(
      id: p.id,
      playedAt: p.playedAt,
      creditId: p.creditId,
      cabinetId: p.cabinetId,
      side: p.side,
      song: p.song,
      mode: p.mode,
      difficulty: p.difficulty,
      songOffsetMs: p.songOffsetMs,
      syncUsedMs: _playedOn.toDouble(),
      averageMs: _fast ? -average.abs() : average.abs(),
      variationMs: variation.abs(),
    ));
    widget.session.changed();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await DatabaseProvider.deleteTimingPlay(widget.play.id);
    widget.session.changed();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const dense = InputDecoration(isDense: true, suffixText: 'ms');
    final valid = _parse(_average) != null && _parse(_variation) != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit timing', style: Theme.of(context).textTheme.titleMedium),
          Text(widget.play.song,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _average,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: dense.copyWith(labelText: 'timing avg'),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _fast = !_fast),
              child: Text(_fast ? 'FAST' : 'SLOW',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _fast ? kFastColor(isDark) : kSlowColor(isDark))),
            ),
            Expanded(
              child: TextField(
                controller: _variation,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration:
                    dense.copyWith(labelText: 'variation', prefixText: '± '),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('played on',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove),
              onPressed: () => setState(() => _playedOn--),
            ),
            Text('${_playedOn >= 0 ? '+' : ''}$_playedOn ms',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add),
              onPressed: () => setState(() => _playedOn++),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
            const Spacer(),
            FilledButton(
                onPressed: valid ? _save : null, child: const Text('Save')),
          ]),
        ],
      ),
    );
  }
}
