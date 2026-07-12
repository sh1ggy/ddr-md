/// Name: HistoryPage
/// Parent: SongPage
/// Description: Tabbed page showing the current song's history:
/// a timeline of notes ([NotesTab], where new notes are also made)
/// and a timeline of saved scores ([ScoresTab]).
library;

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
      child: DefaultTabController(
        length: 2,
        initialIndex: initialTab,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            surfaceTintColor: Colors.black,
            shadowColor: Colors.black,
            elevation: 2,
            centerTitle: true,
            title: const Text(
              'History',
              style: TextStyle(
                  fontSize: 20,
                  color: Colors.blueGrey,
                  fontWeight: FontWeight.w600),
            ),
            iconTheme: const IconThemeData(color: Colors.blueGrey),
            bottom: const TabBar(
              labelColor: Colors.blueGrey,
              indicatorColor: Colors.blueGrey,
              tabs: [
                Tab(icon: Icon(Icons.edit_note), text: 'Notes'),
                Tab(icon: Icon(Icons.scoreboard), text: 'Scores'),
              ],
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
