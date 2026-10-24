/// Name: EamuseProfileCard
/// Parent: SettingsPage
/// Description: The player's e-amusement profile as the last sync read it:
/// dancer name, rival code (tap to copy), last play and total plays. Nothing
/// here is typed in; it fills in from a sync on Home.
library;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/eamuse.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/theme.dart';
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

    final pop = FloorPop.of(context);
    Widget stat(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                color: pop.riser, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: pop.label),
                const SizedBox(height: 2),
                Text(value,
                    style: FloorPop.readout(20,
                        color: theme.colorScheme.onSurface)),
              ],
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(18),
      decoration:
          pop.stripes(color: pop.stage, radius: BorderRadius.circular(26)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Transform.rotate(
                  angle: -0.07, child: const PadGlyph(size: 48, lit: true)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? 'DANCER' : name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FloorPop.display(24,
                            color: theme.colorScheme.onSurface)),
                    if (code.isNotEmpty)
                      Text(formatRivalCode(code),
                          style: FloorPop.readout(18, color: muted)
                              .copyWith(letterSpacing: 1.5)),
                  ],
                ),
              ),
              if (code.isNotEmpty)
                HeaderButton(
                  tooltip: "Copy rival code",
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      showToast(context, "Copied rival code");
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            stat("Last play",
                lastPlay.isEmpty ? '—' : formatAgo(eamuseTime(lastPlay))),
            const SizedBox(width: 8),
            stat("Plays", plays == 0 ? '—' : '$plays'),
          ]),
        ],
      ),
    );
  }
}
