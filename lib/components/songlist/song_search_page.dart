/// Name: SongSearchPage
/// Parent: DifficultyListPage
/// Description: Full-screen song search, ranked on every keystroke; only the
/// rows on screen are built.
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/songlist_item.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';

class SongSearchPage extends StatefulWidget {
  const SongSearchPage(
      {super.key, required this.controller, this.regenFavsCallback});

  // Owned by the song list, so the query is still there next time.
  final TextEditingController controller;
  final void Function()? regenFavsCallback;

  // Just enough of a fade not to pop, well inside the keyboard's slide.
  static Route<void> route(TextEditingController controller,
          {void Function()? regenFavsCallback}) =>
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 90),
        reverseTransitionDuration: const Duration(milliseconds: 70),
        pageBuilder: (context, animation, secondaryAnimation) => SongSearchPage(
            controller: controller, regenFavsCallback: regenFavsCallback),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
                opacity:
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                child: child),
      );

  @override
  State<SongSearchPage> createState() => _SongSearchPageState();
}

class _SongSearchPageState extends State<SongSearchPage> {
  // Below this similarity a result is considered noise and dropped, same
  // threshold spirit as the OCR title matcher.
  static const double _kMinSearchSimilarity = 0.3;

  List<SongMatch> _matches = const [];
  Map<String, int> _indexOf = const {};

  // One row per song, handed back unchanged while the song stays in the
  // results, so a keystroke only builds rows that weren't on screen.
  final Map<SongInfo, Widget> _rows = Map.identity();
  late final Widget? _prototype = Songs.list.isEmpty
      ? null
      : SongListItem(songInfo: Songs.list.first, isFav: false, isSearch: true);

  @override
  void initState() {
    super.initState();
    _search(widget.controller.text);
  }

  void _search(String text) {
    final matches = Songs.matchTitles(text,
        limit: Songs.list.length, minSimilarity: _kMinSearchSimilarity);
    setState(() {
      _matches = matches;
      _indexOf = {
        for (var i = 0; i < matches.length; i++) matches[i].song.name: i
      };
    });
  }

  Widget _row(SongInfo song) => _rows[song] ??= SongListItem(
        key: ValueKey(song.name),
        songInfo: song,
        isFav: false,
        isSearch: true,
        regenFavsCallback: widget.regenFavsCallback,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
            child: Row(children: [
              const BackButton(),
              const SizedBox(width: 8),
              Expanded(
                child: SearchBar(
                  controller: widget.controller,
                  autoFocus: true,
                  hintText: "Search song...",
                  constraints:
                      const BoxConstraints(minHeight: 48, maxHeight: 48),
                  padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 14)),
                  leading: const Icon(Icons.search, size: 20),
                  trailing: [
                    if (widget.controller.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Clear',
                        onPressed: () {
                          widget.controller.clear();
                          _search('');
                        },
                      ),
                  ],
                  onChanged: _search,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 8),
              prototypeItem: _prototype,
              itemCount: _matches.length,
              itemBuilder: (context, index) => _row(_matches[index].song),
              // Rows follow their song as the ranking reshuffles, keeping
              // loaded jackets and skipping the rebuild.
              findChildIndexCallback: (key) =>
                  _indexOf[(key as ValueKey<String>).value],
            ),
          ),
        ]),
      ),
    );
  }
}
