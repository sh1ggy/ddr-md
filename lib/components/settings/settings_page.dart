/// Name: SettingsPage
/// Parent: Main
/// Description: Settings page for use with shared_preferences
library;

import 'package:ddr_md/components/settings/footing_style_page.dart';
import 'package:ddr_md/components/settings/setting_card.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _chosenReadSpeed = 0;
  String _rivalCode = constants.rivalCode;
  String _username = constants.username;

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
      _rivalCode = Settings.getString(Settings.rivalCodeSpeedKey);
      _username = Settings.getString(Settings.usernameKey);
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

  /// After setting BPM preference, asynchronously save it
  /// to persistent storage.
  Future<void> _setRivalCode(String newValue) async {
    setState(() {
      Settings.setString(Settings.rivalCodeSpeedKey, newValue);
      _rivalCode = Settings.getString(Settings.rivalCodeSpeedKey);
    });
  }

  /// After setting the username, asynchronously save it to persistent
  /// storage. Compared against the OCR-detected player name when saving a
  /// score, to flag screenshots that may belong to someone else.
  Future<void> _setUsername(String newValue) async {
    setState(() {
      Settings.setString(Settings.usernameKey, newValue);
      _username = Settings.getString(Settings.usernameKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
              'Settings',
              style: TextStyle(
                fontSize: 20,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.blueGrey),
          ),
          // Settings scroll; the links stay pinned to the bottom.
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    const _SectionHeader('Profile'),
                    SettingCard<int>(
                      setValue: _setReadSpeed,
                      chosenValue: _chosenReadSpeed,
                      field: "Read Speed",
                      maxLength: 3,
                    ),
                    SettingCard<String>(
                      setValue: _setRivalCode,
                      chosenValue: _rivalCode,
                      field: "Rival Code",
                      maxLength: 8,
                    ),
                    SettingCard<String>(
                      setValue: _setUsername,
                      chosenValue: _username,
                      field: "Username",
                      maxLength: constants.usernameLength,
                      digitsOnly: false,
                    ),
                    const _SectionHeader('Play'),
                    const _PlayStyleCard(),
                    Card(
                      child: ListTile(
                        title: const Text("Footing Style",
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        trailing: FootingStyleSwitch(
                            onChanged: () => setState(() {})),
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const FootingStylePage()));
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Expanded(
                        child: Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Text(constants.appVer),
                    )),
                    IconButton(
                        onPressed: () => _launchUrl(constants.github),
                        icon: const FaIcon(FontAwesomeIcons.github, size: 20)),
                    IconButton(
                        onPressed: () => _launchUrl(constants.linkedin),
                        icon:
                            const FaIcon(FontAwesomeIcons.linkedin, size: 20)),
                    IconButton(
                        onPressed: () => _launchUrl(constants.paypalDono),
                        icon: const FaIcon(FontAwesomeIcons.paypal, size: 20)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Future<void> _launchUrl(String urlString) async {
    if (!await launchUrl(Uri.parse(urlString),
        mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch ${Uri.parse(urlString)}');
    }
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
      child: ListTile(
        title: const Text("Play Style",
            style: TextStyle(fontWeight: FontWeight.w600)),
        trailing: SegmentedButton<Modes>(
          showSelectedIcon: false,
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
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Text(label.toUpperCase(),
          style: const TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              color: Colors.blueGrey,
              fontWeight: FontWeight.w700)),
    );
  }
}
