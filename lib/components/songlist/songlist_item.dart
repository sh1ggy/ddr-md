/// Name: SongListItem
/// Parent: DifficultyListPage, FavoriteListPage
/// Description: Rendering out the song item itself.
library;

import 'package:ddr_md/components/song/song_difficulties.dart';
import 'package:ddr_md/components/song/song_patterns.dart';
import 'package:ddr_md/models/pattern_model.dart';
import 'package:ddr_md/components/song/song_sync_status.dart';
import 'package:ddr_md/constants.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/flare_card.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/score_overview.dart' show flareGroup;
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/router.dart';
import 'package:ddr_md/theme.dart';
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
  /// The scoped chart's category as a badge for the jacket's corner: the
  /// player's pick, else the suggested one.
  Widget _category(BuildContext context, Modes mode) {
    final difficulty = (mode == Modes.singles
            ? widget.songInfo.singles
            : widget.songInfo.doubles)
        .availableTypes[widget.difficultyIndex!];
    return FutureBuilder(
      future: PatternsLoader.cached(widget.songInfo.name),
      builder: (context, snapshot) {
        final category = chartCategory(
            widget.songInfo.name, mode, difficulty, snapshot.data);
        if (category == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Tooltip(
          message: kCategoryLabels[category]!,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: FloorPop.of(context).stage, width: 2),
            ),
            child: Icon(kCategoryIcons[category],
                size: 13, color: scheme.onPrimary),
          ),
        );
      },
    );
  }

  Widget _syncAdjust(BuildContext context) {
    final chart = widget.difficultyIndex == null
        ? widget.songInfo.charts.first
        : widget.songInfo.chartAt(
            Provider.of<SongState>(context, listen: false).modes,
            widget.difficultyIndex!);
    return SongSyncStatus(
        sync: widget.songInfo.displaySyncFor(chart), compact: true);
  }

  @override
  Widget build(BuildContext context) {
    // Only the mode is shown, so other SongState changes don't rebuild rows.
    final Modes mode = context.select<SongState, Modes>((s) => s.modes);
    // Only a row standing for one chart shows the player's best on it. Hiding
    // the bests keeps the card and folds its score band away; the best is
    // still read so there's something to fold.
    final bool scoped = widget.difficultyIndex != null;
    final bool shown = scoped && ChartBests.shown;
    final best = scoped
        ? ChartBests.at(widget.songInfo, mode, widget.difficultyIndex!)
        : null;
    final stats = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(widget.songInfo.charts[0].bpmRange),
        _syncAdjust(context),
        // The song's flare group, what the cabinet sorts folders and flare
        // skill by.
        if (flareGroup(canonicalVersion(widget.songInfo.version))
            case final group?)
          Text(group.label,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: group
                      .color(Theme.of(context).brightness == Brightness.dark))),
      ],
    );
    // Fixed height so every row is the same size; a song without a
    // transliteration centres its title and levels instead of leaving a gap.
    final titleBlock = SizedBox(
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
    );
    Future<void> open() async {
      await context.push(
          songPath(widget.songInfo, difficulty: widget.difficultyIndex ?? 0));
      widget.regenFavsCallback?.call();
    }

    final tile = ListTile(
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // A fixed square, so the title doesn't shift when the jacket arrives.
      // Sized to ListTile's icon height cap, which shrinks with the density
      // (48 on desktop); any wider and the jacket squashes.
      leading: SizedBox.square(
        dimension:
            56 + VisualDensity.adaptivePlatformDensity.baseSizeAdjustment.dy,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              // Search results reshuffle every keystroke, so their jackets
              // snap in.
              child: widget.isSearch
                  ? JacketImage(widget.songInfo,
                      fade: const Duration(milliseconds: 80))
                  : JacketImage(widget.songInfo),
            ),
          ),
          if (scoped)
            Positioned(right: -6, bottom: -6, child: _category(context, mode)),
        ]),
      ),
      title: titleBlock,
      trailing: stats,
      onTap: scoped ? null : open,
    );
    if (!scoped) return tile;
    final flare = best?.flare;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: BestsReveal(
        shown: shown,
        builder: (context, t) => Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: revealBack(
              plain: flareCardBack(context, null, radius: 12),
              flare: flare == null
                  ? const BoxDecoration()
                  : flareCardBack(context, flare, radius: 12),
              t: t,
              // Ink draws above the card back rather than under it.
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: open,
                  child: Column(children: [
                    tile,
                    // Flare, grade and lamp on the left, the best score's tab
                    // flush with the right edge, its full height.
                    unfoldBand(
                      t,
                      CardFooter(
                        padding: const EdgeInsets.only(left: 16),
                        child: IntrinsicHeight(
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 5),
                                  child: ChartBestBadges(best,
                                      ink: 12, height: 20),
                                ),
                                const Spacer(),
                                BestScore(best),
                              ]),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          if (flare != null && t > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: t,
                  child: CustomPaint(painter: FlareFrame(flare, radius: 12)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
