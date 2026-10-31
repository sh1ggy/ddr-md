/// Name: EditionGuidePage
/// Parent: EditionViewer, DevelopmentPage
/// Description: How a card is built, as one diagram: its four layers pulled
/// apart in depth, each beside what earns it, on the real renderer, in one
/// screen. Tap a card to stack the layers back
/// into the card.
library;

import 'dart:math' as math;

import 'edition_artwork_picker.dart' show editionArtwork;
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter/material.dart';
import 'edition_model.dart';
import 'edition_rules.dart';
import 'jacket_edition.dart';

const _plain = (
  borderId: 'gilded',
  effects: true,
  motion: false,
  modeStamp: false,
  gradeStamp: false,
  difficultyStamp: false,
  tierSuffix: false
);

class EditionGuidePage extends StatefulWidget {
  const EditionGuidePage(
      {super.key, this.artwork, this.facts, this.sheet = false});
  // The card to start from; a sample when absent.
  final Widget? artwork;
  final EditionFacts? facts;
  // Shown in a sheet, which has its own handle instead of a back button.
  final bool sheet;
  @override
  State<EditionGuidePage> createState() => _EditionGuidePageState();
}

class _EditionGuidePageState extends State<EditionGuidePage>
    with SingleTickerProviderStateMixin {
  late final Grade? _grade =
      widget.facts == null ? Grade.aaa : widget.facts!.grade;
  late final ClearLamp? _lamp =
      widget.facts == null ? ClearLamp.pfc : widget.facts!.lamp;
  late final String? _flare =
      widget.facts == null ? 'VIII' : widget.facts!.flare;
  late final bool _top = widget.facts?.hardestTop ?? false;
  late final _spread = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450), value: 1);

  @override
  void dispose() {
    _spread.dispose();
    super.dispose();
  }

  EditionFacts get _facts => EditionFacts(
      chart: widget.facts?.chart ??
          (song: 'guide', mode: 'singles', difficulty: 'hard'),
      level: widget.facts?.level ?? 14,
      tier: widget.facts?.tier,
      grade: _grade,
      lamp: _lamp,
      flare: _flare,
      precision: widget.facts?.precision,
      hardestTop: _top);

  Widget get _art => widget.artwork ?? editionArtwork(null);

  // What each layer shows now, and what earns it.
  List<(EditionLayer, String, String, String)> _labels() {
    final flare = resolveEdition(_facts, _plain).flareIndex;
    return [
      (
        EditionLayer.aura,
        'AURA',
        'Flare',
        switch (_flare) {
          null => 'None yet',
          'EX' => 'EX · rainbow stars and halo',
          final f when flare < 3 => '$f · sparks rise',
          final f when flare < 6 => '$f · motes circle',
          final f => '$f · stars twinkle',
        }
      ),
      (
        EditionLayer.frame,
        'FRAME',
        'Clear lamp',
        switch (_lamp) {
          _ when widget.facts?.precision?.award == PrecisionAward.sdp =>
            'SDP · pearly platinum',
          null || ClearLamp.failed || ClearLamp.clear => 'Dark stock',
          ClearLamp.mfc => 'MFC · rainbow, with a glint',
          ClearLamp.pfc => 'PFC · gold, catching the light',
          ClearLamp.gfc => 'GFC · silver, with a sheen',
          final l =>
            '${l == ClearLamp.life4 ? 'LIFE4' : l.name.toUpperCase()} · bronze',
        }
      ),
      (
        EditionLayer.finish,
        'FINISH',
        'Grade',
        _grade == Grade.aaa
            ? 'AAA · gold foil, as on its badge'
            : 'Below AAA · clean, the art left alone'
      ),
      (
        EditionLayer.art,
        'ART',
        'Top score, EX',
        [
          if (_top) 'Negative: your top score at your hardest level',
          if (_flare == 'EX') 'Polychrome: flare EX',
          if (!_top && _flare != 'EX') 'The jacket as it is',
        ].join(' · ')
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final diagram = SafeArea(
        top: false,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: GestureDetector(
                onTap: () =>
                    _spread.value > .5 ? _spread.reverse() : _spread.forward(),
                child: _Diagram(
                    facts: _facts,
                    art: _art,
                    labels: _labels(),
                    spread: _spread))));
    // In a sheet, as tall as the diagram and no taller.
    if (widget.sheet) return diagram;
    return Scaffold(appBar: AppBar(), body: diagram);
  }
}

/// The card's layers floating apart in an isometric view, art at the back,
/// each labelled on the right at its own height.
class _Diagram extends StatelessWidget {
  const _Diagram(
      {required this.facts,
      required this.art,
      required this.labels,
      required this.spread});
  final EditionFacts facts;
  final Widget art;
  final List<(EditionLayer, String, String, String)> labels;
  final Animation<double> spread;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        // As large as fits the space, so nothing scrolls.
        final steps = EditionLayer.values.length - 1;
        final side = math.min(math.min(constraints.maxWidth * .38, 200.0),
            constraints.maxHeight / (1.1 + .62 * steps));
        final gap = side * .62;
        final height = side * 1.1 + gap * steps;
        final theme = Theme.of(context);
        final cx = side * .78;
        return AnimatedBuilder(
            animation: spread,
            builder: (context, _) {
              final t = Curves.easeInOutCubic.transform(spread.value);
              // Art lowest; each layer above sits one gap higher, and all
              // meet in the middle when stacked.
              double centre(int i) =>
                  height - side * .55 - i * gap * t - (1 - t) * gap * 1.5;
              return SizedBox(
                  height: height,
                  child: Stack(clipBehavior: Clip.none, children: [
                    for (final layer in EditionLayer.values)
                      Positioned(
                          left: cx - side / 2,
                          top: centre(layer.index) - side / 2,
                          width: side,
                          height: side,
                          child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, .0008)
                                ..rotateX(.95)
                                ..rotateZ(-math.pi / 4),
                              child: Stack(
                                  fit: StackFit.expand,
                                  clipBehavior: Clip.none,
                                  children: [
                                    // The plane itself, so an empty layer
                                    // still shows where it sits.
                                    DecoratedBox(
                                        decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                                side * .065),
                                            border: Border.all(
                                                color: theme
                                                    .colorScheme.onSurface
                                                    .withValues(
                                                        alpha: .25 * t)))),
                                    JacketEdition(
                                        facts: facts,
                                        options: _plain,
                                        frozenLight: const Offset(.35, .3),
                                        layers: {layer},
                                        child: art),
                                  ]))),
                    for (final (layer, name, from, now) in labels)
                      Positioned(
                          left: cx + side * .78,
                          right: 0,
                          top: centre(layer.index) - 24,
                          child: Opacity(
                              opacity: t,
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text.rich(TextSpan(children: [
                                      TextSpan(
                                          text: name,
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w800)),
                                      TextSpan(
                                          text: '  ← $from',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant)),
                                    ])),
                                    const SizedBox(height: 2),
                                    Text(now,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall),
                                  ]))),
                  ]));
            });
      });
}
