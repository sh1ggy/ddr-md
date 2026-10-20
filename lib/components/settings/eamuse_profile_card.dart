/// Name: EamuseProfileCard
/// Parent: SettingsPage
/// Description: The player's e-amusement profile as the last sync read it:
/// dancer name, rival code (tap to copy), last play and total plays. Nothing
/// here is typed in; it fills in from a sync on Home.
library;

import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/eamuse.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class EamuseProfileCard extends StatelessWidget {
  const EamuseProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds when a sync ends, which is when the profile can change.
    context.select<EamuseSyncState, int>((s) => s.revision);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final name = Settings.getString(Settings.eamuseNameKey);
    final code = Settings.getString(Settings.rivalCodeSpeedKey);
    final plays = Settings.getInt(Settings.eamusePlayCountKey);
    // The profile's last play, or a newer one the recent plays page saw.
    final lastPlay = [
      Settings.getString(Settings.eamuseProfileLastPlayKey),
      Settings.getString(Settings.eamuseLastPlayKey),
    ].where((t) => t.isNotEmpty).fold('', (a, b) => b.compareTo(a) > 0 ? b : a);

    if (name.isEmpty && code.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.badge_outlined),
          title: Text("e-amusement profile",
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              "Sync e-amusement on Home to fill in your dancer name and rival code"),
        ),
      );
    }

    Widget stat(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1,
                      color: muted,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? 'Dancer' : name,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      if (code.isNotEmpty)
                        Text(formatRivalCode(code),
                            style: TextStyle(
                                fontSize: 18,
                                letterSpacing: 2,
                                color: muted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                    ],
                  ),
                ),
                if (code.isNotEmpty)
                  IconButton(
                    tooltip: "Copy rival code",
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) {
                        showToast(context, "Copied rival code");
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              stat("Last play",
                  lastPlay.isEmpty ? '—' : formatAgo(eamuseTime(lastPlay))),
              stat("Plays", plays == 0 ? '—' : '$plays'),
            ]),
          ],
        ),
      ),
    );
  }
}
