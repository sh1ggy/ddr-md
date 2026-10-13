/// Name: SnippetFeedPage
/// Parent: SnippetsPage
/// Description: Shuffled saved snippets as pages swiped sideways, so a vertical
/// drag still scrubs the chart. Only the page on screen plays; its neighbours
/// are built and loaded ahead so they slide in ready. Song speed carries over.
library;

import 'dart:math';

import 'package:ddr_md/components/song/notes/chart_preview_page.dart';
import 'package:ddr_md/components/song/notes/section_bar.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The snippet to deal after [dealt]: never one of the last few (half the
/// pool), and another song than the last when there is one.
Snippet dealSnippet(List<Snippet> pool, List<Snippet> dealt, Random random) {
  final gap = pool.length < 2 ? 0 : max(1, pool.length ~/ 2);
  final recent = {for (final s in dealt.reversed.take(gap)) s.id};
  var candidates = [
    for (final s in pool)
      if (!recent.contains(s.id)) s
  ];
  final otherSong = [
    for (final s in candidates)
      if (s.song != dealt.lastOrNull?.song) s
  ];
  if (otherSong.isNotEmpty) candidates = otherSong;
  return candidates[random.nextInt(candidates.length)];
}

class SnippetFeedPage extends StatefulWidget {
  const SnippetFeedPage({super.key, required this.snippets});
  final List<Snippet> snippets;

  @override
  State<SnippetFeedPage> createState() => _SnippetFeedPageState();
}

class _SnippetFeedPageState extends State<SnippetFeedPage> {
  final _random = Random();
  final List<Snippet> _history = [];
  late final Map<String, SongInfo> _songs = {
    for (final song in Songs.list) song.name: song,
  };
  late final List<Snippet> _pool = widget.snippets.where((s) {
    final song = _songs[s.song];
    return song != null &&
        song.charts.isNotEmpty &&
        (s.mode == Modes.singles ? song.singles : song.doubles)
            .availableTypes
            .contains(s.difficulty);
  }).toList();
  int _index = 0;
  double _rate = 1.0;
  final _steps = <String, Future<SongSteps?>>{};

  Snippet _dealt(int i) {
    while (_history.length <= i) {
      _history.add(dealSnippet(_pool, _history, _random));
    }
    return _history[i];
  }

  Future<SongSteps?> _stepsOf(String song) =>
      _steps[song] ??= StepsLoader.load(song);

  void _onPage(int i) {
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    // Keep only the neighbours' charts in memory.
    final near = {for (int j = max(0, i - 1); j <= i + 1; j++) _dealt(j).song};
    _steps.removeWhere((song, _) => !near.contains(song));
    for (final song in near) {
      _stepsOf(song);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pool.isEmpty) {
      return Scaffold(
          appBar: AppBar(title: const Text('Shuffle')),
          body: const Center(
              child: Text('No available charts in your snippets.')));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        allowImplicitScrolling: true,
        onPageChanged: _onPage,
        itemBuilder: (context, i) {
          final snippet = _dealt(i);
          final song = _songs[snippet.song]!;
          final name = snippet.label.isEmpty
              ? sectionLabel(
                  (snippet.startBeat, snippet.endBeat), song.timeSignatures)
              : snippet.label;
          return ChartPreviewPage.forChart(
            song,
            snippet.mode,
            snippet.difficulty,
            key: ValueKey(i),
            snippet: snippet,
            stepsFuture: _stepsOf(snippet.song),
            feedActive: i == _index,
            playbackRate: _rate,
            onPlaybackRateChanged: (rate) => _rate = rate,
            feedLabel: '$name · ${i + 1} · Swipe for next',
          );
        },
      ),
    );
  }
}
