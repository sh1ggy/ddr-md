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
                                    icon: const Icon(SimpleIcons.github,
                                        size: 20)),
                                IconButton(
                                    onPressed: () =>
                                        _launchUrl(constants.linkedin),
                                    icon: const Icon(SimpleIcons.linkedin,
                                        size: 20)),
                                IconButton(
                                    onPressed: () =>
                                        _launchUrl(constants.paypalDono),
                                    icon: const Icon(SimpleIcons.paypal,
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
