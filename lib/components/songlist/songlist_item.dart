/// Name: SongListItem
/// Parent: DifficultyListPage, FavoriteListPage
/// Description: Rendering out the song item itself.
library;

import 'package:ddr_md/components/song/song_difficulties.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/components/song/song_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
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
    final charts = widget.songInfo.charts;
    final chart = charts[widget.difficultyIndex != null &&
            widget.difficultyIndex! < charts.length
        ? widget.difficultyIndex!
        : 0];
    final sync = widget.songInfo.displaySyncFor(chart);
    if (sync == null) return null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adjustBy = -sync.biasMs;
    return Text(
      '${adjustBy >= 0 ? '+' : ''}${adjustBy.toStringAsFixed(1)} ms',
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
    var songState = context.watch<SongState>();
    return ListTile(
      visualDensity: VisualDensity.adaptivePlatformDensity,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(
          image: AssetImage('assets/jackets-160/${widget.songInfo.name}.png'),
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.music_note, size: 40),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.songInfo.title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                overflow: widget.isSearch
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis),
          ),
          if (widget.songInfo.titletranslit.isNotEmpty &&
              widget.songInfo.titletranslit != widget.songInfo.title)
            Text(
              widget.songInfo.titletranslit,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  overflow: widget.isSearch
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis),
            ),
        ],
      ),
      subtitle: SongDifficulty(
          difficulty: songState.modes == Modes.singles
              ? widget.songInfo.singles
              : widget.songInfo.doubles,
          highlightIndex: widget.difficultyIndex),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _syncAdjust(context) ?? Text(widget.songInfo.version),
          Text(widget.songInfo.charts[0].bpmRange),
        ],
      ),
      onTap: () async {
        songState.setSongInfo(widget.songInfo);
        songState.setChosenDifficulty(widget.difficultyIndex ?? 0);
        await Navigator.push(context,
                MaterialPageRoute(builder: (context) => const SongPage()))
            .then((_) {
          if (widget.regenFavsCallback != null) {
            widget.regenFavsCallback!();
          }
        });
      },
    );
  }
}
