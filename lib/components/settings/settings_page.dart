/// Name: SettingsPage
/// Parent: Main
/// Description: Profile tab: e-amusement profile, statistics and play
/// preferences, persisted with shared_preferences
library;

import 'package:ddr_md/components/settings/dancer_type_page.dart';
import 'package:ddr_md/components/settings/eamuse_profile_card.dart';
import 'package:ddr_md/components/settings/footing_style_page.dart';
import 'package:ddr_md/components/settings/score_overview_page.dart';
import 'package:ddr_md/components/settings/setting_card.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _chosenReadSpeed = 0;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  /// Load the initial counter value from persistent storage on start,
  /// or fallback to constant BPM value if it doesn't exist.
  Future<void> _loadPrefs() async {
    setState(() {
      _chosenReadSpeed = Settings.getInt(Settings.chosenReadSpeedKey);
    });
  }

  /// After setting BPM preference, asynchronously save it
  /// to persistent storage.
  Future<void> _setReadSpeed(String newValue) async {
    setState(() {
      Settings.setInt(Settings.chosenReadSpeedKey, int.parse(newValue));
      _chosenReadSpeed = Settings.getInt(Settings.chosenReadSpeedKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        top: false,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
            },
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              appBar: AppBar(
                surfaceTintColor: Colors.black,
                shadowColor: Colors.black,
                elevation: 2,
                title: const Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.blueGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                iconTheme: const IconThemeData(color: Colors.blueGrey),
              ),
              body: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      const _SectionHeader('Profile', Icons.person),
                      const EamuseProfileCard(),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.leaderboard_outlined),
                          title: const Text("Statistics",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ScoreOverviewPage())),
                        ),
                      ),
                      SettingCard<int>(
                        setValue: _setReadSpeed,
                        chosenValue: _chosenReadSpeed,
                        field: "Read Speed",
                        maxLength: 3,
                      ),
                      const _SectionHeader('Dancer', Icons.accessibility_new),
                      Card(
                        child: ListTile(
                          title: const Text("Dancer Type",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle:
                              const Text("Height, shoe size and bar grip"),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const DancerTypePage())),
                        ),
                      ),
                      const _SectionHeader('Play', Icons.directions_run),
                      const _PlayStyleCard(),
                      Card(
                        child: ListTile(
                          title: const Text("Footing Style",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FootingStyleSwitch(
                                  onChanged: () => setState(() {})),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const FootingStylePage()));
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ));
  }
}

/// Play style (singles/doubles) selector, persisted via [SongState.setMode].
class _PlayStyleCard extends StatelessWidget {
  const _PlayStyleCard();

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    ButtonSegment<Modes> segment(Modes mode, String asset) => ButtonSegment(
        value: mode,
        label: Opacity(
          opacity: songState.modes == mode ? 1 : 0.4,
          child: Image.asset(asset, height: 15),
        ));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<Modes>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            segment(Modes.singles, 'assets/icons/style_single.png'),
            segment(Modes.doubles, 'assets/icons/style_double.png'),
          ],
          selected: {songState.modes},
          onSelectionChanged: (s) {
            songState.setMode(s.first);
            showToast(context,
                "Set play style to ${s.first == Modes.singles ? "singles" : "doubles"}");
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: Colors.blueGrey,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
