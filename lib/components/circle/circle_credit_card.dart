/// Name: CircleCreditCard
/// Parent: CirclePersonPage
/// Description: A shared credit: its songs with jacket, difficulty, score,
/// new bests and fails, the cheers on it as notes, and, for someone
/// else's, the Cheer button that opens the cheer sheet. Also a session
/// that's over, compact: its tally, its best songs and every cheer on it,
/// cheered as one through its last credit.
library;

import 'package:ddr_md/components/circle/cheer_sheet.dart';
import 'package:ddr_md/components/circle/cheer_stamp.dart';
import 'package:ddr_md/components/circle/circle_page.dart' show CircleBubble;
import 'package:ddr_md/components/session/recent_plays.dart' show chartOf;
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CircleCreditCard extends StatelessWidget {
  const CircleCreditCard(this.credit, {super.key});
  final CircleCredit credit;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: pop.stage,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pop.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('CREDIT ${credit.credit}',
              style: FloorPop.readout(18, color: scheme.onSurface)),
          const Spacer(),
          Text(ago(credit.at), style: TextStyle(color: pop.haze, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        for (final p in credit.plays) _PlayRow(p),
        if (credit.cheers.isNotEmpty) ...[
          const SizedBox(height: 10),
          _CheerNotes(credit.cheers, credit),
        ],
        if (credit.by != null && credit.mine == null) ...[
          const SizedBox(height: 12),
          _CheerButton(credit),
        ],
      ]),
    );
  }

  static String ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

/// Someone's finished session in brief. [credits] are its own, newest
/// first; a cheer lands on the newest, which the wrap counts like any other.
class CircleSessionCard extends StatelessWidget {
  const CircleSessionCard(this.credits, {super.key, this.header = false});
  final List<CircleCredit> credits;

  /// Leads with who played it, for the Circle tab.
  final bool header;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    final last = credits.first;
    final plays = [for (final c in credits) ...c.plays];
    final bests = plays.where((p) => p.best && !p.failed).length;
    // New bests first, then the highest scores.
    final top = [...plays.where((p) => !p.failed)]..sort((a, b) =>
        a.best != b.best ? (a.best ? -1 : 1) : (b.score ?? 0) - (a.score ?? 0));
    // Each cheerer once, their latest cheer.
    final cheers = <String, ({String? id, String name, Cheer cheer})>{};
    for (final c in credits.reversed) {
      for (final x in c.cheers) {
        cheers[x.id ?? x.name] = x;
      }
    }
    final tally = [
      '${credits.length} credit${credits.length == 1 ? '' : 's'}',
      '${plays.length} song${plays.length == 1 ? '' : 's'}',
      if (bests > 0) '$bests new best${bests == 1 ? '' : 's'}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: pop.stage,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pop.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (header && last.by != null) ...[
            CircleBubble(last.by!, size: 36),
            const SizedBox(width: 10),
          ],
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  header && last.by != null
                      ? '${last.by!.name} wrapped a session'
                      : 'LAST SESSION',
                  style: header
                      ? const TextStyle(fontWeight: FontWeight.w700)
                      : FloorPop.readout(18, color: scheme.onSurface)),
              Text('${CircleCreditCard.ago(last.at)} · $tally',
                  style: TextStyle(color: pop.haze, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        for (final p in top.take(2)) _PlayRow(p),
        if (cheers.isNotEmpty) ...[
          const SizedBox(height: 10),
          _CheerNotes(cheers.values.toList(), last),
        ],
        if (last.by != null && last.mine == null) ...[
          const SizedBox(height: 12),
          _CheerButton(last, summary: 'Their session · $tally'),
        ],
      ]),
    );
  }
}

/// The cheers on a credit as notes; yours opens the sheet to change it.
class _CheerNotes extends StatelessWidget {
  const _CheerNotes(this.cheers, this.credit);
  final List<({String? id, String name, Cheer cheer})> cheers;
  final CircleCredit credit;

  @override
  Widget build(BuildContext context) {
    final circle = context.read<CircleState>();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in cheers)
        Builder(
            builder: (note) => CheerNote(c.cheer,
                name: c.name,
                personId: c.id,
                onTap: credit.by != null &&
                        (c.id == circle.id ||
                            (c.id == null && c.name == circle.name))
                    ? () => showCheerSheet(note, credit)
                    : null)),
    ]);
  }
}

/// Volt, across the card.
class _CheerButton extends StatelessWidget {
  const _CheerButton(this.credit, {this.summary});
  final CircleCredit credit;
  final String? summary;

  @override
  Widget build(BuildContext context) => Builder(
        builder: (button) => FilledButton.icon(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: FloorPop.volt,
              foregroundColor: FloorPop.onVolt),
          onPressed: () => showCheerSheet(button, credit, summary: summary),
          icon: const CheerIcon(size: 18),
          label: const Text('Cheer'),
        ),
      );
}

class _PlayRow extends StatelessWidget {
  const _PlayRow(this.play);
  final CirclePlay play;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final mode = Modes.values.byName(play.mode);
    final chart = chartOf(play.song, mode, play.difficulty);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: SizedBox.square(
            dimension: 38,
            child: chart.song == null
                ? ColoredBox(
                    color: pop.riser,
                    child: Icon(Icons.music_note, color: pop.haze, size: 18))
                : JacketImage(chart.song!),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(chart.song?.title ?? play.song,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(children: [
              Text(mode == Modes.singles ? 'SP' : 'DP',
                  style: TextStyle(
                      color: pop.haze,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              DifficultyLabel(
                  difficulty: play.difficulty,
                  level: chart.level,
                  height: kSongListLevelHeight),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
              play.failed
                  ? 'FAILED'
                  : play.score == null
                      ? '—'
                      : _score(play.score!),
              style: FloorPop.readout(15,
                  color: play.failed ? FloorPop.coral : null)),
          if (play.best && !play.failed)
            Text('NEW BEST',
                style: FloorPop.readout(10, color: pop.up)
                    .copyWith(letterSpacing: 0.8)),
        ]),
      ]),
    );
  }

  static String _score(int s) =>
      s.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
}
