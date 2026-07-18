/// Name: SettingsPage
/// Parent: Main
/// Description: Settings page for use with shared_preferences
library;

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
          body: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                        // TODO: find a better way to set height, dynamic height shifts the layout
                        minHeight: MediaQuery.of(context).size.height * 0.74),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.start,
                                mainAxisSize: MainAxisSize.max,
                                children: [
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
                                  const _PlayStyleCard(),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                const Expanded(
                                    child: Padding(
                                  padding: EdgeInsets.only(left: 8.0),
                                  child: Text(constants.appVer),
                                )),
                                IconButton(
                                    onPressed: () =>
                                        _launchUrl(constants.github),
                                    icon: const FaIcon(FontAwesomeIcons.github,
                                        size: 20)),
                                IconButton(
                                    onPressed: () =>
                                        _launchUrl(constants.linkedin),
                                    icon: const FaIcon(
                                        FontAwesomeIcons.linkedin,
                                        size: 20)),
                                IconButton(
                                    onPressed: () =>
                                        _launchUrl(constants.paypalDono),
                                    icon: const FaIcon(FontAwesomeIcons.paypal,
                                        size: 20)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ));
            },
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

  Widget _styleOption(BuildContext context, Modes mode, String asset) {
    var songState = context.watch<SongState>();
    final selected = songState.modes == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        if (selected) return;
        songState.setMode(mode);
        showToast(context,
            "Set play style to ${mode == Modes.singles ? "singles" : "doubles"}");
      },
      child: Opacity(
        opacity: selected ? 1 : 0.3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Image.asset(asset, height: 15),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: const Text("Play Style",
            style: TextStyle(fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _styleOption(
                context, Modes.singles, 'assets/icons/style_single.png'),
            _styleOption(
                context, Modes.doubles, 'assets/icons/style_double.png'),
          ],
        ),
      ),
    );
  }
}
