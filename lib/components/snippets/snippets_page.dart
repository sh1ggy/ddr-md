/// Name: SnippetsPage
/// Parent: App (Snippets tab)
/// Description: Saved chart sections, newest first. Tapping one opens its
/// chart looping the section; Shuffle deals them as a feed, and Add starts a
/// new one from a song search.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:ddr_md/components/snippets/snippet_chart_picker.dart';
import 'package:ddr_md/components/snippets/snippet_feed_page.dart';
import 'package:ddr_md/components/song/notes/chart_preview_page.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
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
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SnippetsPage extends StatefulWidget {
  const SnippetsPage({super.key});

  @override
  State<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends State<SnippetsPage> {
  List<Snippet>? _snippets;
  final _facts = <String, Future<_SnippetFacts>>{};
  // Snippets already risen in, so scrolling back doesn't replay it.
  final _shown = <String>{};

  // Where the section sits in its chart, as fractions of the chart's length,
  // and the patterns inside it.
  Future<_SnippetFacts> _patterns(Snippet s) async {
    final steps = await StepsLoader.load(s.song);
    final chart = steps?.chartFor(s.mode, s.difficulty);
    if (chart == null || chart.notes.isEmpty) return const _SnippetFacts();
    final selected = chart.notes
        .where((n) => n.beat >= s.startBeat && n.beat <= s.endBeat)
        .toList();
    if (selected.isEmpty) return const _SnippetFacts();
    final from = selected.first.second, to = selected.last.second;
    final end = chart.notes.last.second;
    final span = end <= 0 ? null : (from / end, to / end);
    final analysis =
        analyseChart(chart.notes, s.mode, weights: ParityProfile.active);
    final counts = <Pattern, int>{};
    for (final span in analysis.footwork.spans) {
      if (span.$2 >= from - 1e-6 && span.$3 <= to + 1e-6) {
        counts[span.$1] = (counts[span.$1] ?? 0) + 1;
      }
    }
    return _SnippetFacts(counts: counts, span: span);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snippets = await DatabaseProvider.getAllSnippets();
    _facts.clear();
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

  // Draws the snippet through its own preview, mounted out of sight just long
  // enough to render, and shares the image. [origin] places the share sheet's
  // popover on iPad and macOS.
  Future<void> _share(Snippet s, SongInfo song, Rect? origin) async {
    final ready = Completer<Future<void> Function(Rect? origin)>();
    // Built once: a fresh page per overlay rebuild would reload the steps and
    // mount a second preview.
    final page = Offstage(
        child: ChartPreviewPage.forChart(song, s.mode, s.difficulty, snippet: s,
            onShareReady: (share) {
      if (!ready.isCompleted) ready.complete(share);
    }));
    final entry = OverlayEntry(builder: (_) => page);
    Overlay.of(context).insert(entry);
    try {
      final share = await ready.future.timeout(const Duration(seconds: 10));
      await share(origin);
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't draw this snippet")));
      }
    } finally {
      entry.remove();
    }
  }

  Future<void> _menu(Snippet s, Rect? origin) async {
    final song = _songOf(s);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (song != null)
          ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Share image'),
              onTap: () => Navigator.pop(context, 'share')),
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
    if (action == 'share') await _share(s, song!, origin);
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
    final canShuffle = snippets?.any((s) => _songOf(s) != null) ?? false;
    return Scaffold(
      appBar: AppBar(
        title: PageTitle('Snippets',
            trailing: snippets == null || snippets.isEmpty
                ? null
                : Text('${snippets.length}',
                    style: FloorPop.readout(15,
                        color: FloorPop.of(context).haze))),
      ),
      body: Stack(children: [
        if (snippets == null)
          const Center(child: CircularProgressIndicator())
        else if (snippets.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Save a section of any chart to loop it here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ListView.builder(
            padding: clearOfTabBar(
                context, const EdgeInsets.fromLTRB(12, 4, 12, 88)),
            itemCount: snippets.length,
            itemBuilder: (context, i) => BeatIn(
                index: i,
                animate: _shown.add(snippets[i].id),
                child: _tile(snippets[i])),
          ),
        // Shuffle and Add float at the foot of the page, like the song
        // page's Preview chart and scan.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SafeArea(
              top: false,
              child: Row(children: [
                Expanded(
                  child: VoltButton(
                    color: FloorPop.grape,
                    riser: const Color(0xFF6A35C2),
                    onPressed: canShuffle
                        ? () async {
                            await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        SnippetFeedPage(snippets: snippets!)));
                            _load();
                          }
                        : null,
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.shuffle_rounded, size: 24),
                      SizedBox(width: 8),
                      Text('Shuffle'),
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: IconButton.filled(
                    tooltip: 'Add snippet',
                    style: IconButton.styleFrom(
                      backgroundColor: FloorPop.of(context).riser,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      elevation: 6,
                      shadowColor: Colors.black,
                      fixedSize: const Size(56, 56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _add,
                    icon: const Icon(Icons.add_rounded, size: 28),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _tile(Snippet s) {
    final song = _songOf(s);
    final pop = FloorPop.of(context);
    final difficulty = song == null
        ? null
        : (s.mode == Modes.singles ? song.singles : song.doubles)
            .toJson()[s.difficulty] as int?;
    final name = kInGameDifficultyNames[s.difficulty];
    final tint = difficultyColor(s.difficulty);
    final facts = _facts.putIfAbsent(
        '${s.id}:${s.startBeat}:${s.endBeat}', () => _patterns(s));
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
            color: pop.down, borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      // Out of the list at once: a dismissed Dismissible can't wait for the
      // reload to remove it.
      onDismissed: (_) {
        setState(() =>
            _snippets = _snippets?.where((item) => item.id != s.id).toList());
        _delete(s);
      },
      child: Builder(
        builder: (context) => Card(
          child: InkWell(
            onTap: song == null ? null : () => _open(s, song),
            onLongPress: () => _menu(s, _rectOf(context)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image(
                        width: 52,
                        height: 52,
                        image: ContentStore.image(
                            'assets/jackets-160/${s.song}.png'),
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.music_note, size: 40),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(song?.title ?? s.song,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 3),
                          Row(children: [
                            Text(s.mode == Modes.singles ? 'SP' : 'DP',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: pop.haze)),
                            const SizedBox(width: 6),
                            if (name != null &&
                                kInGameDifficultyColors.containsKey(name))
                              DifficultyLabel(
                                  difficulty: name,
                                  level: difficulty,
                                  height: 14)
                            else
                              Text(name ?? s.difficulty,
                                  style: TextStyle(
                                      color: tint,
                                      fontWeight: FontWeight.w700)),
                          ]),
                          if (s.label.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(s.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(fontSize: 13, color: pop.haze)),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'Snippet actions',
                        onPressed: () => _menu(s, _rectOf(context))),
                  ]),
                  FutureBuilder<_SnippetFacts>(
                    future: facts,
                    builder: (_, snapshot) {
                      final data = snapshot.data ?? const _SnippetFacts();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 10),
                            _SnippetTimeline(span: data.span, color: tint),
                            if (data.counts.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(spacing: 6, runSpacing: 6, children: [
                                for (final entry in data.counts.entries)
                                  Tooltip(
                                    message:
                                        '${kPatternLabels[entry.key]}: ${entry.value}',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: pop.riser,
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(kPatternIcons[entry.key],
                                                size: 14, color: pop.haze),
                                            const SizedBox(width: 4),
                                            Text('${entry.value}',
                                                style: FloorPop.readout(14)),
                                          ]),
                                    ),
                                  ),
                              ]),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect? _rectOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }
}

/// What a snippet's chart says about it: where the section falls, as
/// fractions of the chart, and the patterns inside it.
class _SnippetFacts {
  const _SnippetFacts({this.counts = const {}, this.span});

  final Map<Pattern, int> counts;
  final (double, double)? span;
}

/// The whole chart as a track, the snippet's section lit along it.
class _SnippetTimeline extends StatelessWidget {
  const _SnippetTimeline({required this.span, required this.color});

  final (double, double)? span;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final span = this.span;
    return LayoutBuilder(
      builder: (context, box) => Container(
        height: 8,
        decoration: BoxDecoration(
            color: FloorPop.of(context).riser,
            borderRadius: BorderRadius.circular(4)),
        alignment: Alignment.centerLeft,
        child: span == null
            ? null
            : Padding(
                padding: EdgeInsets.only(left: box.maxWidth * span.$1),
                child: Container(
                  width: math.max(4, box.maxWidth * (span.$2 - span.$1)),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: 0.6), blurRadius: 8)
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
