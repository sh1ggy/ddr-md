/// Name: SnippetFeedPage
/// Parent: SnippetsPage
/// Description: Shuffled saved snippets, one active chart preview at a time.
/// Vertical swipes navigate; the next chart loads ahead of time.
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
  Future<SongSteps?>? _current;
  Future<SongSteps?>? _next;

  @override
  void initState() {
    super.initState();
    if (_pool.isEmpty) return;
    _appendRound();
    _current = StepsLoader.load(_history.first.song);
    _preload();
  }

  void _appendRound() {
    final round = [..._pool]..shuffle(_random);
    if (round.length > 1 &&
        _history.isNotEmpty &&
        round.first.id == _history.last.id) {
      final first = round.removeAt(0);
      round.add(first);
    }
    _history.addAll(round);
  }

  void _preload() {
    if (_index + 1 >= _history.length) _appendRound();
    final song = _history[_index + 1].song;
    _next = song == _history[_index].song ? _current : StepsLoader.load(song);
  }

  void _navigate(int direction) {
    if (direction < 0 && _index == 0) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (direction > 0) {
        _current = _next;
        _index++;
      } else {
        _index--;
        _current = StepsLoader.load(_history[_index].song);
      }
      _preload();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_pool.isEmpty) {
      return Scaffold(
          appBar: AppBar(title: const Text('Shuffle')),
          body: const Center(
              child: Text('No available charts in your snippets.')));
    }
    final snippet = _history[_index];
    final song = _songs[snippet.song]!;
    return KeyedSubtree(
      key: ValueKey(_index),
      child: ChartPreviewPage.forChart(
        song,
        snippet.mode,
        snippet.difficulty,
        snippet: snippet,
        stepsFuture: _current,
        autoPlay: true,
        onSwipeSnippet: _navigate,
        feedLabel: '${snippet.label.isEmpty ? sectionLabel((
                snippet.startBeat,
                snippet.endBeat
              ), song.timeSignatures) : snippet.label} · ${_index + 1} · Swipe up for next',
      ),
    );
  }
}
