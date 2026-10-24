/// Name: SnippetChartPicker
/// Parent: SnippetsPage
/// Description: First steps of adding a snippet: search for a song, pick its
/// mode and difficulty, then pick the section in the chart preview. Pops with
/// the saved [Snippet]. Leaves the Songs tab's selection alone.
library;

import 'package:ddr_md/components/song/notes/chart_preview_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class SnippetChartPicker extends StatefulWidget {
  const SnippetChartPicker({super.key});

  @override
  State<SnippetChartPicker> createState() => _SnippetChartPickerState();
}

class _SnippetChartPickerState extends State<SnippetChartPicker> {
  // Same cut-off as the song list's search.
  static const double _minSimilarity = 0.3;

  List<SongInfo> _results = Songs.list;

  void _search(String value) {
    value = value.trim();
    setState(() => _results = value.isEmpty
        ? Songs.list
        : [
            for (final m in Songs.matchTitles(value,
                limit: Songs.list.length, minSimilarity: _minSimilarity))
              m.song
          ]);
  }

  Future<void> _pick(SongInfo song) async {
    HapticFeedback.selectionClick();
    final chart = await showModalBottomSheet<(Modes, String)>(
      context: context,
      showDragHandle: true,
      builder: (_) => _DifficultySheet(
          song: song, initialMode: context.read<SongState>().modes),
    );
    if (chart == null || !mounted) return;
    final snippet = await Navigator.push<Snippet>(
      context,
      MaterialPageRoute(
        builder: (_) => ChartPreviewPage.forChart(song, chart.$1, chart.$2,
            newSnippet: true),
      ),
    );
    if (snippet != null && mounted) Navigator.pop(context, snippet);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: const GlassHeader(),
        title: TextField(
          autofocus: true,
          style: const TextStyle(
              fontSize: 20,
              color: Colors.blueGrey,
              fontWeight: FontWeight.w600),
          decoration: const InputDecoration(
              hintText: 'Search song...', border: InputBorder.none),
          onChanged: _search,
        ),
      ),
      body: ListView.builder(
        itemCount: _results.length,
        itemBuilder: (context, i) {
          final song = _results[i];
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image(
                width: 48,
                height: 48,
                image:
                    ContentStore.image('assets/jackets-160/${song.name}.png'),
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.music_note, size: 40),
              ),
            ),
            title: Text(song.title, overflow: TextOverflow.ellipsis),
            subtitle: Text(song.artist, overflow: TextOverflow.ellipsis),
            onTap: () => _pick(song),
          );
        },
      ),
    );
  }
}

// SP/DP and the difficulties that mode has; pops with the one tapped.
class _DifficultySheet extends StatefulWidget {
  const _DifficultySheet({required this.song, required this.initialMode});

  final SongInfo song;
  final Modes initialMode;

  @override
  State<_DifficultySheet> createState() => _DifficultySheetState();
}

class _DifficultySheetState extends State<_DifficultySheet> {
  late Modes _mode = widget.initialMode;

  @override
  Widget build(BuildContext context) {
    final difficulty =
        _mode == Modes.singles ? widget.song.singles : widget.song.doubles;
    final levels = difficulty.toJson();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.song.title,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            SegmentedButton<Modes>(
              segments: const [
                ButtonSegment(value: Modes.singles, label: Text('SP')),
                ButtonSegment(value: Modes.doubles, label: Text('DP')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            if (difficulty.availableTypes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No charts for this mode.'),
              ),
            for (final key in difficulty.availableTypes)
              ListTile(
                title: Text(kInGameDifficultyNames[key] ?? key,
                    style: TextStyle(
                        color: difficultyColor(key),
                        fontWeight: FontWeight.w900)),
                trailing: Text('${levels[key]}',
                    style: TextStyle(
                        color: difficultyColor(key),
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                onTap: () => Navigator.pop(context, (_mode, key)),
              ),
          ],
        ),
      ),
    );
  }
}
