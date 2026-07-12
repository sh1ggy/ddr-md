/// Name: SaveScorePanel
/// Description: Shared by the load-image and camera pages. Fuzzy-matches the
/// OCR'd title against the master song list ([Songs]) via Levenshtein
/// distance and saves the score fields to that song's record in SQLite.
/// Tapping the matched song opens a searchable picker (ranked by the same
/// distance) to override the automatic match.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';

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

  const SaveScorePanel({
    super.key,
    required this.controllers,
    required this.initialTitle,
    this.middleChildren = const [],
  });

  @override
  State<SaveScorePanel> createState() => _SaveScorePanelState();
}

class _SaveScorePanelState extends State<SaveScorePanel> {
  // Song explicitly chosen from the picker; overrides the automatic match.
  SongInfo? _selectedSong;
  bool _savedOnce = false;

  String _text(String key) => widget.controllers[key]?.text.trim() ?? '';

  int? _number(String key) => parseOcrNumber(_text(key));

  Future<void> _save(SongInfo song) async {
    if (_savedOnce) return;
    final score = Score(
      date: DateTime.now().toIso8601String(),
      songTitle:
          song.titletranslit.isNotEmpty ? song.titletranslit : song.title,
      difficulty: _text('difficulty'),
      username: _text('username'),
      flare: _text('flare'),
      score: _number('score'),
      marvelous: _number('marvelous'),
      perfect: _number('perfect'),
      great: _number('great'),
      good: _number('good'),
      miss: _number('miss'),
      maxCombo: _number('maxCombo'),
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
          if (widget.middleChildren.isNotEmpty) ...widget.middleChildren,
          buildSaveButton(
            padding: EdgeInsets.only(top: widget.middleChildren.isEmpty ? 0 : 12),
          ),
        ],
      ),
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
