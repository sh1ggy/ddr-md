/// Name: PrivacyPage
/// Parent: SettingsPage
/// Description: Privacy notice: what DDR MD keeps on the device, what touches
/// the network, its permissions, and where the song data comes from. Keep it
/// true to the code, and update it (and [privacyUpdated]) when storage,
/// permissions, network use or the content updates change.
library;

import 'package:ddr_md/constants.dart' as constants;
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const privacyUpdated = '26 October 2026';

/// Heading, then paragraphs; a paragraph starting "- " is a bullet. Also
/// published as the stores' privacy policy page by tool/content_manifest.dart.
const privacySections = <(String, List<String>)>[
  (
    'In Short',
    [
      "DDR MD keeps everything on your device. There's no sign-in, no ads, "
          'no analytics and no tracking, and nothing you save or type leaves '
          'your device unless you turn on Cloud Backup. Photos never do. It '
          'downloads song data, with nothing about you attached, and, only '
          'if you link your e-amusement account, your own scores from Konami.',
    ]
  ),
  (
    'What Stays on Your Device',
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
    'What Uses the Network',
    [
      '- Song updates: when DDR MD opens, and when you tap sync under '
          'Home → Settings → Song Updates, it checks DDR MD\'s update server (hosted '
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
          "password; the page keeps Konami's sign-in cookies on your device "
          'like a browser would, and DDR MD keeps any Konami renews during a '
          'sync. If the e-amusement session has lapsed, Sync reopens the '
          'sign-in page out of sight, which signs straight back in while '
          'Konami still remembers you. When you tap Sync, and only then, DDR MD '
          'uses that cookie to read your DDR WORLD play data from '
          "Konami's e-amusement site: your recent plays first, then only the "
          'charts you played since the last sync (or, the first time, every '
          'page of your play data), plus your profile page when you\'ve played, '
          'one page every few seconds. It saves your best score, rank, clear '
          'lamp, flare and max combo on each chart, each recent play\'s score, '
          'and your dancer name, rival code, play count and last play date on '
          'your device. Nothing is sent to DDR MD or anyone else, unless '
          'Cloud Backup (below) is on. Konami sees '
          "these requests as coming from your account, and Konami's own "
          'privacy policy applies to them.',
      '- Cloud Backup (optional, off until you turn it on under Home → '
          'Settings): copies your scores (saved and synced), sessions, '
          'venues, cabinets and their timing, notes, favourites, hand-set '
          'feet, snippets and settings to DDR MD\'s sync server (hosted on '
          'Cloudflare), and brings back what your other devices saved. It '
          'syncs when DDR MD opens, when you leave or return to it, and when '
          'you tap Back up now. Score photos, timing offsets, your Konami '
          'sign-in and e-amusement cookies are never sent. There is no '
          'account: your backup is filed under a random key DDR MD makes on '
          "first use, which only DDR MD on your devices knows. It's kept in "
          "your iPhone's Keychain (iCloud Keychain carries it to your other "
          'Apple devices) or in DDR MD\'s settings on Android (restored by '
          'Google backup on a new phone). The server stores a one-way '
          'fingerprint of that key, never the key itself, and your rival '
          'code if DDR MD has one, so a backup can be recognised as yours. '
          'Cloudflare sees your IP address and the time of each request. '
          "DDR MD doesn't log them; to stop one network flooding the "
          "server, it counts each day's backups against a one-way "
          'fingerprint of the IP address, cleared the next day.',
      "- Links: the GitHub, LinkedIn and PayPal buttons, and the links under "
          "Credits, open in your browser, where those sites' own privacy "
          'policies apply.',
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
    'Deleting Your Data',
    [
      'Notes, favourites and hand-set feet can be removed in the app. Sign '
          'out of e-amusement on Home deletes the Konami sign-in '
          'cookie. '
          'Uninstalling DDR MD deletes everything it has stored on your '
          'device, including scores and their photos. With Cloud Backup on, '
          'Delete cloud copy under Home → Settings removes everything on the '
          'sync server straight away and turns backup off. Deleting a row '
          'on your device deletes it from the backup at the next sync. '
          "Without Cloud Backup nothing is kept anywhere else, so there's "
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
    'Song Data',
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: const GlassHeader(),
        title: const Text('Privacy'),
      ),
      body: Builder(
          builder: (context) => ListView(
                padding: clearOfBars(
                    context, const EdgeInsets.fromLTRB(20, 8, 20, 32)),
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
              )),
    );
  }
}
