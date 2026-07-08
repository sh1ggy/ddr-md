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
  // kOcrFieldOrder names. Values are read at save time so user edits count.
  final Map<String, TextEditingController> controllers;

  const SaveScorePanel({super.key, required this.controllers});

  @override
  State<SaveScorePanel> createState() => _SaveScorePanelState();
}

class _SaveScorePanelState extends State<SaveScorePanel> {
  // Song explicitly chosen from the picker; overrides the automatic match
  // until cleared.
  SongInfo? _selectedSong;

  String _text(String key) => widget.controllers[key]?.text.trim() ?? '';

  int? _number(String key) {
    final digits = _text(key).replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  Future<void> _save(SongInfo song) async {
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
    showToast(context, 'Score saved for ${song.title}');
  }

  Future<void> _openPicker(String initialQuery) async {
    final picked = await showModalBottomSheet<SongInfo>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SongSearchSheet(initialQuery: initialQuery),
    );
    if (picked != null) {
      setState(() => _selectedSong = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleController = widget.controllers['title'];
    if (titleController == null) return const SizedBox.shrink();

    // Rebuild on every title change (OCR prefill or user edit) so the match
    // tracks the field live.
    return ListenableBuilder(
      listenable: titleController,
      builder: (context, _) {
        if (Songs.list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Song list not loaded — cannot link score to a song.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.orange),
            ),
          );
        }
        final match = Songs.matchTitle(titleController.text);
        final song = _selectedSong ?? match?.song;
        final isPicked = _selectedSong != null;
        final isWeak =
            !isPicked && (match == null || match.similarity < _kWeakMatchThreshold);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (song != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: InkWell(
                        onTap: () => _openPicker(titleController.text),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          child: Text(
                            isPicked
                                ? 'Selected song: ${song.title}'
                                : 'Matched song: ${song.title} '
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
                    onPressed: () => _openPicker(titleController.text),
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
              ElevatedButton.icon(
                onPressed: song == null ? null : () => _save(song),
                icon: const Icon(Icons.save),
                label: const Text('Save score'),
              ),
            ],
          ),
        );
      },
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
