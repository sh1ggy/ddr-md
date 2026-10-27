/// Name: HistoryPage
/// Parent: SongPage
/// Description: Tabbed page showing the current song's history:
/// a timeline of notes ([NotesTab], where new notes are also made)
/// and a timeline of saved scores ([ScoresTab]).
library;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/song/notes/note_page.dart';
import 'package:ddr_md/components/song/scores/score_page.dart';
import 'package:flutter/material.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, this.initialTab = notesTab});

  static const int notesTab = 0;
  static const int scoresTab = 1;

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DefaultTabController(
        length: 2,
        initialIndex: initialTab,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            centerTitle: true,
            title: const Text('History'),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(60),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: PillTabBar(tabs: [
                  _HistoryTab(Icons.edit_note, 'Notes'),
                  _HistoryTab(Icons.scoreboard_outlined, 'Scores'),
                ]),
              ),
            ),
          ),
          body: const TabBarView(
            children: [NotesTab(), ScoresTab()],
          ),
        ),
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      );
}
