/// Name: EamuseProfileCard
/// Parent: SettingsPage
/// Description: The player's e-amusement profile as the last sync read it:
/// dancer name, rival code (tap to copy), last play and total plays. Nothing
/// here is typed in; it fills in from a sync on Home.
library;

import 'dart:math';

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/settings/development_page.dart'
    show toggleDevelopmentTools;
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/settings/flare_class_style.dart';
import 'package:ddr_md/components/settings/score_overview_page.dart'
    show ScoreOverviewPage;
import 'package:ddr_md/grades.dart' show flareClassColor;
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/score_overview.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/eamuse.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The player's flare skill class, from whichever style is higher, or null
/// before any scores are synced.
Future<String?> _flareClass() async {
  final records =
      await DatabaseProvider.getScoreRecords(ScoreRecordSource.eamuse);
  if (records.isEmpty) return null;
  final total = [Modes.singles, Modes.doubles]
      .map((m) => flareSkill(records, Songs.list, m).total)
      .reduce(max);
  return flareClass(total).name;
}

/// Four quick taps on the flare rank unlock the development tools, or lock
/// them again.
class _FlareTaps extends StatefulWidget {
  const _FlareTaps({required this.child});
  final Widget child;

  @override
  State<_FlareTaps> createState() => _FlareTapsState();
}

class _FlareTapsState extends State<_FlareTaps> {
  int _taps = 0;
  DateTime _last = DateTime(0);

  void _tap() {
    final now = DateTime.now();
    _taps = now.difference(_last) < const Duration(milliseconds: 600)
        ? _taps + 1
        : 1;
    _last = now;
    if (_taps < 4) return;
    _taps = 0;
    toggleDevelopmentTools(context);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      behavior: HitTestBehavior.opaque, onTap: _tap, child: widget.child);
}

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
    final radius = BorderRadius.circular(26);

    return FutureBuilder<String?>(
      future: _flareClass(),
      builder: (context, snapshot) {
        final cls = snapshot.data;
        final tint = cls == null ? null : flareClassColor(cls);
        Widget stat(String label, String value) => Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: tint == null
                        ? pop.riser
                        : Color.lerp(pop.riser, tint, 0.18),
                    borderRadius: BorderRadius.circular(14)),
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
        return AnimatedContainer(
          duration: FloorPop.beat,
          curve: FloorPop.settle,
          margin: const EdgeInsets.symmetric(vertical: 5),
          decoration: cls == null
              ? BoxDecoration(
                  color: pop.stage,
                  borderRadius: radius,
                  border: Border.all(color: Colors.transparent, width: 1.5))
              : flareClassSurface(cls, base: pop.stage, radius: radius),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: pop.stripes(radius: radius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // Held at one size so nothing moves as the class loads.
                    SizedBox.square(
                      dimension: 64,
                      child: cls == null
                          ? Center(
                              child: Transform.rotate(
                                  angle: -0.07,
                                  child: const PadGlyph(size: 48, lit: true)))
                          : _FlareTaps(
                              child: Tooltip(
                                message: 'Flare rank',
                                child: FlareClassArt(cls, size: 64),
                              ),
                            ),
                    ),
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
                          SizedBox(
                              height: 18,
                              child: cls == null
                                  ? null
                                  : FlareClassName(cls, fontSize: 12)),
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
                const SizedBox(height: 8),
                Material(
                  color: tint == null
                      ? pop.riser
                      : Color.lerp(pop.riser, tint, 0.18),
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ScoreOverviewPage())),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      child: Row(children: [
                        const Icon(Icons.leaderboard_outlined, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Text('Statistics',
                                style: TextStyle(fontWeight: FontWeight.w600))),
                        Icon(Icons.chevron_right, color: muted),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
