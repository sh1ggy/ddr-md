/// Name: SaveScorePanel
/// Description: Shared by the load-image and camera pages. Fuzzy-matches the
/// OCR'd title against the master song list ([Songs]) via Levenshtein
/// distance and saves the score fields to that song's record in SQLite.
/// Tapping the matched song opens a searchable picker (ranked by the same
/// distance) to override the automatic match. The difficulty is a dropdown of
/// the charts that exist on the matched song, pre-selected by matching the
/// raw OCR reading against them (see [resolveOcrDifficulty]) — mirroring how
/// the song itself is matched-but-overridable.
library;

import 'dart:typed_data';

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/score_images.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Below this similarity the match is shown as a warning and likely wrong;
// the user can still fix the title field or pick from the list.
const double _kWeakMatchThreshold = 0.5;

class SaveScorePanel extends StatefulWidget {
  // The per-field OCR controllers owned by the parent page, keyed by the
  // kOcrFieldOrder names (excluding 'title'). Values are read at save time.
  final Map<String, TextEditingController> controllers;
  // Raw OCR'd title string used as the initial Levenshtein query. May be empty
  // when OCR didn't detect a title — the user can still open the picker.
  final String initialTitle;
  // Optional content rendered between the match header and save button.
  // Used by OCR pages to place editable fields above the save button.
  final List<Widget> middleChildren;
  // Called at save time for the proof image to store alongside the score
  // (the parent page's ROI overlay render or captured frame). Null result
  // saves the score without an image.
  final Future<Uint8List?> Function()? proofImageBytes;

  const SaveScorePanel({
    super.key,
    required this.controllers,
    required this.initialTitle,
    this.middleChildren = const [],
    this.proofImageBytes,
  });

  @override
  State<SaveScorePanel> createState() => _SaveScorePanelState();
}

class _SaveScorePanelState extends State<SaveScorePanel> {
  // Song explicitly chosen from the picker; overrides the automatic match.
  SongInfo? _selectedSong;
  // Difficulty explicitly chosen from the dropdown; overrides the automatic
  // match. Ignored when the current song doesn't have that chart (e.g. after
  // picking a different song).
  String? _pickedDifficulty;
  bool _savedOnce = false;

  // Username saved in settings, read once — settings can't change while this
  // panel is open. Empty when the user never set one (warning disabled).
  final String _savedUsername =
      Settings.getString(Settings.usernameKey).trim();

  String _text(String key) => widget.controllers[key]?.text.trim() ?? '';

  int? _number(String key) => parseOcrNumber(_text(key));

  Difficulty _levels(SongInfo song, Modes mode) =>
      mode == Modes.singles ? song.singles : song.doubles;

  // The played step count, summed from the judgment fields. Null unless all
  // five were read — a missing one would silently undercount the total.
  int? _judgedNoteTotal() {
    var total = 0;
    for (final key in const ['marvelous', 'perfect', 'great', 'good', 'miss']) {
      final n = _number(key);
      if (n == null) return null;
      total += n;
    }
    return total;
  }

  // Snaps the noisy OCR'd difficulty reading (e.g. "ert 16") to the in-game
  // name of a chart that exists on [song] in [mode], using the chart's
  // difficulty names and levels as evidence, with the judged step count vs
  // the charts' note counts as a fallback. Null when nothing matches.
  String? _resolvedDifficulty(SongInfo song, Modes mode) => resolveOcrDifficulty(
        _text('difficulty'),
        _levels(song, mode),
        notecounts: mode == Modes.singles
            ? song.singlesNotecounts
            : song.doublesNotecounts,
        totalNotes: _judgedNoteTotal(),
      );

  // The difficulty the score will be saved under: the user's dropdown pick
  // when it exists on this song, else the automatic OCR match.
  String? _effectiveDifficulty(SongInfo song, Modes mode) {
    final options = difficultyOptions(_levels(song, mode));
    if (options.any((o) => o.$1 == _pickedDifficulty)) {
      return _pickedDifficulty;
    }
    return _resolvedDifficulty(song, mode);
  }

  // The chart's note count for the OCR'd (in-game) difficulty name, keyed to
  // the StepMania-style fields of [Difficulty]. Null when the difficulty
  // doesn't resolve or the song has no note-count data.
  int? _chartNoteCount(SongInfo song, Modes mode) {
    final counts =
        mode == Modes.singles ? song.singlesNotecounts : song.doublesNotecounts;
    return switch (
        _effectiveDifficulty(song, mode) ?? _text('difficulty').toUpperCase()) {
      'BEGINNER' => counts.beginner,
      'BASIC' => counts.easy,
      'DIFFICULT' => counts.medium,
      'EXPERT' => counts.hard,
      'CHALLENGE' => counts.challenge,
      _ => null,
    };
  }

