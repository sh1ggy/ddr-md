/// Name: NavBar
/// Parent: Layout
/// Description: The tab bar: Songs, Snippets, Home, Scan, Profile on a
/// floating pill, Home raised in the middle and ringed while a session runs.
/// Above it on every tab while a session runs, the live dock carries the
/// running credit and starts the next one.
library;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/session/session_page.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
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
    (Icons.document_scanner_outlined, Icons.document_scanner, 'Scan'),
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
          margin: const EdgeInsets.fromLTRB(12, 18, 12, 4),
          height: 64,
          decoration: BoxDecoration(
            color: pop.stage,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: pop.line),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 30,
                  offset: Offset(0, 10))
            ],
          ),
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
                                curve: FloorPop.step,
                                width: 52,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: index == i
                                      ? scheme.onSurface
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(index == i ? selectedIcon : icon,
                                    color:
                                        index == i ? scheme.surface : pop.haze),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

/// Home, raised above the bar: Volt when it's the open tab, ringed in Volt
/// while a session runs so it reads from any tab.
class _HomeTab extends StatelessWidget {
  const _HomeTab(
      {required this.selected, required this.live, required this.onTap});

  final bool selected, live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Transform.translate(
      offset: const Offset(0, -16),
      child: Tooltip(
        message: live ? 'Home · session live' : 'Home',
        child: Semantics(
          label: live ? 'Home, session live' : 'Home',
          selected: selected,
          button: true,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: FloorPop.eighth,
              curve: FloorPop.step,
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: selected ? FloorPop.volt : pop.riser,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  if (selected)
                    const BoxShadow(
                        color: FloorPop.voltRiser, offset: Offset(0, 5)),
                  if (live) ...[
                    BoxShadow(color: scheme.surface, spreadRadius: 4),
                    BoxShadow(
                        color: FloorPop.volt.withValues(alpha: 0.6),
                        spreadRadius: 6),
                  ],
                ],
              ),
              child: Center(
                child: PadGlyph(
                  size: 26,
                  color: selected
                      ? FloorPop.onVolt
                      : live
                          ? FloorPop.volt
                          : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The running session over the tab bar: credit, side and cab, tap for
/// Home, and the next credit one tap away.
class LiveSessionDock extends StatelessWidget {
  const LiveSessionDock({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final credit = session.credit!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: FloorPop.volt,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 56,
          child: Row(children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    const LivePulse(color: FloorPop.onVolt),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'CREDIT ${credit.number} · ${sideLabel(credit.side)}',
                              style:
                                  FloorPop.readout(16, color: FloorPop.onVolt)),
                          Text(credit.cabinet.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: FloorPop.onVolt)),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: FloorPop.onVolt,
                  foregroundColor: FloorPop.volt,
                  minimumSize: const Size(44, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => showNewCreditSheet(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Credit'),
              ),
            ),
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
  late final _controller =
      AnimationController(vsync: this, duration: FloorPop.beat * 2)
        ..repeat(reverse: true);

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
