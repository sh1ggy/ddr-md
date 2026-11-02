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
  final route = PageRouteBuilder<bool>(
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
          onBinder:
              onBinder == null ? null : () => Navigator.of(context).pop(true)));
  final openBinder = await Navigator.of(context).push<bool>(route);
  if (openBinder == true) {
    // Finish removing the card's overlay and hover regions before opening
    // another route with its own layout-driven cards.
    await route.completed;
    if (context.mounted) onBinder?.call();
  }
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
      Positioned.fill(
        child: GestureDetector(
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
                    final curve = animation
                        .drive(CurveTween(curve: Curves.fastOutSlowIn));
                    return AnimatedBuilder(
                        animation: curve,
                        builder: (context, child) =>
                            Stack(clipBehavior: Clip.none, children: [
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
      ),
      FadeTransition(
        opacity: animation,
        child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                    padding: const EdgeInsets.only(bottom: 48),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Material(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        elevation: 8,
                        shadowColor: Colors.black54,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant)),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Row(children: [
                            if (widget.onBinder case final onBinder?)
                              _ViewerAction(
                                  label: 'Binder',
                                  icon: Icons.collections_bookmark_outlined,
                                  onPressed: onBinder),
                            _ViewerAction(
                                label: 'Share',
                                icon: Icons.ios_share,
                                onPressed: () => showEditionShare(context,
                                    facts: widget.facts, artwork: artwork)),
                            _ViewerAction(
                                label: 'Effects',
                                toggled: _options.effects,
                                icon: _options.effects
                                    ? Icons.auto_awesome
                                    : Icons.auto_awesome_outlined,
                                onPressed: _toggleEffects),
                            _ViewerAction(
                                label: 'Guide',
                                icon: Icons.info_outline,
                                // A sheet over the card, not a page: a page would take
                                // the card and the song page beneath out of view, and a
                                // hover region moving with them breaks the frame.
                                onPressed: () => showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    showDragHandle: true,
                                    builder: (context) => EditionGuidePage(
                                        artwork: artwork,
                                        facts: widget.facts,
                                        sheet: true))),
                          ]),
                        ),
                      ),
                    )))),
      )
    ]);
  }
}

class _ViewerAction extends StatelessWidget {
  const _ViewerAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.toggled,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = toggled == true;
    return Expanded(
        child: Semantics(
            toggled: toggled,
            child: TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: active ? scheme.primary : scheme.onSurface,
                    backgroundColor:
                        active ? scheme.primary.withValues(alpha: .12) : null,
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18))),
                onPressed: onPressed,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 24),
                  const SizedBox(height: 6),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ]))));
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
