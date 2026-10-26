/// Name: AppSettingsPage
/// Parent: SessionPage
/// Description: Settings, opened from Home's gear: check for song updates,
/// turn on cloud backup, read the privacy notes, and the app version with
/// links.
library;

import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/settings/privacy_page.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/cloud_sync.dart';
import 'package:ddr_md/models/content_updater.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
          ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 72),
            children: [
              const Card(child: _ContentTile()),
              const Card(child: _CloudTile()),
              Card(
                child: ListTile(
                  title: const Text("Privacy",
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PrivacyPage())),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
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
                          : () => _run(() => CloudSync.sync(force: true),
                              "Backed up"),
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
