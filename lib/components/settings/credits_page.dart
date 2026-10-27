/// Name: CreditsPage
/// Parent: AppSettingsPage
/// Description: Credits and inspiration: the apps, people and projects DDR MD
/// learnt from or builds on, and a word for arcades and Konami. Add credits to
/// [creditSections].
library;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Heading, then (name, what it gave DDR MD, link or null) per credit.
const creditSections = <(String, List<(String, String, String?)>)>[
  (
    'Inspiration',
    [
      (
        'GhostStep',
        'The DDR companion that set the bar; its song filters and read speed '
            'stepper shaped DDR MD\'s.',
        'https://ghoststep.app',
      ),
      (
        '3icecream',
        'Score tracking and difficulty tier lists, and the folder stats '
            'behind Statistics.',
        'https://3icecream.com',
      ),
      (
        'unfuzzed',
        'The original inspiration for reading scores off a photo of the '
            'result screen.',
        'https://unfuzzed.net',
      ),
      (
        'DDR BPM by Michael Xie',
        'Where DDR MD started: its song data pipeline grew out of DDR BPM\'s.',
        'https://github.com/xiexingwu/DDR-BPM-prep',
      ),
      (
        'Stepcharts by city41',
        'Showed charts could be drawn live, straight from the simfile.',
        'https://github.com/city41/stepcharts',
      ),
    ]
  ),
  (
    'Charts and Song Data',
    [
      (
        'Zenius-I-vanisher',
        'Charts, BPMs and song details, transcribed by its simfile authors.',
        'https://zenius-i-vanisher.com',
      ),
      (
        'RemyWiki',
        'The game\'s history, songs and groove radar.',
        'https://remywiki.com',
      ),
      (
        'groove-radar-calculator by sugoku',
        'Groove radar values worked out from the charts.',
        'https://github.com/sugoku/groove-radar-calculator',
      ),
      (
        '+9ms or Null? by Telperion',
        'The sync fingerprint behind each song\'s timing bias.',
        'https://github.com/telperion/nine-or-null',
      ),
      (
        'Chart data spreadsheet by Landpaddle',
        'Per-chart pattern study that pointed the way to the Patterns card.',
        'https://www.reddit.com/r/DanceDanceRevolution/comments/1latk94/spreadsheet_of_step_data_for_all_songs_and_charts/',
      ),
    ]
  ),
  (
    'Footwork and Form',
    [
      (
        'SMEditor by tillvit',
        'The foot parity solver and dancing bot that the footing and dancers '
            'are built on.',
        'https://github.com/tillvit/smeditor',
      ),
      (
        'ITGmania',
        'Step parity and tech counts, the reference for pattern counts.',
        'https://github.com/itgmania/itgmania',
      ),
      (
        'Simply Love',
        'Chart parsing that DDR MD\'s reading of simfiles leans on.',
        'https://github.com/Simply-Love/Simply-Love-SM5',
      ),
      (
        'Step annotations by mjvotaw',
        'A study of where feet land, step by step.',
        'https://mjvotaw.github.io/posts/step-annotation/step-annotations/',
      ),
      (
        'Form guide by chris4life',
        'The form the dancers\' feet follow.',
        'https://iamchris4life.com/formguide/',
      ),
    ]
  ),
  (
    'Under the Hood',
    [
      (
        'PaddleOCR',
        'The PP-OCR models that read the result screen.',
        'https://github.com/PaddlePaddle/PaddleOCR',
      ),
      ('OpenCV', 'Finding and straightening the screen.', 'https://opencv.org'),
      (
        'ONNX Runtime',
        'Running the OCR models on your phone.',
        'https://onnxruntime.ai',
      ),
      (
        'flutter_native_opencv by westracer',
        'The starting point for OpenCV in Flutter.',
        'https://github.com/westracer/flutter_native_opencv',
      ),
      (
        'Flutter',
        'And the open-source packages DDR MD is made of.',
        'https://flutter.dev',
      ),
    ]
  ),
];

/// Paragraphs under the credits: the case for the real thing.
const arcadeSupport = [
  'DanceDanceRevolution is made by Konami, and DDR MD is only a study '
      'companion to it. None of this exists without the cabinets.',
  'Play at your local arcade, on official machines, with your own '
      'e-amusement pass. Arcades keep their DDR cabinets because people put '
      'credits in them, so play often, bring friends, and let the staff know '
      'you want the machine to stay. Supporting the official game is what '
      'keeps new versions, songs and charts coming.',
];

class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(text, style: theme.textTheme.titleMedium),
        );
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: const GlassHeader(),
        title: const Text('Credits'),
      ),
      body: Builder(
          builder: (context) => ListView(
                padding: clearOfBars(
                    context, const EdgeInsets.fromLTRB(20, 8, 20, 32)),
                children: [
                  Text(
                      'Projects and people DDR MD learnt from or builds on. '
                      'Thank you all.',
                      style: theme.textTheme.bodySmall),
                  for (final (title, credits) in creditSections) ...[
                    heading(title),
                    for (final (name, note, url) in credits)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        title: Text(name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(note),
                        trailing: url == null
                            ? null
                            : const Icon(Icons.open_in_new, size: 18),
                        onTap: url == null
                            ? null
                            : () => launchUrl(Uri.parse(url),
                                mode: LaunchMode.externalApplication),
                      ),
                  ],
                  heading('Support Your Local Arcade'),
                  for (final p in arcadeSupport)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(p),
                    ),
                ],
              )),
    );
  }
}
