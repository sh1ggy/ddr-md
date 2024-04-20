/// Name: SettingsPage
/// Parent: Main
/// Description: Settings page for use with shared_preferences
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ddr_md/constants.dart' as constants;

class SettingsPage extends StatefulWidget {
  static const chosenReadSpeedSetting = "chosenReadSpeed";
  static const rivalCodeSpeedSetting = "rivalCode";
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _chosenReadSpeed = 0;
  String _rivalCode = constants.rivalCode;
  int _textReadSpeed = 0;
  String _textRivalCode = constants.rivalCode;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  /// Load the initial counter value from persistent storage on start,
  /// or fallback to constant BPM value if it doesn't exist.
  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _chosenReadSpeed = prefs.getInt(SettingsPage.chosenReadSpeedSetting) ??
          constants.chosenReadSpeed;
      _rivalCode = prefs.getString(SettingsPage.rivalCodeSpeedSetting) ??
          constants.rivalCode;
    });
  }

  /// After setting BPM preference, asynchronously save it
  /// to persistent storage.
  Future<void> _setReadSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      prefs.setInt(SettingsPage.chosenReadSpeedSetting, _textReadSpeed);
      _chosenReadSpeed = prefs.getInt(SettingsPage.chosenReadSpeedSetting) ??
          constants.chosenReadSpeed;
    });
  }

  /// After setting BPM preference, asynchronously save it
  /// to persistent storage.
  Future<void> _setRivalCode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      prefs.setString(SettingsPage.rivalCodeSpeedSetting, _textRivalCode);
      _rivalCode = prefs.getString(SettingsPage.rivalCodeSpeedSetting) ??
          constants.rivalCode;
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
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Card(
                    child: ListTile(
                      title: const Text('Preferred Read Speed'),
                      trailing: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Expanded(
                              child: TextField(
                                maxLength: 3,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                onChanged: (value) => {
                                  if (value != "")
                                    {_textReadSpeed = int.parse(value)}
                                },
                                decoration: InputDecoration(
                                  counterText: "",
                                  border: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  focusedErrorBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  hintText: _chosenReadSpeed.toString(),
                                ),
                              ),
                            ),
                            IconButton(
                                icon: const Icon(
                                  Icons.save,
                                ),
                                tooltip: "Save Read Speed",
                                onPressed: () {
                                  if (_textReadSpeed == 0) {
                                    _showToast(context, "Invalid Read Speed");
                                    return;
                                  }
                                  _setReadSpeed();
                                  _showToast(context,
                                      "Saved Read Speed to $_textReadSpeed");
                                }),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('DDR Rival Code'),
                      trailing: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Expanded(
                              child: TextField(
                                maxLength: 8,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                onChanged: (value) => {
                                  if (value != "") {_textRivalCode = value}
                                },
                                decoration: InputDecoration(
                                  counterText: "",
                                  border: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  focusedErrorBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  hintText: _rivalCode,
                                ),
                              ),
                            ),
                            IconButton(
                                icon: const Icon(
                                  Icons.save,
                                ),
                                tooltip: "Save DDR Rival Code",
                                onPressed: () {
                                  if (_textRivalCode == constants.rivalCode ||
                                      _textRivalCode.length <
                                          constants.rivalCodeLength) {
                                    _showToast(context, "Invalid Rival Code");
                                    return;
                                  }
                                  _setRivalCode();
                                  _showToast(context,
                                      "Saved Rival Code to $_textRivalCode");
                                }),
                          ],
                        ),
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

  void _showToast(BuildContext context, String message) {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
            label: 'DISMISS', onPressed: scaffold.hideCurrentSnackBar),
      ),
    );
  }
}
