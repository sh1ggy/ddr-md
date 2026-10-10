/// Name: PrivacyPage
/// Parent: SettingsPage
/// Description: Privacy notice: what DDR MD keeps on the device, what touches
/// the network, its permissions, and the fan-app notice. Keep it true to the
/// code, and update it (and [_updated]) when storage, permissions or network
/// use change.
library;

import 'package:ddr_md/constants.dart' as constants;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _updated = '10 October 2026';

/// Heading, then paragraphs; a paragraph starting "- " is a bullet.
const _sections = <(String, List<String>)>[
  (
    'In short',
    [
      "DDR MD keeps everything on your device. There's no account, no ads, "
          "no analytics and no tracking, and nothing you save, type or "
          "photograph is sent anywhere.",
    ]
  ),
  (
    'What stays on your device',
    [
      '- Scores you save, with the result-screen photo kept as proof',
      '- Notes and favourites',
      '- Feet you set by hand in the chart preview, and the footing style '
          'learned from them',
      '- Settings such as read speed, rival code, username and play style',
      'Result screens are read by OCR running on your phone. Camera frames '
          'and photos are never uploaded.',
    ]
  ),
  (
    'What uses the network',
    [
      '- Chart updates: when DDR MD opens, it checks for new songs and chart '
          'fixes and downloads them from a static file host (Cloudflare). '
          'These requests contain nothing about you or your data. As with '
          'any download, the host sees your IP address and the time of the '
          "request; I don't collect or look at these.",
      "- Links: the GitHub, LinkedIn and PayPal buttons open in your browser, "
          "where those sites' own privacy policies apply.",
    ]
  ),
  (
    'Permissions',
    [
      "- Camera: to read your score from a cabinet's result screen, only "
          'while the camera screen is open.',
      '- Photos: to read a result-screen screenshot you choose. DDR MD only '
          'sees the photo you pick.',
      '- Microphone: iOS lists this because of the audio engine behind the '
          'assist tick. DDR MD never records audio.',
    ]
  ),
  (
    'Deleting your data',
    [
      'Notes, favourites and hand-set feet can be removed in the app. '
          'Uninstalling DDR MD deletes everything it has stored, including '
          "scores and their photos. Nothing is kept anywhere else, so there's "
          'nothing for me to delete on your behalf.',
    ]
  ),
  (
    'Children',
    [
      "DDR MD isn't aimed at children under 13, and it doesn't collect "
          'personal information from anyone.',
    ]
  ),
  (
    'Game content',
    [
      "DDR MD is an independent fan-made app. It isn't affiliated with or "
          'endorsed by Konami. DanceDanceRevolution, song titles, jacket '
          'artwork and charts belong to their respective owners and are shown '
          'for reference. If you hold rights to content in the app and want it '
          'removed, get in touch below.',
    ]
  ),
  (
    'Changes',
    [
      'If this notice changes, the new version comes with an app update and '
          'a new date above.',
    ]
  ),
];

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy',
            style: TextStyle(
                fontSize: 20,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.blueGrey),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Last updated $_updated', style: theme.textTheme.bodySmall),
          for (final (heading, paragraphs) in _sections) ...[
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 6),
              child: Text(heading, style: theme.textTheme.titleMedium),
            ),
            for (final p in paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: p.startsWith('- ')
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(p.substring(2))),
                        ],
                      )
                    : Text(p),
              ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 6),
            child: Text('Contact', style: theme.textTheme.titleMedium),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => launchUrl(Uri.parse(constants.github),
                  mode: LaunchMode.externalApplication),
              child: const Text('github.com/sh1ggy'),
            ),
          ),
        ],
      ),
    );
  }
}
