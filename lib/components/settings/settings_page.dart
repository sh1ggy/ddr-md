/// Name: SettingsPage
/// Parent: Main
/// Description: Settings page for use with shared_preferences
library;

import 'package:ddr_md/components/settings/setting_card.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:simple_icons/simple_icons.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _chosenReadSpeed = 0;
  String _rivalCode = constants.rivalCode;

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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
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
            body: Padding(
              padding: const EdgeInsets.all(8.0),
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
                  Expanded(
                    child: Align(
                      alignment: FractionalOffset.bottomCenter,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          const Expanded(child: Padding(
                            padding: EdgeInsets.only(left: 8.0),
                            child: Text(constants.appVer),
                          )),
                          IconButton(
                              onPressed: () => _launchUrl(constants.github),
                              icon: const Icon(Icons.bug_report, size: 25)),
                          IconButton(
                              onPressed: () => _launchUrl(constants.github),
                              icon: const Icon(SimpleIcons.github,
                                  color: SimpleIconColors.github, size: 20)),
                          IconButton(
                              onPressed: () => _launchUrl(constants.linkedin),
                              icon: const Icon(SimpleIcons.linkedin,
                                  color: SimpleIconColors.linkedin, size: 20)),
                          IconButton(
                              onPressed: () => _launchUrl(constants.paypalDono),
                              icon: const Icon(SimpleIcons.paypal,
                                  color: SimpleIconColors.paypal, size: 20)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    if (!await launchUrl(Uri.parse(urlString),
        mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch ${Uri.parse(urlString)}');
    }
  }
}
