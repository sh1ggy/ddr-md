/// Name: EditionGuidePage
/// Parent: EditionViewer, EditionLabPage, DevelopmentPage
/// Description: One page on what earns each layer of a jacket card, each
/// shown on the real renderer with every other layer left plain.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyNames;
import 'package:ddr_md/models/chart_bests.dart' show ChartBests;
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/version_group.dart';
import 'package:flutter/material.dart';
import 'edition_artwork_picker.dart';
import 'edition_model.dart';
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

EditionFacts _facts(
        {Grade? grade,
        ClearLamp? lamp,
        String? flare,
        FlareGroup? version,
        int? level,
        String difficulty = 'hard',
        bool levelTop = false}) =>
    EditionFacts(
        chart: (song: 'guide', mode: 'singles', difficulty: difficulty),
        level: level,
        version: version,
        grade: grade,
        lamp: lamp,
        flare: flare,
        levelTop: levelTop);

class EditionGuidePage extends StatelessWidget {
  const EditionGuidePage({super.key, this.artwork});
  final Widget? artwork;

  @override
  Widget build(BuildContext context) {
    final art = artwork ?? editionArtwork(null);
    Widget card(EditionFacts facts, Widget caption) => SizedBox(
        width: 76,
        child: Column(children: [
          SizedBox.square(
              dimension: 64,
              child: JacketEdition(
                  facts: facts,
                  options: _plain,
                  frozenLight: const Offset(.35, .3),
                  child: art)),
          const SizedBox(height: 6),
          SizedBox(height: 14, child: FittedBox(child: caption)),
        ]));
    Widget text(String s) => Text(s, style: const TextStyle(fontSize: 11));

    return Scaffold(
        appBar: AppBar(title: const Text('How cards work')),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              const Text(
                  'A chart\'s card is its jacket, finished by your best on it. '
                  'Each best owns one layer, so they stack instead of '
                  'fighting. Drag across a card to tilt it and move the light.'),
              _Section(
                  layer: 'Frame',
                  from: 'Clear lamp',
                  about: 'The border round the card. A spectrum inlay marks a '
                      'PFC with single-digit perfects.',
                  cards: [
                    card(_facts(lamp: ClearLamp.clear), text('CLEAR')),
                    card(_facts(lamp: ClearLamp.fc), text('FC · GFC · LIFE4')),
                    card(_facts(lamp: ClearLamp.pfc), text('PFC')),
                    card(_facts(lamp: ClearLamp.mfc), text('MFC')),
                  ]),
              _Section(
                  layer: 'Surface',
                  from: 'Grade',
                  about: 'The finish over the art, catching the light. A + '
                      'grade is stronger, a − weaker.',
                  cards: [
                    for (final (grade, name) in [
                      (Grade.d, 'Print'),
                      (Grade.c, 'Satin'),
                      (Grade.b, 'Metallic'),
                      (Grade.a, 'Holo'),
                      (Grade.aa, 'Textured'),
                      (Grade.aaa, 'Prism'),
                    ])
                      card(_facts(grade: grade, level: 14),
                          text('${grade.label} · $name')),
                  ]),
              _Section(
                  layer: 'Aura',
                  from: 'Flare',
                  about: 'A halo and particles round the edge, brighter up '
                      'each band: sparks rise at I–III, motes circle at '
                      'IV–VI, stars twinkle at VII–IX. EX goes rainbow and '
                      'turns the art polychrome.',
                  cards: [
                    for (final flare in ['I', 'IV', 'VII', 'IX', 'EX'])
                      card(_facts(flare: flare), text(flare)),
                  ]),
              _Section(
                  layer: 'Negative',
                  from: 'Top score of its level',
                  about: 'The art inverts on your highest score at a level, '
                      'once you\'ve scored ${ChartBests.levelTopMinCharts} '
                      'charts there. Beat it on another chart and the '
                      'negative moves.',
                  cards: [
                    card(_facts(grade: Grade.aa, levelTop: true),
                        text('Negative')),
                    card(_facts(grade: Grade.aa, flare: 'EX', levelTop: true),
                        text('+ EX')),
                  ]),
              _Section(
                  layer: 'Pattern',
                  from: 'Version and level',
                  about: 'Fine lines in the surface, from C up. The song\'s '
                      'version family sets their shape and the level sets '
                      'how dense they are.',
                  cards: [
                    for (final version in FlareGroup.values)
                      card(
                          _facts(grade: Grade.aaa, version: version, level: 14),
                          text(version.label)),
                    card(_facts(grade: Grade.aaa, level: 4), text('Level 4')),
                    card(_facts(grade: Grade.aaa, level: 18), text('Level 18')),
                  ]),
              _Section(
                  layer: 'Corners',
                  from: 'Difficulty',
                  about: 'Studs in the frame\'s corners, larger up the '
                      'difficulties.',
                  cards: [
                    for (final MapEntry(:key, :value)
                        in kInGameDifficultyNames.entries)
                      card(_facts(lamp: ClearLamp.pfc, difficulty: key),
                          DifficultyLabel(difficulty: value, height: 12)),
                  ]),
              const _Section(
                  layer: 'Stickers',
                  from: 'The chart',
                  about: 'Grade and flare stuck in the top corner; play style, '
                      'difficulty and level on a label along the bottom. '
                      'They sit on top of the finish, with their own shine '
                      'and shadow. Each can be hidden in Development.',
                  cards: []),
            ]));
  }
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.layer,
      required this.from,
      required this.about,
      required this.cards});
  final String layer, from, about;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: layer, style: theme.textTheme.titleMedium),
            TextSpan(
                text: '  ←  $from',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ])),
          const SizedBox(height: 4),
          Text(about),
          if (cards.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Room for each card's aura.
            Wrap(spacing: 8, runSpacing: 14, children: cards),
          ],
        ]));
  }
}
