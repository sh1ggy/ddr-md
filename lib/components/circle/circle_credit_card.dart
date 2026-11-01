/// Name: CircleCreditCard
/// Parent: CirclePersonPage, CheersStrip
/// Description: A shared credit: its songs with jacket, difficulty, score,
/// new bests and fails, the cheers on it as stamps, and, for someone
/// else's, the pom-pom Cheer button that opens the cheer sheet.
library;

import 'package:ddr_md/components/circle/cheer_sheet.dart';
import 'package:ddr_md/components/circle/cheer_stamp.dart';
import 'package:ddr_md/components/session/recent_plays.dart' show chartOf;
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

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
          Text(_ago(credit.at),
              style: TextStyle(color: pop.haze, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        for (final p in credit.plays) _PlayRow(p),
        if (credit.cheers.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in credit.cheers) CheerStamp(c.cheer, name: c.name),
          ]),
        ],
        if (credit.by != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Builder(
              builder: (button) => FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor:
                        credit.mine == null ? FloorPop.volt : pop.riser,
                    foregroundColor: credit.mine == null
                        ? FloorPop.onVolt
                        : scheme.onSurface),
                onPressed: () => showCheerSheet(button, credit),
                icon: const PomPom(size: 18),
                label: Text(credit.mine == null ? 'Cheer' : 'Change cheer'),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
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
