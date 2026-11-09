/// Name: NavBar
/// Parent: Layout
/// Description: The tab bar: Songs, Snippets, Home, Circle, Profile on a
/// floating pill, Home in Volt in the middle, ringed while a session runs.
/// Above it on every tab while a session runs, the live dock carries the
/// running credit, Song ID, scanning and the next credit.
library;

import 'dart:ui';

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/session/listen_sheet.dart';
import 'package:ddr_md/components/session/session_page.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

const kHomeTab = 2;

class FloorPopNavBar extends StatelessWidget {
  const FloorPopNavBar(
      {super.key, required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  static const _tabs = [
    (Icons.music_note_outlined, Icons.music_note, 'Songs'),
    (Icons.content_cut_outlined, Icons.content_cut, 'Snippets'),
    (null, null, 'Home'),
    (Icons.groups_outlined, Icons.groups, 'Circle'),
    (Icons.person_outline, Icons.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    final live = context.watch<SessionState>().active;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // On every tab, Home included: once the live card scrolls away the
      // session should still read at a glance.
      if (live) LiveSessionDock(onOpen: () => onSelected(kHomeTab)),
      SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          height: 64,
          // Frosted like the header and search bar, the page showing through.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: pop.stage.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: pop.line),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 30,
                  offset: Offset(0, 10))
            ],
          ),
          child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Row(children: [
                for (final (i, (icon, selectedIcon, label)) in _tabs.indexed)
                  Expanded(
                    child: Center(
                      child: i == kHomeTab
                          ? _HomeTab(
                              selected: index == i,
                              live: live,
                              onTap: () => onSelected(i))
                          : Tooltip(
                              message: label,
                              child: Semantics(
                                label: label,
                                selected: index == i,
                                button: true,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => onSelected(i),
                                  child: AnimatedContainer(
                                    duration: FloorPop.eighth,
                                    curve: FloorPop.settle,
                                    width: 52,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: index == i
                                          ? scheme.onSurface
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                        index == i ? selectedIcon : icon,
                                        color: index == i
                                            ? scheme.surface
                                            : pop.haze),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
              ])),
        ),
      ),
    ]);
  }
}

/// Home, always in Volt and sitting in the bar like the other tabs. Open, it
/// stands on its riser; while a session runs it's ringed in Volt so it reads
/// from any tab.
class _HomeTab extends StatelessWidget {
  const _HomeTab(
      {required this.selected, required this.live, required this.onTap});

  final bool selected, live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Tooltip(
      message: live ? 'Home · session live' : 'Home',
      child: Semantics(
        label: live ? 'Home, session live' : 'Home',
        selected: selected,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: FloorPop.eighth,
            curve: FloorPop.settle,
            width: 60,
            height: 44,
            margin: EdgeInsets.only(bottom: selected ? 4 : 0),
            decoration: BoxDecoration(
              color: FloorPop.volt,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: selected ? FloorPop.voltRiser : Colors.transparent,
                    offset: const Offset(0, 4)),
                if (live) ...[
                  BoxShadow(color: pop.stage, spreadRadius: 3),
                  BoxShadow(
                      color: FloorPop.volt.withValues(alpha: 0.6),
                      spreadRadius: 5),
                ],
              ],
            ),
            child:
                const Center(child: PadGlyph(size: 24, color: FloorPop.onVolt)),
          ),
        ),
      ),
    );
  }
}

/// The running session over the tab bar as one slim line: credit, side and
/// cab (tap for Home), then Song ID, a scan and the next credit.
class LiveSessionDock extends StatelessWidget {
  const LiveSessionDock({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final credit = session.credit!;
    Widget action(String tooltip, IconData icon, VoidCallback onPressed,
            {bool primary = false}) =>
        IconButton(
          tooltip: tooltip,
          style: IconButton.styleFrom(
            backgroundColor: primary ? FloorPop.onVolt : Colors.transparent,
            foregroundColor: primary ? FloorPop.volt : FloorPop.onVolt,
            fixedSize: const Size(36, 36),
            minimumSize: const Size(36, 36),
            padding: EdgeInsets.zero,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          iconSize: 20,
          onPressed: onPressed,
          icon: Icon(icon),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Material(
        color: FloorPop.volt,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 44,
          child: Row(children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    const LivePulse(color: FloorPop.onVolt),
                    const SizedBox(width: 8),
                    Text('C${credit.number} · ${sideLabel(credit.side)}',
                        style: FloorPop.readout(15, color: FloorPop.onVolt)),
                    const SizedBox(width: 8),
                    const Icon(Icons.videogame_asset_outlined,
                        size: 14, color: FloorPop.onVolt),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(credit.cabinet.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: FloorPop.onVolt)),
                    ),
                  ]),
                ),
              ),
            ),
            action('Name the song playing', Icons.hearing,
                () => showListenSheet(context)),
            const SizedBox(width: 2),
            action('Scan a score', Icons.document_scanner_outlined,
                () => context.push('/scan')),
            const SizedBox(width: 2),
            action('Credit ${credit.number + 1}', Icons.add,
                () => showNewCreditSheet(context),
                primary: true),
            const SizedBox(width: 4),
          ]),
        ),
      ),
    );
  }
}

/// The live dot, breathing on the beat.
class LivePulse extends StatefulWidget {
  const LivePulse({super.key, this.color = FloorPop.volt});

  final Color color;

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: FloorPop.beat * 2);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    return reduce
        ? dot
        : FadeTransition(
            opacity: Tween(begin: 1.0, end: 0.35).animate(_controller),
            child: dot);
  }
}
