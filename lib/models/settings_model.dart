/// Name: SettingsState
/// Description: Model for state relating to settings
library;

import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const String chosenReadSpeedKey = "chosenReadSpeed";

  // DDR CONSTANT modifier for the chart preview: the arrow display time in ms
  // (100–3000, 10ms steps; DDR default 1000). Only applied when [constantOnKey]
  // is set. Stored as an int of milliseconds.
  static const String constantMsKey = "chartPreviewConstantMs";
  static const String constantOnKey = "chartPreviewConstantOn";

  // DDR TURN modifier for the chart preview: which column-permutation is applied
  // to the notes (receptors stay fixed). Stored as an int: 0 = OFF, 1 = MIRROR,
  // 2 = LEFT, 3 = RIGHT. See [_Turn] in chart_scroller.
  static const String chartPreviewTurnKey = "chartPreviewTurn";

  // Assist tick for the chart preview: play a short tick as each note row
  // crosses the receptor line during playback. Stored as 0/1.
  static const String assistTickOnKey = "chartPreviewAssistTickOn";

  // DDR WORLD speed options for the chart preview, mirroring the cabinet's
  // SPEED TYPE: 0 = SCROLL SPEED ("real speed" — a target scroll rate,
  // 10–1000 in steps of 10, pinned to the chart's max BPM), 1 = HI-SPEED
  // (raw multiplier in hundredths, 25–800 = x0.25–x8.00, dialled in x0.05).
  // Each type keeps its own dialled value, like the cabinet's separate
  // option fields; tapping the speed pane switches type.
  static const String chartPreviewSpeedTypeKey = "chartPreviewSpeedType";
  static const String chartPreviewHispeedKey = "chartPreviewHispeed";
  static const String chartPreviewScrollSpeedKey = "chartPreviewScrollSpeed";
  static const String rivalCodeSpeedKey = "rivalCode";
  static const String detectionSideKey = "detectionSide";
  static const String usernameKey = "username";
  static const String playModeKey = "playMode";

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
