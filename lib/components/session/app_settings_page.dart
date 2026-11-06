/// Name: AppSettingsPage
/// Parent: SessionPage
/// Description: Settings, opened from Home's gear: check for song updates,
/// turn on cloud backup, choose when e-amusement syncs and whether it reads
/// doubles, sign out of it, read the privacy notes and credits, and the app
/// version with links.
library;

import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/settings/credits_page.dart';
import 'package:ddr_md/components/settings/development_page.dart';
import 'package:ddr_md/components/settings/privacy_page.dart';
import 'package:ddr_md/components/settings/timing_check/timing_check_page.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/cloud_sync.dart';
import 'package:ddr_md/models/content_updater.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Paragraphs at the bottom of Settings: the case for the real thing.
const arcadeSupport = [
  'DanceDanceRevolution is made by Konami, and DDR MD is only a study '
      'companion to it. None of this exists without the cabinets.',
  'Play at your local arcade, on official machines, with your own '
      'e-amusement pass. Arcades keep their DDR cabinets because people put '
      'credits in them, so play often, bring friends, and let the staff know '
      'you want the machine to stay. Supporting the official game is what '
      'keeps new versions, songs and charts coming.',
];

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});

  Future<void> _launchUrl(String urlString) async {
    if (!await launchUrl(Uri.parse(urlString),
        mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch ${Uri.parse(urlString)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return HomeSubpage(
      title: 'Settings',
      // The links float at the bottom, over anything scrolled under them.
      body: Stack(
        children: [
          Builder(
              builder: (context) => ListView(
                    padding: clearOfBars(
                        context, const EdgeInsets.fromLTRB(8, 8, 8, 72)),
                    children: [
                      const DevelopmentToolsTile(),
                      const Card(child: _ContentTile()),
                      const Card(child: _CloudTile()),
                      const Card(child: _EamuseTiles()),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.timer_outlined),
                          title: const Text('Timing Check',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle:
                              const Text('Compare judgement and visual timing'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                      builder: (_) => const TimingCheckPage())),
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.privacy_tip_outlined),
                          title: const Text("Privacy",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const PrivacyPage())),
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.favorite_outline),
                          title: const Text("Credits",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text("Inspiration and thanks"),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const CreditsPage())),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Support Your Local Arcade',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            for (final paragraph in arcadeSupport)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(paragraph,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ),
                          ],
                        ),
                      ),
                    ],
                  )),
          Positioned(
            left: 0,
            right: 0,
            // Clear of the floating tab bar the page runs under.
            bottom: 10 + MediaQuery.paddingOf(context).bottom,
            child: Center(
              child: Material(
                elevation: 3,
                shape: const StadiumBorder(),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHigh
                    .withValues(alpha: 0.85),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(constants.appVer,
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _launchUrl(constants.github),
                          icon:
                              const FaIcon(FontAwesomeIcons.github, size: 18)),
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _launchUrl(constants.linkedin),
                          icon: const FaIcon(FontAwesomeIcons.linkedin,
                              size: 18)),
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _launchUrl(constants.paypalDono),
                          icon:
                              const FaIcon(FontAwesomeIcons.paypal, size: 18)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// When e-amusement syncs on its own and what it reads, and signing out.
class _EamuseTiles extends StatefulWidget {
  const _EamuseTiles();

  @override
  State<_EamuseTiles> createState() => _EamuseTilesState();
}

class _EamuseTilesState extends State<_EamuseTiles> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<EamuseSyncState>();
    return Column(children: [
      SwitchListTile(
        secondary: const Icon(Icons.cloud_sync_outlined),
        title: const Text("Sync Each Credit",
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text(
            "Collect plays as each credit ends, not just at the session's end"),
        value: EamuseSyncState.syncEachCredit,
        onChanged: (on) async {
          await EamuseSyncState.setSyncEachCredit(on);
          if (mounted) setState(() {});
        },
      ),
      SwitchListTile(
        secondary: const Icon(Icons.people_outline),
        title: const Text("Sync Doubles",
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text("Include doubles in e-amusement syncs"),
        value: EamuseSyncState.syncDoubles,
        onChanged: (on) async {
          await EamuseSyncState.setSyncDoubles(on);
          if (mounted) setState(() {});
        },
      ),
      if (state.status != EamuseStatus.signedOut)
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text("Sign Out of e-amusement",
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text("Your synced scores stay on this device"),
          enabled: state.status != EamuseStatus.syncing,
          onTap: () => _confirmSignOut(state),
        ),
    ]);
  }

  Future<void> _confirmSignOut(EamuseSyncState state) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of e-amusement?'),
        content: const Text('Your synced scores stay on this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (yes == true) await state.signOut();
  }
}

/// Manual check for new songs and chart fixes, applied straight away like the
/// one at startup.
class _ContentTile extends StatefulWidget {
  const _ContentTile();

  @override
  State<_ContentTile> createState() => _ContentTileState();
}

class _ContentTileState extends State<_ContentTile> {
  bool _syncing = false;
  bool _checked = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    String message;
    try {
      final support = await getApplicationSupportDirectory();
      final applied = await ContentUpdater.update(support);
      _checked = true;
      message = applied
          ? "Added new songs and chart fixes"
          : "Songs and charts are up to date";
    } catch (_) {
      message = "Couldn't check for updates";
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final String subtitle;
    if (kContentUrl.isEmpty) {
      subtitle = "Updates are off in this build";
    } else if (_checked) {
      subtitle = "Up to date";
    } else {
      subtitle = "New songs and chart fixes";
    }
    return ListTile(
      leading: const Icon(Icons.library_music_outlined),
      title: const Text("Song Updates",
          style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: _syncing
          ? const SizedBox.square(
              dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(
              tooltip: "Check for updates",
              icon: const Icon(Icons.sync),
              onPressed: kContentUrl.isEmpty ? null : _sync,
            ),
    );
  }
}

/// Cloud backup on or off, with a manual sync and a way to delete what's on
/// the server.
class _CloudTile extends StatefulWidget {
  const _CloudTile();

  @override
  State<_CloudTile> createState() => _CloudTileState();
}

class _CloudTileState extends State<_CloudTile> {
  Future<void> _run(Future<void> Function() action, String done) async {
    String message;
    try {
      await action();
      message = done;
    } on SyncLimitException {
      message = "Backup is full for today; the rest goes up tomorrow";
    } catch (_) {
      message = "Couldn't reach the backup server; it'll try again later";
    }
    if (!mounted) return;
    setState(() {});
    showToast(context, message);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete cloud copy?'),
        content: const Text(
            "Removes your backed-up data from DDR MD's server and turns backup "
            "off. Everything on this device stays."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _run(CloudSync.deleteCloudCopy, "Cloud copy deleted");
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: CloudSync.running,
      builder: (context, running, _) {
        final on = CloudSync.enabled;
        final at =
            DateTime.tryParse(Settings.getString(Settings.cloudSyncedAtKey));
        final String subtitle;
        if (!CloudSync.available) {
          subtitle = "Backup is off in this build";
        } else if (running) {
          subtitle = "Backing up…";
        } else if (on) {
          subtitle =
              at == null ? "Not backed up yet" : "Backed up ${formatAgo(at)}";
        } else {
          subtitle = "Keep scores, sessions, notes and settings on all your "
              "devices";
        }
        return Column(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.cloud_outlined),
              title: const Text("Cloud Backup",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(subtitle),
              value: on,
              onChanged: !CloudSync.available || running
                  ? null
                  : (v) => _run(() => CloudSync.setEnabled(v),
                      v ? "Backed up" : "Backup turned off"),
            ),
            if (on)
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: running ? null : _delete,
                      child: const Text("Delete cloud copy")),
                  TextButton.icon(
                      onPressed: running
                          ? null
                          : () => _run(
                              () => CloudSync.sync(force: true), "Backed up"),
                      icon: const Icon(Icons.sync),
                      label: const Text("Back up now")),
                ],
              ),
          ],
        );
      },
    );
  }
}