  // Max combo renders on screen as "combo/total note count". The OCR pipeline
  // keeps only the combo, but a misread '/' leaves the two numbers
  // concatenated — when the value exceeds the chart's note count and its
  // digits end with that count, strip the suffix to recover the combo.
  int? _maxCombo(SongInfo song, Modes mode) {
    final raw = _number('maxCombo');
    if (raw == null) return null;
    final noteCount = _chartNoteCount(song, mode);
    if (noteCount == null || noteCount <= 0 || raw <= noteCount) return raw;
    final digits = raw.toString();
    final suffix = noteCount.toString();
    if (!digits.endsWith(suffix)) return raw;
    final combo = int.parse(digits.substring(0, digits.length - suffix.length));
    return combo <= noteCount ? combo : raw;
  }

  Future<void> _save(SongInfo song) async {
    if (_savedOnce) return;
    // OCR results don't say which side was played, so file the score
    // under the app's currently selected mode.
    final mode = Provider.of<SongState>(context, listen: false).modes;
    // The dropdown selection (user pick or automatic match) is always a
    // canonical chart name; only an unresolvable reading with no pick falls
    // back to the raw OCR text.
    final difficulty = _effectiveDifficulty(song, mode) ?? _text('difficulty');
    final date = DateTime.now().toIso8601String();
    // The proof image is written first so the row never points at a path
    // that failed to save; an image that can't be produced isn't fatal.
    String imagePath = '';
    final bytes = await widget.proofImageBytes?.call();
    if (bytes != null) {
      imagePath = await ScoreImages.save(bytes, date);
    }
    final score = Score(
      date: date,
      songTitle:
          song.titletranslit.isNotEmpty ? song.titletranslit : song.title,
      mode: mode,
      difficulty: difficulty,
      username: _text('username'),
      // The dropdown writes canonical ranks into the controller; only an
      // unresolvable reading the user never touched falls back to raw text.
      flare: resolveOcrFlare(_text('flare')) ?? _text('flare'),
      score: _number('score'),
      marvelous: _number('marvelous'),
      perfect: _number('perfect'),
      great: _number('great'),
      good: _number('good'),
      miss: _number('miss'),
      maxCombo: _maxCombo(song, mode),
      imagePath: imagePath,
    );
    await DatabaseProvider.addScore(score);
    if (!mounted) return;
    setState(() => _savedOnce = true);
    showToast(context, 'Score saved for ${song.title}');
  }

  Future<void> _openPicker() async {
    final picked = await showModalBottomSheet<SongInfo>(
      context: context,
      isScrollControlled: true,
      // Keep the sheet out of the top notch when the keyboard pushes it up
      // on small screens.
      useSafeArea: true,
      builder: (context) =>
          _SongSearchSheet(initialQuery: widget.initialTitle),
    );
    if (picked != null) {
      setState(() => _selectedSong = picked);
    }
  }

  ({SongInfo? song, SongMatch? match, bool isPicked, bool isWeak})
      _resolveMatchState() {
    if (Songs.list.isEmpty) {
      return (song: null, match: null, isPicked: false, isWeak: true);
    }
    final match = _selectedSong == null
        ? Songs.matchTitle(widget.initialTitle)
        : null;
    final isPicked = _selectedSong != null;
    final song = _selectedSong ?? match?.song;
    final isWeak =
        !isPicked && (match == null || match.similarity < _kWeakMatchThreshold);
    return (song: song, match: match, isPicked: isPicked, isWeak: isWeak);
  }

