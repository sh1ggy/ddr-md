/// Name: SongSearchSheet
/// Parent: SaveScorePanel, SessionTrendsView
/// Description: Shared fuzzy song/chart picker with small jackets, cabinet
/// difficulty lettering and keyboard-aware sizing.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';

/// A song choice, or one specific chart when [difficulty] is supplied.
class SongSearchOption<T> {
  const SongSearchOption({
    required this.value,
    required this.song,
    required this.mode,
    this.difficulty,
    this.level,
  });

  final T value;
  final SongInfo song;
  final Modes mode;
  final String? difficulty;
  final int? level;
}

Future<T?> showSongSearchSheet<T>(
  BuildContext context, {
  required List<SongSearchOption<T>> options,
  String initialQuery = '',
  T? selected,
  bool browseWhenEmpty = false,
  ({String label, T value})? allOption,
}) =>
    showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SongSearchSheet<T>(
        options: options,
        initialQuery: initialQuery,
        selected: selected,
        browseWhenEmpty: browseWhenEmpty,
        allOption: allOption,
      ),
    );

class SongSearchSheet<T> extends StatefulWidget {
  const SongSearchSheet({
    super.key,
    required this.options,
    this.initialQuery = '',
    this.selected,
    this.browseWhenEmpty = false,
    this.allOption,
  });

  final List<SongSearchOption<T>> options;
  final String initialQuery;
  final T? selected;
  final bool browseWhenEmpty;
  final ({String label, T value})? allOption;

  @override
  State<SongSearchSheet<T>> createState() => _SongSearchSheetState<T>();
}

class _SongSearchSheetState<T> extends State<SongSearchSheet<T>> {
  late final _search = TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rank songs first, then retain each of their eligible chart choices.
    // History can contain several modes/difficulties of the same song.
    final bySong = <String, List<SongSearchOption<T>>>{};
    for (final option in widget.options) {
      (bySong[option.song.name] ??= []).add(option);
    }
    final songs = [for (final group in bySong.values) group.first.song];
    final matches = _search.text.trim().isEmpty && widget.browseWhenEmpty
        ? [for (final song in songs) SongMatch(song, 0)]
        : Songs.matchTitles(_search.text, limit: 20, candidates: songs);
    final results = [
      for (final match in matches)
        for (final option in bySong[match.song.name]!)
          (option: option, similarity: match.similarity),
    ];
    final searching = _search.text.trim().isNotEmpty;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(builder: (context, constraints) {
      final height = (MediaQuery.sizeOf(context).height * 0.6).clamp(
          0.0, (constraints.maxHeight - bottom).clamp(0.0, double.infinity));
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: height,
          child: SafeArea(
            top: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    hintText: 'Search songs…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear',
                            onPressed: () => setState(_search.clear),
                          ),
                    isDense: true,
                  ),
                ),
              ),
              if (widget.allOption case final all?)
                ListTile(
                  dense: true,
                  title: Text(all.label),
                  trailing:
                      widget.selected == null || widget.selected == all.value
                          ? const Icon(Icons.check)
                          : null,
                  onTap: () => Navigator.pop(context, all.value),
                ),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            searching || widget.browseWhenEmpty
                                ? 'No songs found.'
                                : 'Type to search the song list.',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.builder(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final (:option, :similarity) = results[index];
                          final song = option.song;
                          final mode =
                              option.mode == Modes.singles ? 'SP' : 'DP';
                          final levels = option.mode == Modes.singles
                              ? song.singles
                              : song.doubles;
                          return ListTile(
                            dense: true,
                            selected: widget.selected == option.value,
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox.square(
                                dimension: 40,
                                child: JacketImage(song),
                              ),
                            ),
                            title: Text(song.title,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (song.titletranslit.isNotEmpty &&
                                    song.titletranslit != song.title)
                                  Text(song.titletranslit,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(mode),
                                    if (option.difficulty
                                        case final difficulty?)
                                      Semantics(
                                        label:
                                            '$difficulty ${option.level ?? "level unknown"}',
                                        child: ExcludeSemantics(
                                          child: DifficultyLabel(
                                            difficulty: difficulty,
                                            level: option.level,
                                            height: kSongListLevelHeight,
                                          ),
                                        ),
                                      )
                                    else
                                      LevelRow(
                                        levels: levels,
                                        height: kSongListLevelHeight,
                                        packed: true,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (searching)
                                  Text('${(similarity * 100).round()}%',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)),
                                if (widget.selected == option.value) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.check, size: 18),
                                ],
                              ],
                            ),
                            onTap: () => Navigator.pop(context, option.value),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}
