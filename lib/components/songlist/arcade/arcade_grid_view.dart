/// Name: ArcadeGridView
/// Parent: DifficultyListPage
/// Description: The arcade song select — a three-wide grid of jackets split
/// into folder sections, with the cabinet's two-step pick: the first tap
/// focuses a jacket and raises the info panel, the second (or SELECT) opens
/// the song.
library;

import 'package:ddr_md/components/song/song_page.dart';
import 'package:ddr_md/components/songlist/arcade/arcade_grid_tile.dart';
import 'package:ddr_md/components/songlist/arcade/arcade_info_panel.dart';
import 'package:ddr_md/components/songlist/arcade/arcade_section_header.dart';
import 'package:ddr_md/components/songlist/arcade/song_sections.dart';
import 'package:ddr_md/components/songlist/song_item.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class ArcadeGridView extends StatefulWidget {
  const ArcadeGridView({
    super.key,
    required this.songItems,
    required this.sortType,
    required this.mode,
    required this.leadingSlivers,
    required this.regenFavsCallback,
  });

  final List<SongItem> songItems;
  final SortType sortType;
  final Modes mode;
  // The page's shared header slivers (search, filters, favourites, count) so
  // both views present the same controls.
  final List<Widget> leadingSlivers;
  final VoidCallback regenFavsCallback;

  @override
  State<ArcadeGridView> createState() => _ArcadeGridViewState();
}

class _ArcadeGridViewState extends State<ArcadeGridView> {
  final ScrollController _scrollController = ScrollController();

  // Focus is held by song name rather than index so it survives the list being
  // refiltered or resorted underneath it.
  String? _focusedSongName;

  late List<ArcadeSection> _sections;

  @override
  void initState() {
    super.initState();
    _sections = groupSongItems(widget.songItems, widget.sortType, widget.mode);
  }

  @override
  void didUpdateWidget(ArcadeGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.songItems != oldWidget.songItems ||
        widget.sortType != oldWidget.sortType ||
        widget.mode != oldWidget.mode) {
      _sections = groupSongItems(widget.songItems, widget.sortType, widget.mode);
      // A filter, sort or mode change can drop the focused song entirely; let
      // the panel go rather than describing a song that is no longer shown.
      if (_focusedSongName != null && _focusedItem == null) {
        _focusedSongName = null;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // What the panel actually covers: its own height plus the home-indicator
  // inset it sits over. Both the trailing spacer and the auto-scroll work off
  // this so a focused tile always clears the panel on every device.
  double get _panelHeight =>
      kArcadeInfoPanelHeight + MediaQuery.paddingOf(context).bottom;

  SongItem? get _focusedItem {
    if (_focusedSongName == null) return null;
    for (final section in _sections) {
      for (final item in section.items) {
        if (item.songInfo.name == _focusedSongName) return item;
      }
    }
    return null;
  }

  void _onTileTap(SongItem item, BuildContext tileContext) {
    if (_focusedSongName == item.songInfo.name) {
      _confirm(item);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _focusedSongName = item.songInfo.name);
    // Focusing a song sets the difficulty the panel and song page both read,
    // honouring an active single-level filter the way the list rows do.
    context
        .read<SongState>()
        .setChosenDifficulty(item.defaultDifficultyIndex ?? 0);
    _ensureVisible(tileContext);
  }

  // Nudges the scroll view so the newly focused tile isn't left sitting behind
  // the info panel that is about to cover the bottom of the viewport.
  void _ensureVisible(BuildContext tileContext) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final RenderObject? tileBox = tileContext.findRenderObject();
      final RenderObject? viewportBox = context.findRenderObject();
      if (tileBox is! RenderBox || viewportBox is! RenderBox) return;
      if (!tileBox.attached || !viewportBox.attached) return;

      final double tileTop =
          tileBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
      final double tileBottom = tileTop + tileBox.size.height;
      final double visibleBottom = viewportBox.size.height - _panelHeight - 8;

      double delta = 0;
      if (tileBottom > visibleBottom) {
        delta = tileBottom - visibleBottom;
      } else if (tileTop < 0) {
        delta = tileTop;
      }
      if (delta == 0) return;

      final double target = (_scrollController.offset + delta)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _confirm(SongItem item) async {
    final songState = context.read<SongState>();
    songState.setSongInfo(item.songInfo);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SongPage()),
    );
    widget.regenFavsCallback();
  }

  @override
  Widget build(BuildContext context) {
    final SongItem? focused = _focusedItem;

    return Stack(
      children: <Widget>[
        CustomScrollView(
          controller: _scrollController,
          slivers: <Widget>[
            ...widget.leadingSlivers,
            for (final section in _sections) ...<Widget>[
              SliverToBoxAdapter(
                child: ArcadeSectionHeader(
                  label: section.label,
                  accent: section.accent,
                  count: section.items.length,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final SongItem item = section.items[index];
                      return Builder(
                        builder: (tileContext) => ArcadeGridTile(
                          item: item,
                          focused: _focusedSongName == item.songInfo.name,
                          onTap: () => _onTileTap(item, tileContext),
                        ),
                      );
                    },
                    childCount: section.items.length,
                  ),
                ),
              ),
            ],
            // Lets the last row scroll out from behind the info panel.
            SliverToBoxAdapter(
              child: SizedBox(height: _panelHeight + 8),
            ),
          ],
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            offset: focused == null ? const Offset(0, 1) : Offset.zero,
            child: focused == null
                ? const SizedBox(width: double.infinity)
                : ArcadeInfoPanel(
                    item: focused,
                    onConfirm: () => _confirm(focused),
                    onClose: () => setState(() => _focusedSongName = null),
                    onFavToggled: widget.regenFavsCallback,
                  ),
          ),
        ),
      ],
    );
  }
}
