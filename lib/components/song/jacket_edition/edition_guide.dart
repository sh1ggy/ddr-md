/// Name: EditionGuidePage
/// Parent: EditionViewer, DevelopmentPage
/// Description: How a card is built, as one diagram: its four layers pulled
/// apart in depth, each beside what earns it, on the real renderer. Change
/// the grade, lamp, flare and top score below and the layers change with
/// them; tap the diagram to stack them back into the card.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks;
import 'package:ddr_md/models/chart_bests.dart' show ChartBests;
import 'package:ddr_md/models/db_models.dart';
import 'package:flutter/material.dart';
import 'edition_artwork_picker.dart';
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
  late Grade? _grade = widget.facts == null ? Grade.aaa : widget.facts!.grade;
  late ClearLamp? _lamp =
      widget.facts == null ? ClearLamp.pfc : widget.facts!.lamp;
  late String? _flare = widget.facts == null ? 'VIII' : widget.facts!.flare;
  late bool _top = widget.facts?.levelTop ?? false;
  SongInfo? _song;
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
      grade: _grade,
      lamp: _lamp,
      flare: _flare,
      levelTop: _top);

  Widget get _art => _song != null || widget.artwork == null
      ? editionArtwork(_song)
      : widget.artwork!;

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
          null || ClearLamp.failed || ClearLamp.clear => 'Dark stock',
          ClearLamp.mfc => 'MFC · rainbow, with a glint',
          ClearLamp.pfc => 'PFC · gold, catching the light',
          final l =>
            '${l == ClearLamp.life4 ? 'LIFE4' : l.name.toUpperCase()} · silver',
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
          if (_top) 'Negative: your top score of its level',
          if (_flare == 'EX') 'Polychrome: flare EX',
          if (!_top && _flare != 'EX') 'The jacket as it is',
        ].join(' · ')
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget chips<T>(String label, List<(T, String)> values, T value,
            ValueChanged<T> onSelected) =>
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final (v, name) in values)
                      Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                              label: Text(name),
                              selected: v == value,
                              onSelected: (_) =>
                                  setState(() => onSelected(v)))),
                  ])),
            ]));

    return Scaffold(
        backgroundColor: widget.sheet ? Colors.transparent : null,
        appBar: AppBar(
            title: const Text('How cards work'),
            automaticallyImplyLeading: !widget.sheet,
            backgroundColor: widget.sheet ? Colors.transparent : null),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            children: [
              const Text('A card is its badges made physical. Each best owns '
                  'one layer, so they stack instead of fighting. Tap the '
                  'diagram to stack the layers into the card.'),
              const SizedBox(height: 8),
              GestureDetector(
                  onTap: () => _spread.value > .5
                      ? _spread.reverse()
                      : _spread.forward(),
                  child: _Diagram(
                      facts: _facts,
                      art: _art,
                      labels: _labels(),
                      spread: _spread)),
              chips<Grade?>(
                  'Grade',
                  [(null, '—'), (Grade.aa, 'AA'), (Grade.aaa, 'AAA')],
                  _grade,
                  (v) => _grade = v),
              chips<ClearLamp?>(
                  'Lamp',
                  [
                    (null, '—'),
                    (ClearLamp.clear, 'CLEAR'),
                    (ClearLamp.fc, 'FC'),
                    (ClearLamp.gfc, 'GFC'),
                    (ClearLamp.pfc, 'PFC'),
                    (ClearLamp.mfc, 'MFC'),
                  ],
                  _lamp,
                  (v) => _lamp = v),
              chips<String?>(
                  'Flare',
                  [(null, '—'), for (final r in kFlareRanks) (r, r)],
                  _flare,
                  (v) => _flare = v),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Top score of its level'),
                  subtitle: const Text('Once ${ChartBests.levelTopMinCharts} '
                      'charts there have a score'),
                  value: _top,
                  onChanged: (v) => setState(() => _top = v)),
              EditionArtworkPicker(
                  song: _song, onChanged: (s) => setState(() => _song = s)),
              const SizedBox(height: 12),
              Text(
                  'Your badges and score stay on the score card; the card '
                  'carries none of them. A shared card puts them back on, as '
                  'stickers and a band along its foot. The binder files '
                  'every card by level.',
                  style: theme.textTheme.bodySmall),
            ]));
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
        final side = math.min(constraints.maxWidth * .38, 200.0);
        final gap = side * .62;
        final height = side * 1.1 + gap * (EditionLayer.values.length - 1);
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
                                        maxLines: 2,
                                        style: theme.textTheme.bodySmall),
                                  ]))),
                  ]));
            });
      });
}
