/// Name: EditionViewer
/// Parent: SongDetails
/// Description: Refreshes a frozen chart's facts on score changes, off-frame.
library;

import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'edition_model.dart';
import 'edition_chart_facts.dart';
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
      pageBuilder: (context, _, __) {
        final card = refreshScores
            ? EditionViewer(facts: facts, options: options, child: artwork)
            : JacketEdition(facts: facts, options: options, child: artwork);
        return GestureDetector(
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
                                    flightShuttleBuilder:
                                        (_, __, ___, ____, _____) => artwork,
                                    child: card))))));
      }));
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
