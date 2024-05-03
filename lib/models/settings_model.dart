/// Name: SettingsState
/// Description: Model for state relating to settings
library;

import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const String chosenReadSpeedKey = "chosenReadSpeed";
  static const String rivalCodeSpeedKey = "rivalCode";

  static Future<SharedPreferences> get _instance async =>
      _prefsInstance ??= await SharedPreferences.getInstance();
  static SharedPreferences? _prefsInstance;

  static Future<SharedPreferences?> init() async {
    _prefsInstance = await _instance;
    return _prefsInstance;
  }

  // Getter shared_preferences functions
  static int getInt(String key) {
    return _prefsInstance?.getInt(key) ?? 0;
  }

  static String getString(String key) {
    return _prefsInstance?.getString(key) ?? "";
  }

  // Setter shared_preferences functions
  static Future<Future<bool>?> setString(String key, String value) async {
    return _prefsInstance?.setString(key, value);
  }

  static Future<Future<bool>?> setInt(String key, int value) async {
    return _prefsInstance?.setInt(key, value);
  }
}
