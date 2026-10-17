/// Name: PrivacyPage
/// Parent: SettingsPage
/// Description: Privacy notice: what DDR MD keeps on the device, what touches
/// the network, its permissions, and where the song data comes from. Keep it
/// true to the code, and update it (and [privacyUpdated]) when storage,
/// permissions, network use or the content updates change.
library;

import 'package:ddr_md/constants.dart' as constants;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const privacyUpdated = '17 October 2026';

/// Heading, then paragraphs; a paragraph starting "- " is a bullet. Also
/// published as the stores' privacy policy page by tool/content_manifest.dart.
const privacySections = <(String, List<String>)>[
  (
    'In short',
    [
      "DDR MD keeps everything on your device. There's no DDR MD account, "
          "no ads, no analytics and no tracking, and nothing you save, type "
          "or photograph is sent anywhere. It downloads song data, with "
          'nothing about you attached, and, only if you link your '
          'e-amusement account, your own scores from Konami.',
    ]
  ),
  (
    'What stays on your device',
    [
      '- Scores you save, with the result-screen photo kept as proof',
      '- Scores synced from e-amusement, if you link your account',
      '- Notes and favourites',
      '- Feet you set by hand in the chart preview, and the footing style '
          'learned from them',
      '- Settings such as read speed, rival code, username and play style',
      'Result screens are read by OCR running on your phone. Camera frames '
          'and photos are never uploaded. On iPhone, saved score photos sit in '
          "DDR MD's folder in the Files app. Like any app's data, all of this "
          "is included in your device's own backups (iCloud or Google).",
    ]
  ),
  (
    'What uses the network',
    [
      '- Song updates: when DDR MD opens, and when you tap sync under '
          'Settings → Song Updates, it checks DDR MD\'s update server (hosted '
          'on Cloudflare) for new songs and chart fixes and downloads only '
          'what changed. These are plain file downloads with no account, '
          'device ID or anything you\'ve saved attached. As with any '
          'download, Cloudflare sees your IP address and the time of the '
          "request; DDR MD doesn't log or keep these.",
      '- Updates only ever contain song data (the song list, charts, jackets '
          'and pattern counts), never code, and each file is checked against '
          "its fingerprint before it's used.",
      '- e-amusement (optional): on Home you can sign '
          "in to your Konami account on Konami's own sign-in page, shown "
          'inside DDR MD. DDR MD never sees or stores your Konami ID or '
          "password; the page keeps Konami's sign-in cookie on your device "
          'like a browser would. When you tap Sync, and only then, DDR MD '
          'uses that cookie to read your DDR WORLD play data pages from '
          "Konami's e-amusement site, one page every few seconds, and saves "
          'your best score, rank, clear lamp and flare on each chart on your '
          'device. Nothing is sent to DDR MD or anyone else. Konami sees '
          "these requests as coming from your account, and Konami's own "
          'privacy policy applies to them.',
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
      'Notes, favourites and hand-set feet can be removed in the app. Sign '
          'out of e-amusement on Home deletes the Konami sign-in '
          'cookie. '
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
    'Song data',
    [
      'Charts and song details come from community-made simfiles, mostly '
          'from Zenius-I-vanisher, and all credit for them goes to their '
          "authors. They're fan transcriptions of the arcade charts and can "
          'have mistakes; fixes arrive through song updates. BPM behaviour, '
          'timing and pattern counts are worked out from those charts by '
          'DDR MD.',
      "DDR MD is an independent fan-made app. It isn't affiliated with or "
          'endorsed by Konami. DanceDanceRevolution, song titles, artists, '
          'jacket artwork and charts belong to their respective owners and '
          'are shown for reference.',
      'If you hold rights to content in the app and want it removed, get in '
          'touch below. Removed songs come off the update server, so they '
          'disappear from the app at its next update check, and from the app '
          'download with the next release.',
    ]
  ),
  (
    'Changes',
    [
      'If this notice changes, it gets a new date above and comes with an '
          'app update. Song updates never change it.',
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
          Text('Last updated $privacyUpdated',
              style: theme.textTheme.bodySmall),
          for (final (heading, paragraphs) in privacySections) ...[
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
