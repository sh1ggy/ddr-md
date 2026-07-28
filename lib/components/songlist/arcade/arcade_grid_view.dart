/// Name: ArcadeGridView
/// Parent: DifficultyListPage
/// Description: The arcade song select — a three-wide grid of jackets split
/// into folder sections that fold away when their banner is tapped. A tap on a
/// jacket opens the song, matching the plain list view.
library;

import 'package:ddr_md/components/song/song_page.dart';
import 'package:ddr_md/components/songlist/arcade/arcade_grid_tile.dart';
import 'package:ddr_md/components/songlist/arcade/arcade_section_header.dart';
import 'package:ddr_md/components/songlist/arcade/song_sections.dart';
import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ArcadeGridView extends StatefulWidget {
  const ArcadeGridView({
    super.key,
    required this.songItems,
    required this.sortType,
    required this.mode,
    required this.leadingSlivers,
    required this.regenFavsCallback,
    this.descending = false,
  });

  final List<SongItem> songItems;
  final SortType sortType;
  final Modes mode;
  final bool descending;
  // The page's shared header slivers (search, filters, favourites, count) so
  // both views present the same controls.
  final List<Widget> leadingSlivers;
  final VoidCallback regenFavsCallback;

  @override
  State<ArcadeGridView> createState() => _ArcadeGridViewState();
}

class _ArcadeGridViewState extends State<ArcadeGridView> {
  late List<ArcadeSection> _sections;

  // Collapsed folders, held by label rather than index: a filter or sort change
  // rebuilds the section list, and labels survive that where positions don't.
  final Set<String> _collapsed = <String>{};

  void _toggleSection(String label) {
    setState(() {
      if (!_collapsed.remove(label)) _collapsed.add(label);
    });
  }

  @override
  void initState() {
    super.initState();
    _sections = groupSongItems(widget.songItems, widget.sortType, widget.mode,
        descending: widget.descending);
  }

  @override
  void didUpdateWidget(ArcadeGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.songItems != oldWidget.songItems ||
        widget.sortType != oldWidget.sortType ||
        widget.mode != oldWidget.mode ||
        widget.descending != oldWidget.descending) {
      _sections = groupSongItems(widget.songItems, widget.sortType, widget.mode,
          descending: widget.descending);
    }
  }

  // Opens the song, matching what a row in the plain list view does: a
  // chart-scoped tile opens the song page on the chart the tile stands for.
  Future<void> _open(SongItem item) async {
    final songState = context.read<SongState>();
    songState.setSongInfo(item.songInfo);
    songState.setChosenDifficulty(item.difficultyIndex ?? 0);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SongPage()),
    );
    widget.regenFavsCallback();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        ...widget.leadingSlivers,
        for (final section in _sections) ...<Widget>[
          SliverToBoxAdapter(
            child: ArcadeSectionHeader(
              label: section.label,
              count: section.items.length,
              collapsed: _collapsed.contains(section.label),
              onTap: () => _toggleSection(section.label),
            ),
          ),
          // Dropped rather than sized to zero, so the jackets stop being built.
          if (!_collapsed.contains(section.label))
            SliverPadding(
              // The banner is full-bleed and carries no margin of its own, so
              // the gap below it belongs to the grid.
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  // Square jacket plus the caption below it, so the artwork
                  // stays uncropped whatever the column width. The 16 is the
                  // grid's horizontal padding.
                  mainAxisExtent: (MediaQuery.sizeOf(context).width - 16) / 3 -
                      kArcadeTileGap * 2 +
                      kArcadeTitleHeight +
                      kArcadeCaptionHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final SongItem item = section.items[index];
                    return ArcadeGridTile(
                      item: item,
                      mode: widget.mode,
                      onTap: () => _open(item),
                    );
                  },
                  childCount: section.items.length,
                ),
              ),
            ),
        ],
        // Keeps the last row clear of the home indicator.
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
        ),
      ],
    );
  }
}