  @override
  Widget build(BuildContext context) {
    final state = _resolveMatchState();
    final mode = context.watch<SongState>().modes;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMatchContent(
            context,
            song: state.song,
            match: state.match,
            isPicked: state.isPicked,
            isWeak: state.isWeak,
          ),
          if (state.song != null) _buildDifficultyRow(state.song!, mode),
          if (widget.middleChildren.isNotEmpty) ...widget.middleChildren,
          _buildUsernameMismatchWarning(),
          buildSaveButton(
            padding: EdgeInsets.only(top: widget.middleChildren.isEmpty ? 0 : 12),
          ),
        ],
      ),
    );
  }

  // Difficulty dropdown in the style of the OCR field rows: it offers only
  // the charts that exist on [song] in [mode], pre-selected with the
  // automatic match for the raw OCR reading — the difficulty counterpart of
  // the matched-but-overridable song row above it.
  Widget _buildDifficultyRow(SongInfo song, Modes mode) {
    final options = difficultyOptions(_levels(song, mode));
    if (options.isEmpty) return const SizedBox.shrink();
    final isPicked = options.any((o) => o.$1 == _pickedDifficulty);
    final value = _effectiveDifficulty(song, mode);
    final raw = _text('difficulty');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'DIFFICULTY',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: value,
                    isExpanded: true,
                    hint: Text(
                      // No chart matched the reading — show it so the user
                      // knows what the scan said while they pick.
                      raw.isEmpty ? 'Select…' : '"$raw"?',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    items: [
                      for (final (name, level) in options)
                        DropdownMenuItem(
                          value: name,
                          child: Text(
                            '$name $level',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: kInGameDifficultyColors[name],
                            ),
                          ),
                        ),
                    ],
                    onChanged: _savedOnce
                        ? null
                        : (v) => setState(() => _pickedDifficulty = v),
                  ),
                ),
                if (isPicked)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Back to automatic match',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _pickedDifficulty = null),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Gentle heads-up when the detected player name isn't the username saved in
  // settings — the screenshot may be someone else's score (e.g. the other
  // player's side, or a friend's photo). Purely informational: saving is not
  // blocked. Listens to the username controller so edits to the field update
  // the warning live. Silent when no username is set in settings or none was
  // detected.
  Widget _buildUsernameMismatchWarning() {
    final controller = widget.controllers['username'];
    if (_savedUsername.isEmpty || controller == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final detected = value.text.trim();
        if (detected.isEmpty ||
            detected.toUpperCase() == _savedUsername.toUpperCase()) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Detected player "$detected" doesn\'t match '
            'your username "$_savedUsername".',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.orange),
          ),
        );
      },
    );
  }

  Widget buildSaveButton({EdgeInsetsGeometry? padding}) {
    final state = _resolveMatchState();
    final song = state.song;
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: ElevatedButton.icon(
        onPressed: (song == null || _savedOnce) ? null : () => _save(song),
        icon: const Icon(Icons.save),
        label: Text(_savedOnce ? 'Saved' : 'Save score'),
      ),
    );
  }

  Widget _buildMatchContent(
    BuildContext context, {
    required SongInfo? song,
    required SongMatch? match,
    required bool isPicked,
    required bool isWeak,
  }) {
    if (Songs.list.isEmpty) {
      return const Text(
        'Song list not loaded — cannot link score to a song.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.orange),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (song != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: InkWell(
                  onTap: _openPicker,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(
                      isPicked
                          ? 'Selected: ${song.title}'
                          : 'Matched: ${song.title} '
                              '(${(match!.similarity * 100).round()}%)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isWeak ? Colors.orange : Colors.green,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
              if (isPicked)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Back to automatic match',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _selectedSong = null),
                ),
            ],
          )
        else
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: _openPicker,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Choose song'),
            ),
          ),
        if (isWeak)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              match == null
                  ? 'No song matched — tap to search for one.'
                  : 'Weak match — tap the song name to pick another.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

// Bottom-sheet song picker: a search field prefilled with the OCR'd title and
// a result list ranked by Levenshtein similarity, updating as the user types.
// Pops with the chosen SongInfo.
class _SongSearchSheet extends StatefulWidget {
  final String initialQuery;

  const _SongSearchSheet({required this.initialQuery});

  @override
  State<_SongSearchSheet> createState() => _SongSearchSheetState();
}

class _SongSearchSheetState extends State<_SongSearchSheet> {
  late final TextEditingController _searchController =
      TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = Songs.matchTitles(_searchController.text, limit: 20);
    return Padding(
      // Keep the sheet above the on-screen keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search songs…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.trim().isEmpty
                            ? 'Type to search the song list.'
                            : 'No songs found.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final m = matches[i];
                        final translit = m.song.titletranslit;
                        return ListTile(
                          dense: true,
                          title: Text(m.song.title),
                          subtitle:
                              translit.isNotEmpty && translit != m.song.title
                                  ? Text(translit)
                                  : null,
                          trailing: Text(
                            '${(m.similarity * 100).round()}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, m.song),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
