/// Name: EditionViewer
/// Parent: SongDetails
/// Description: Refreshes a frozen chart's facts on score changes, off-frame.
library;

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
  Object? heroTag,
  bool refreshScores = true,
}) async {
  final still = MediaQuery.disableAnimationsOf(context);
  await Navigator.of(context).push<void>(PageRouteBuilder(
      transitionDuration: still ? Duration.zero : FloorPop.beat,
      reverseTransitionDuration: still ? Duration.zero : FloorPop.eighth,
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, _, __) => _ViewerPage(
          facts: facts,
          options: options,
          artwork: artwork,
          heroTag: heroTag,
          refreshScores: refreshScores)));
}

class _ViewerPage extends StatefulWidget {
  const _ViewerPage(
      {required this.facts,
      required this.options,
      required this.artwork,
      required this.heroTag,
      required this.refreshScores});
  final EditionFacts facts;
  final EditionOptions options;
  final Widget artwork;
  final Object? heroTag;
  final bool refreshScores;
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
    final heroTag = widget.heroTag;
    return Stack(children: [
      GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: AspectRatio(
                          aspectRatio: 1,
                          child: heroTag == null
                              ? card
                              : Hero(
                                  tag: heroTag,
                                  transitionOnUserGestures: true,
                                  createRectTween: (begin, end) =>
                                      RectTween(begin: begin, end: end),
                                  // The plain jacket and the still card cross
                                  // over through the flight, so neither
                                  // flashes in at an end.
                                  flightShuttleBuilder: (_, animation, __, ___,
                                          ____) =>
                                      Stack(fit: StackFit.expand, children: [
                                        artwork,
                                        FadeTransition(
                                            opacity: animation,
                                            child: JacketEdition(
                                                facts: widget.facts,
                                                options: _options,
                                                frozenLight:
                                                    const Offset(.35, .3),
                                                child: artwork)),
                                      ]),
                                  child: card)))))),
      SafeArea(
          child: Align(
              alignment: Alignment.topRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
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
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                EditionGuidePage(artwork: artwork)))),
              ]))),
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
