/// Name: ArcadeInfoPanel
/// Parent: ArcadeGridView
/// Description: The panel that rises from the bottom once a jacket is focused,
/// standing in for the cabinet's song banner: jacket, title, BPM for the
/// picked chart, the difficulty picker, the favourite toggle and SELECT.
library;

import 'package:ddr_md/components/songlist/arcade/arcade_theme.dart';
import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Height the grid reserves under itself so a focused tile in the last row can
// still scroll clear of the panel.
const double kArcadeInfoPanelHeight = 132;

class ArcadeInfoPanel extends StatelessWidget {
  const ArcadeInfoPanel({
    super.key,
    required this.item,
    required this.onConfirm,
    required this.onClose,
    required this.onFavToggled,
  });

  final SongItem item;
  final VoidCallback onConfirm;
  final VoidCallback onClose;
  final VoidCallback onFavToggled;

  @override
  Widget build(BuildContext context) {
    final songState = context.watch<SongState>();
    final SongInfo song = item.songInfo;
    final Difficulty difficulty =
        songState.modes == Modes.singles ? song.singles : song.doubles;
    final List<String> types = difficulty.availableTypes;
    // Per-chart songs carry one entry per difficulty, so the BPM shown has to
    // follow the picker; single-chart songs clamp back to their only chart.
    final String? bpmRange = song.charts.isEmpty
        ? null
        : song.charts[songState.chosenDifficulty
                .clamp(0, song.charts.length - 1)]
            .bpmRange;

    // The fixed height is the panel's own content; the home-indicator inset is
    // added on top so the bottom safe area doesn't eat into the controls.
    return Container(
      height: kArcadeInfoPanelHeight + MediaQuery.paddingOf(context).bottom,
      decoration: const BoxDecoration(
        color: kArcadeSurface,
        border: Border(top: BorderSide(color: kArcadeAccent, width: 2)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black54, blurRadius: 14, spreadRadius: 2),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 64,
                height: 64,
                child: Image(
                  image: AssetImage('assets/jackets-160/${song.name}.png'),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const ColoredBox(
                    color: kArcadeBackdrop,
                    child: Icon(Icons.music_note,
                        size: 24, color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: kArcadeFont,
                        fontSize: 16,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Text(
                          song.version,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white38),
                        ),
                        const SizedBox(width: 8),
                        if (bpmRange != null)
                          Text(
                            '$bpmRange BPM',
                            style: const TextStyle(
                              fontFamily: kArcadeFont,
                              fontSize: 12,
                              color: kArcadeAccent,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _DifficultyBadges(
                      difficulty: difficulty,
                      types: types,
                      chosen: types.isEmpty
                          ? 0
                          : songState.chosenDifficulty
                              .clamp(0, types.length - 1),
                      onPick: songState.setChosenDifficulty,
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _FavStar(
                        song: song,
                        mode: songState.modes,
                        isFav: item.isFav,
                        onToggled: onFavToggled,
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close,
                            size: 20, color: Colors.white38),
                        tooltip: 'Clear selection',
                        onPressed: onClose,
                      ),
                    ],
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kArcadeAccent,
                      foregroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 6),
                    ),
                    onPressed: onConfirm,
                    child: const Text(
                      'SELECT',
                      style: TextStyle(
                        fontFamily: kArcadeFont,
                        fontSize: 14,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// The level badges, one per chart the mode actually has, in the same
// beginner..challenge order chosenDifficulty indexes into (see
// SongDifficultyPicker). Dark-styled rather than reusing that widget, whose
// ToggleButtons chrome fights the cabinet look.
class _DifficultyBadges extends StatelessWidget {
  const _DifficultyBadges({
    required this.difficulty,
    required this.types,
    required this.chosen,
    required this.onPick,
  });

  final Difficulty difficulty;
  final List<String> types;
  final int chosen;
  final void Function(int) onPick;

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) {
      return const Text(
        'No charts in this mode',
        style: TextStyle(fontSize: 11, color: Colors.white38),
      );
    }

    final Map<String, dynamic> levels = difficulty.toJson();
    return Row(
      children: <Widget>[
        for (int i = 0; i < types.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onPick(i),
              child: Container(
                width: 30,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == chosen
                      ? difficultyColor(types[i])
                      : difficultyColor(types[i]).withValues(alpha: 0.15),
                  border: Border.all(
                    color: i == chosen
                        ? Colors.white
                        : difficultyColor(types[i]).withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  '${levels[types[i]]}',
                  style: TextStyle(
                    fontFamily: kArcadeFont,
                    fontSize: 13,
                    color:
                        i == chosen ? Colors.black : difficultyColor(types[i]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Favourites are keyed by (titletranslit, mode), same as the song page's star.
class _FavStar extends StatelessWidget {
  const _FavStar({
    required this.song,
    required this.mode,
    required this.isFav,
    required this.onToggled,
  });

  final SongInfo song;
  final Modes mode;
  final bool isFav;
  final VoidCallback onToggled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(
        isFav ? Icons.star : Icons.star_border,
        size: 22,
        color: isFav ? Colors.yellow : Colors.white38,
      ),
      tooltip: isFav ? 'Unfavourite' : 'Favourite',
      onPressed: () async {
        HapticFeedback.lightImpact();
        final Favorite? existing =
            await DatabaseProvider.getFavoriteBySong(song.titletranslit, mode);
        if (existing == null) {
          await DatabaseProvider.addFavorite(Favorite(
            id: 0,
            isFav: true,
            songTitle: song.titletranslit,
            mode: mode,
          ));
        } else {
          await DatabaseProvider.deleteFavorite(existing);
        }
        onToggled();
      },
    );
  }
}
