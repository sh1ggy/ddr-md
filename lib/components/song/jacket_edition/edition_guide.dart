/// Name: EditionGuidePage
/// Parent: EditionViewer, DevelopmentPage
/// Description: How a card is built, as one diagram: its four layers pulled
/// apart in depth, each beside what earns it, on the real renderer, in one
/// screen. Tap a card to stack the layers back
/// into the card.
library;

import 'dart:math' as math;

import 'edition_artwork_picker.dart';
import 'package:ddr_md/components/song_json.dart' show SongInfo;
import 'package:ddr_md/helpers.dart' show kFlareRanks, kInGameDifficultyNames;
import 'package:ddr_md/models/version_group.dart';
import '../difficulty_label.dart';
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
      {super.key,
      this.artwork,
      this.facts,
      this.sheet = false,
      this.editable = false});
  // The card to start from; a sample when absent.
  final Widget? artwork;
  final EditionFacts? facts;
  // Shown in a sheet, which has its own handle instead of a back button.
  final bool sheet;
  final bool editable;
  @override
  State<EditionGuidePage> createState() => _EditionGuidePageState();
}

class _EditionGuidePageState extends State<EditionGuidePage>
    with SingleTickerProviderStateMixin {
  late Grade? _grade = widget.facts == null ? Grade.aaa : widget.facts!.grade;
  late ClearLamp? _lamp =
      widget.facts == null ? ClearLamp.pfc : widget.facts!.lamp;
  late String? _flare = widget.facts == null ? 'VIII' : widget.facts!.flare;
  late bool _top = widget.facts?.hardestTop ?? false;
  SongInfo? _song;
  bool _pickedJacket = false;
  late PrecisionAward _precision =
      widget.facts?.precision?.award ?? PrecisionAward.unknown;
  late String _difficulty = widget.facts?.chart.difficulty ?? 'hard';
  late String _mode = widget.facts?.chart.mode ?? 'singles';
  late int? _tier = widget.facts?.tier;
  late FlareGroup? _version = widget.facts?.version;
  final _layers = {...EditionLayer.values};
  late final _spread = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450), value: 1);

  @override
  void dispose() {
    _spread.dispose();
    super.dispose();
  }

  EditionFacts get _facts => EditionFacts(
          chart: (
            song: _song?.name ?? widget.facts?.chart.song ?? 'guide',
            mode: _mode,
            difficulty: _difficulty
          ),
          level: widget.facts?.level ?? 14,
          tier: _tier,
          version: _version,
          grade: _grade,
          lamp: _lamp,
          flare: _flare,
          precision: _precision == PrecisionAward.unknown
              ? null
              : (
                  award: _precision,
                  sourceRowId: 'preview',
                  perfects: _precision == PrecisionAward.sdp ? 5 : null
                ),
          hardestTop: _top);

  Widget get _art => _pickedJacket
      ? editionArtwork(_song)
      : widget.artwork ?? editionArtwork(null);

  // What each layer shows now, and what earns it.
  List<(EditionLayer, String, String, String)> _labels() {
    return [
      (
        EditionLayer.aura,
        'AURA',
        'Flare',
        switch (_flare) {
          null => 'None yet',
          'EX' => 'EX · rainbow stars and halo',
          final f => '$f · stars twinkle',
        }
      ),
      (
        EditionLayer.frame,
        'FRAME',
        'Clear lamp',
        switch (resolveEdition(_facts).frame) {
          EditionFrame.stock => 'Dark stock',
          EditionFrame.bronze => 'LIFE4 / FC · bronze',
          EditionFrame.silver => 'GFC · silver, with a sheen',
          EditionFrame.gold => 'PFC · gold, catching the light',
          EditionFrame.platinum => 'SDP · pearly platinum',
          EditionFrame.rainbow => 'MFC · rainbow, with a glint',
        }
      ),
      (
        EditionLayer.finish,
        'FINISH',
        'Grade',
        switch (finishFor(_grade)) {
          EditionFinish.print => 'D / C · matte print',
          EditionFinish.satin => 'B · satin',
          EditionFinish.gloss => 'A · gloss',
          EditionFinish.metallic => 'AA · silver sheen',
          EditionFinish.prism => 'AAA · gold foil',
        }
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

  Widget _select<T>(String label, T value, List<(T, Widget)> choices,
          ValueChanged<T> changed) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: DropdownButtonFormField<T>(
              key: ValueKey((label, value)),
              initialValue: value,
              decoration: InputDecoration(labelText: label),
              isExpanded: true,
              items: [
                for (final (v, child) in choices)
                  DropdownMenuItem(value: v, child: child)
              ],
              onChanged: (v) => setState(() => changed(v as T))));

  Widget _controls() {
    final content =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EditionArtworkPicker(
          song: _song,
          onChanged: (song) => setState(() {
                _song = song;
                _pickedJacket = true;
              })),
      Wrap(spacing: 6, children: [
        for (final layer in EditionLayer.values)
          FilterChip(
              label: Text(layer.name),
              selected: _layers.contains(layer),
              onSelected: (on) => setState(
                  () => on ? _layers.add(layer) : _layers.remove(layer)))
      ]),
      _select<Grade?>(
          'Grade / surface',
          _grade,
          [
            (null, const Text('No grade')),
            for (final g in Grade.values) (g, Text(g.label))
          ],
          (v) => _grade = v),
      _select<ClearLamp?>(
          'Clear lamp / frame',
          _lamp,
          [
            (null, const Text('No lamp')),
            for (final l in ClearLamp.values) (l, Text(l.name.toUpperCase()))
          ],
          (v) => _lamp = v),
      _select<PrecisionAward>(
          'Precision / frame upgrade',
          _precision,
          [
            for (final p in PrecisionAward.values)
              (
                p,
                Text(
                    p == PrecisionAward.unknown ? 'None' : p.name.toUpperCase())
              )
          ],
          (v) => _precision = v),
      _select<String?>(
          'Flare / aura',
          _flare,
          [
            (null, const Text('None')),
            for (final f in kFlareRanks) (f, Text(f))
          ],
          (v) => _flare = v),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Negative jacket'),
          value: _top,
          onChanged: (v) => setState(() => _top = v)),
      _select<String>(
          'Chart style',
          _mode,
          [
            ('singles', const Text('Singles')),
            ('doubles', const Text('Doubles'))
          ],
          (v) => _mode = v),
      _select<String>(
          'Difficulty / corner shape',
          _difficulty,
          [
            for (final entry in kInGameDifficultyNames.entries)
              (entry.key, DifficultyLabel(difficulty: entry.value, height: 18))
          ],
          (v) => _difficulty = v),
      _select<FlareGroup?>(
          'Version / surface motif',
          _version,
          [
            (null, const Text('Neutral')),
            for (final v in FlareGroup.values) (v, Text(v.label))
          ],
          (v) => _version = v),
      _select<int?>(
          'Tier / engraving',
          _tier,
          [
            (null, const Text('Unknown')),
            for (var i = 0; i < 10; i++) (i, Text('$i'))
          ],
          (v) => _tier = v),
      const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Tap the diagram to stack or separate the layers. '
              'Preview only; your scores and settings are unchanged.')),
    ]);
    final padded = Padding(padding: const EdgeInsets.all(16), child: content);
    return SingleChildScrollView(child: padded);
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
                    spread: _spread,
                    layers: _layers))));
    // In a sheet, as tall as the diagram and no taller.
    if (widget.sheet) return diagram;
    if (!widget.editable) return Scaffold(appBar: AppBar(), body: diagram);
    return Scaffold(
        appBar: AppBar(title: const Text('Card effects lab')),
        body: LayoutBuilder(builder: (context, box) {
          final controls = _controls();
          if (box.maxWidth >= 850) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: diagram),
              SizedBox(width: 360, child: controls),
            ]);
          }
          return Column(children: [
            SizedBox(
                height: math.min(360, box.maxHeight * .46), child: diagram),
            Expanded(child: controls),
          ]);
        }));
  }
}

/// The card's layers floating apart in an isometric view, art at the back,
/// each labelled on the right at its own height.
class _Diagram extends StatelessWidget {
  const _Diagram(
      {required this.facts,
      required this.art,
      required this.labels,
      required this.spread,
      required this.layers});
  final EditionFacts facts;
  final Widget art;
  final List<(EditionLayer, String, String, String)> labels;
  final Animation<double> spread;
  final Set<EditionLayer> layers;

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
                    for (final layer
                        in EditionLayer.values.where(layers.contains))
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
                    for (final (layer, name, from, now)
                        in labels.where((l) => layers.contains(l.$1)))
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
