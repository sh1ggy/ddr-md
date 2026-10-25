/// Name: HistoryPage
/// Parent: SongPage
/// Description: Tabbed page showing the current song's history:
/// a timeline of notes ([NotesTab], where new notes are also made)
/// and a timeline of saved scores ([ScoresTab]).
library;

import 'package:ddr_md/components/song/notes/note_page.dart';
import 'package:ddr_md/components/song/scores/score_page.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, this.initialTab = notesTab});

  static const int notesTab = 0;
  static const int scoresTab = 1;

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
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
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                height: 44,
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: pop.riser, borderRadius: BorderRadius.circular(16)),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerHeight: 0,
                  indicator: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(12)),
                  labelColor: scheme.onPrimary,
                  unselectedLabelColor: pop.haze,
                  splashBorderRadius: BorderRadius.circular(12),
                  tabs: const [
                    _HistoryTab(Icons.edit_note, 'Notes'),
                    _HistoryTab(Icons.scoreboard_outlined, 'Scores'),
                  ],
                ),
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
