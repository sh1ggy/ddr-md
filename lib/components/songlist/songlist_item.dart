/// Name: SongListItem
/// Parent: DifficultyListPage, FavoriteListPage
/// Description: Rendering out the song item itself.
library;

import 'package:ddr_md/components/song/song_difficulties.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class SongListItem extends StatefulWidget {
  const SongListItem(
      {super.key,
      required this.songInfo,
      required this.isFav,
      required this.isSearch,
      this.difficultyIndex,
      this.regenFavsCallback});
  final SongInfo songInfo;
  final bool isFav;
  final bool isSearch;
  // The chart this row stands for: opens the song there and marks it in the
  // difficulty strip.
  final int? difficultyIndex;
  final void Function()? regenFavsCallback; // callback function for navigator

  @override
  State<SongListItem> createState() => _SongListItemState();
}

class _SongListItemState extends State<SongListItem> {
  // The recommended in-game offset adjustment, same figure the song page's
  // sync card leads with: the bias with its sign flipped. Null when this song
  // has no sync data, so the row can fall back to the version.
  Widget? _syncAdjust(BuildContext context) {
    final chart = widget.difficultyIndex == null
        ? widget.songInfo.charts.first
        : widget.songInfo.chartAt(
            Provider.of<SongState>(context, listen: false).modes,
            widget.difficultyIndex!);
    final sync = widget.songInfo.displaySyncFor(chart);
    if (sync == null) return null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Rounded first, so a bias under half a ms reads +0, never +-0.
    final adjustBy = (-sync.biasMs).round();
    return Text(
      '${adjustBy >= 0 ? '+' : ''}$adjustBy ms',
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: sync.biasMs < 0
            ? kSlowColor(isDark)
            : sync.biasMs > 0
                ? kFastColor(isDark)
                : Colors.grey.shade600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only the mode is shown, so other SongState changes don't rebuild rows.
    final Modes mode = context.select<SongState, Modes>((s) => s.modes);
    return ListTile(
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // A fixed square (ListTile caps it at its icon height), so the title
      // doesn't shift when the jacket arrives.
      leading: SizedBox.square(
        dimension: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: JacketImage(widget.songInfo),
        ),
      ),
      // Fixed height so every row is the same size; a song without a
      // transliteration centres its title and levels instead of leaving a gap.
      title: SizedBox(
        height: 54,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.songInfo.title,
              maxLines: 1,
              style: const TextStyle(
                  fontSize: 16,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                  overflow: TextOverflow.ellipsis),
            ),
            if (widget.songInfo.titletranslit.isNotEmpty &&
                widget.songInfo.titletranslit != widget.songInfo.title)
              Text(
                widget.songInfo.titletranslit,
                maxLines: 1,
                style: const TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: Colors.grey,
                    overflow: TextOverflow.ellipsis),
              ),
            // Same fixed gap under every line so the rows read evenly.
            const SizedBox(height: 4),
            SongDifficulty(
                difficulty: mode == Modes.singles
                    ? widget.songInfo.singles
                    : widget.songInfo.doubles,
                highlightIndex: widget.difficultyIndex),
          ],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _syncAdjust(context) ?? Text(widget.songInfo.version),
          Text(widget.songInfo.charts[0].bpmRange),
        ],
      ),
      onTap: () async {
        await context.push(
            songPath(widget.songInfo, difficulty: widget.difficultyIndex ?? 0));
        widget.regenFavsCallback?.call();
      },
    );
  }
}
