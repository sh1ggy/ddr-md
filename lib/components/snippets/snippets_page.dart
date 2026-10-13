/// Name: SnippetsPage
/// Parent: App (Snippets tab)
/// Description: Saved chart sections, newest first. Tapping one opens its
/// chart looping the section; Add starts a new one from a song search.
library;

import 'package:ddr_md/components/snippets/snippet_chart_picker.dart';
import 'package:ddr_md/components/snippets/snippet_feed_page.dart';
import 'package:ddr_md/components/song/notes/chart_preview_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:ddr_md/models/pattern_model.dart';
import 'package:ddr_md/models/parity_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SnippetsPage extends StatefulWidget {
  const SnippetsPage({super.key});

  @override
  State<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends State<SnippetsPage> {
  List<Snippet>? _snippets;
  final _counts = <String, Future<Map<Pattern, int>>>{};

  Future<Map<Pattern, int>> _patterns(Snippet s) async {
    final steps = await StepsLoader.load(s.song);
    final chart = steps?.chartFor(s.mode, s.difficulty);
    if (chart == null) return {};
    final selected = chart.notes
        .where((n) => n.beat >= s.startBeat && n.beat <= s.endBeat)
        .toList();
    if (selected.isEmpty) return {};
    final from = selected.first.second, to = selected.last.second;
    final analysis =
        analyseChart(chart.notes, s.mode, weights: ParityProfile.active);
    final counts = <Pattern, int>{};
    for (final span in analysis.footwork.spans) {
      if (span.$2 >= from - 1e-6 && span.$3 <= to + 1e-6) {
        counts[span.$1] = (counts[span.$1] ?? 0) + 1;
      }
    }
    return counts;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snippets = await DatabaseProvider.getAllSnippets();
    _counts.clear();
    if (mounted) setState(() => _snippets = snippets);
  }

  SongInfo? _songOf(Snippet s) =>
      Songs.list.where((song) => song.name == s.song).firstOrNull;

  Future<void> _add() async {
    HapticFeedback.selectionClick();
    await Navigator.push<Snippet>(
        context, MaterialPageRoute(builder: (_) => const SnippetChartPicker()));
    _load();
  }

  Future<void> _open(Snippet s, SongInfo song) async {
    HapticFeedback.selectionClick();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChartPreviewPage.forChart(song, s.mode, s.difficulty, snippet: s),
      ),
    );
    _load();
  }

  Future<void> _rename(Snippet s) async {
    final controller = TextEditingController(text: s.label);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename snippet'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (label == null) return;
    await DatabaseProvider.saveSnippet(s.copyWith(label: label));
    _load();
  }

  Future<void> _menu(Snippet s) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(context, 'rename')),
        ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            onTap: () => Navigator.pop(context, 'delete')),
      ])),
    );
    if (!mounted) return;
    if (action == 'rename') await _rename(s);
    if (action == 'delete') {
      setState(() =>
          _snippets = _snippets?.where((item) => item.id != s.id).toList());
      await _delete(s);
    }
  }

  Future<void> _delete(Snippet s) async {
    await DatabaseProvider.deleteSnippet(s.id);
    _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        // A snackbar with an action otherwise stays up until dismissed.
        persist: false,
        content: const Text('Snippet deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await DatabaseProvider.saveSnippet(s);
            _load();
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final snippets = _snippets;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.black,
        shadowColor: Colors.black,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.blueGrey),
        title: const Text('Snippets',
            style: TextStyle(
                fontSize: 20,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _add,
              tooltip: 'Add snippet',
              icon: const Icon(Icons.add_rounded))
        ],
      ),
      body: snippets == null
          ? const Center(child: CircularProgressIndicator())
          : snippets.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Save a section of any chart to loop it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : Column(children: [
                  Expanded(
                      child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: snippets.length,
                    itemBuilder: (context, i) => _tile(snippets[i]),
                  )),
                  Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: FilledButton.icon(
                            onPressed: snippets.any((s) => _songOf(s) != null)
                                ? () async {
                                    await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => SnippetFeedPage(
                                                snippets: snippets)));
                                    _load();
                                  }
                                : null,
                            icon: const Icon(Icons.shuffle_rounded),
                            label: const Text('Play shuffle'),
                          ))),
                ]),
    );
  }

  Widget _tile(Snippet s) {
    final song = _songOf(s);
    final difficulty = song == null
        ? null
        : (s.mode == Modes.singles ? song.singles : song.doubles)
            .toJson()[s.difficulty];
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade700,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _delete(s),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image(
            width: 48,
            height: 48,
            image: ContentStore.image('assets/jackets-160/${s.song}.png'),
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.music_note, size: 40),
          ),
        ),
        title: Text(song?.title ?? s.song, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${s.mode == Modes.singles ? 'SP' : 'DP'} '
                '${kInGameDifficultyNames[s.difficulty] ?? s.difficulty}'
                '${difficulty == null ? '' : ' $difficulty'}',
                style: TextStyle(
                    color: difficultyColor(s.difficulty),
                    fontWeight: FontWeight.w700)),
            if (s.label.isNotEmpty)
              Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            FutureBuilder<Map<Pattern, int>>(
              future: _counts.putIfAbsent(
                  '${s.id}:${s.startBeat}:${s.endBeat}', () => _patterns(s)),
              builder: (_, snapshot) => Wrap(
                spacing: 10,
                children: [
                  for (final entry
                      in (snapshot.data ?? <Pattern, int>{}).entries)
                    Tooltip(
                      message: '${kPatternLabels[entry.key]}: ${entry.value}',
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(kPatternIcons[entry.key], size: 16),
                        const SizedBox(width: 3),
                        Text('${entry.value}'),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
        enabled: song != null,
        onTap: song == null ? null : () => _open(s, song),
        onLongPress: () => _menu(s),
        trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Snippet actions',
            onPressed: () => _menu(s)),
      ),
    );
  }
}
