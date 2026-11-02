/// Name: EditionViewer
/// Parent: SongDetails
/// Description: Refreshes a frozen chart's facts on score changes, off-frame.
library;

import 'dart:math' as math;

import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'edition_model.dart';
import 'edition_chart_facts.dart';
import 'edition_guide.dart';
import 'edition_share.dart';
import 'jacket_edition.dart';

// Shared route dimensions and transition for song jackets and lab previews.
Future<void> showEditionViewer(
  BuildContext context, {
  required EditionFacts facts,
  required EditionOptions options,
  required Widget artwork,
  // Where the jacket sits on screen, for the card to grow out of it.
  Rect? from,
  bool refreshScores = true,
  VoidCallback? onBinder,
}) async {
  final still = MediaQuery.disableAnimationsOf(context);
  await Navigator.of(context).push<void>(PageRouteBuilder(
      transitionDuration: still ? Duration.zero : FloorPop.beat,
      reverseTransitionDuration: still ? Duration.zero : FloorPop.eighth,
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      // A card growing from its jacket carries its own transition.
      transitionsBuilder: (_, animation, __, child) => from == null
          ? FadeTransition(opacity: animation, child: child)
          : child,
      pageBuilder: (context, _, __) => _ViewerPage(
          facts: facts,
          options: options,
          artwork: artwork,
          from: from,
          refreshScores: refreshScores,
          onBinder: onBinder)));
}

class _ViewerPage extends StatefulWidget {
  const _ViewerPage(
      {required this.facts,
      required this.options,
      required this.artwork,
      required this.from,
      required this.refreshScores,
      required this.onBinder});
  final EditionFacts facts;
  final EditionOptions options;
  final Widget artwork;
  final Rect? from;
  final bool refreshScores;
  // Closes the viewer for the binder, at this card.
  final VoidCallback? onBinder;
  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  late var _options = widget.options;

  Future<void> _toggleEffects() async {
    final effects = !_options.effects;
    setState(() => _options = (
          borderId: _options.borderId,
          effects: effects,
          motion: _options.motion,
          modeStamp: _options.modeStamp,
          gradeStamp: _options.gradeStamp,
          difficultyStamp: _options.difficultyStamp,
          tierSuffix: _options.tierSuffix
        ));
    await Settings.setInt(Settings.jacketEffectsOffKey, effects ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final artwork = widget.artwork;
    final card = widget.refreshScores
        ? EditionViewer(facts: widget.facts, options: _options, child: artwork)
        : JacketEdition(facts: widget.facts, options: _options, child: artwork);
    final from = widget.from;
    final animation = ModalRoute.of(context)!.animation!;
    return Stack(children: [
      GestureDetector(
          onTap: () => Navigator.pop(context),
          child: from == null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: AspectRatio(aspectRatio: 1, child: card))))
              // One card throughout, flown from the jacket to the middle and
              // back, with nothing crossfaded or swapped on the way.
              : LayoutBuilder(builder: (context, box) {
                  final side = math.min(
                      640.0, math.min(box.maxWidth, box.maxHeight) - 48);
                  final to = Rect.fromCenter(
                      center: box.biggest.center(Offset.zero),
                      width: side,
                      height: side);
                  final curve = CurvedAnimation(
                      parent: animation, curve: Curves.fastOutSlowIn);
                  return AnimatedBuilder(
                      animation: curve,
                      builder: (context, child) => Stack(children: [
                            // Laid out once at full size and scaled, so the
                            // card's layers are drawn once, not per frame.
                            Positioned.fromRect(
                                rect: Rect.lerp(from, to, curve.value)!,
                                child: FittedBox(
                                    child: SizedBox.fromSize(
                                        size: to.size, child: child)))
                          ]),
                      child: card);
                })),
      FadeTransition(
        opacity: animation,
        child: SafeArea(
            child: Align(
                alignment: Alignment.topRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.onBinder case final onBinder?)
                    IconButton(
                        tooltip: 'Open in binder',
                        color: Colors.white,
                        icon: const Icon(Icons.collections_bookmark_outlined),
                        onPressed: () {
                          Navigator.pop(context);
                          onBinder();
                        }),
                  IconButton(
                      tooltip: 'Share card',
                      color: Colors.white,
                      icon: const Icon(Icons.ios_share),
                      onPressed: () => showEditionShare(context,
                          facts: widget.facts, artwork: artwork)),
                  IconButton(
                      tooltip: _options.effects
                          ? 'Turn card effects off'
                          : 'Turn card effects on',
                      color: Colors.white,
                      isSelected: _options.effects,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      selectedIcon: const Icon(Icons.auto_awesome),
                      onPressed: _toggleEffects),
                  IconButton(
                      tooltip: 'How cards work',
                      color: Colors.white,
                      icon: const Icon(Icons.info_outline),
                      // A sheet over the card, not a page: a page would take
                      // the card and the song page beneath out of view, and a
                      // hover tooltip moving with them breaks the frame.
                      onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          showDragHandle: true,
                          builder: (context) => EditionGuidePage(
                              artwork: artwork,
                              facts: widget.facts,
                              sheet: true))),
                ]))),
      )
    ]);
  }
}

class EditionViewer extends StatelessWidget {
  const EditionViewer(
      {super.key,
      required this.facts,
      required this.options,
      required this.child});
  final EditionFacts facts;
  final EditionOptions options;
  final Widget child;
  @override
  Widget build(BuildContext context) => EditionChartFacts(
      facts: facts,
      enabled: options.effects,
      builder: (_, current) =>
          JacketEdition(facts: current, options: options, child: child));
}
