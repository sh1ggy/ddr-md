/// Name: SettingsState
/// Description: Model for state relating to settings
library;

import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const String chosenReadSpeedKey = "chosenReadSpeed";

  // DDR CONSTANT modifier for the chart preview: the arrow display time in ms
  // (100–3000, 10ms steps; DDR default 1000). Only applied when [constantOnKey]
  // is set. Stored as an int of milliseconds.
  //
  // Written whenever the window is dialled, but NOT read back on open: the
  // preview re-derives it from [chosenReadSpeedKey] each time CONSTANT loads or
  // is switched on, since a window dialled against an older saved speed is
  // stale. Kept persisted so the last dialled value remains inspectable.
  static const String constantMsKey = "chartPreviewConstantMs";
  static const String constantOnKey = "chartPreviewConstantOn";

  // DDR TURN modifier for the chart preview: which column-permutation is applied
  // to the notes (receptors stay fixed). Stored as an int: 0 = OFF, 1 = MIRROR,
  // 2 = LEFT, 3 = RIGHT. See [_Turn] in chart_scroller.
  static const String chartPreviewTurnKey = "chartPreviewTurn";

  // Assist tick for the chart preview: play a short tick as each note row
  // crosses the receptor line during playback. Stored as 0/1.
  static const String assistTickOnKey = "chartPreviewAssistTickOn";

  // Measure rules for the chart preview: numbered lines every 4 beats. 0/1.
  static const String measureLinesOnKey = "chartPreviewMeasureLinesOn";

  // FOOT TRAILS for the chart preview: the lines joining each note to the
  // previous one struck by the same foot. Separate from the badges because the
  // trails read the chart's movement while the badges read its footing, and
  // either is useful without the other. 0/1.
  static const String footTrailsOnKey = "chartPreviewFootTrailsOn";

  // DANCING FEET for the chart preview: the mini pad under the field showing
  // where the parity solve stands the player at the playhead. 0/1.
  static const String dancingFeetOnKey = "chartPreviewDancingFeetOn";

  // Where the user has dragged the dancing-feet pad, as THOUSANDTHS of the
  // field's free space, PLUS ONE. Stored as a fraction rather than pixels so
  // the pad returns to the same spot on a different screen size or after a
  // rotation; biased by one so getInt's 0 default still reads as "never placed"
  // even for a pad parked hard in a corner. See [kDancingFeetUnset].
  static const String dancingFeetXKey = "chartPreviewDancingFeetX";
  static const String dancingFeetYKey = "chartPreviewDancingFeetY";

  // ARCADE NOTES for the chart preview: colour arrows with the cabinet's coarser
  // palette (4ths/8ths/16ths only, everything else green) instead of the full
  // ITG-style one. Stored as 0/1. See [QuantColors.arcadeMode].
  static const String arcadeQuantOnKey = "chartPreviewArcadeQuantOn";

  // ARCADE SYNC for the chart preview: master switch for the cabinet timing
  // simulation below. Off by default; while off both offsets are ignored and
  // their controls stay hidden. Stored as 0/1.
  static const String arcadeSyncOnKey = "chartPreviewArcadeSyncOn";

  // DDR TIMING offsets for the chart preview, mirroring the cabinet's two
  // timing dials. The cabinet uses DIFFERENT units and scales for these, so
  // they are stored differently — they are not interchangeable:
  //
  // VISUAL (表示タイミング) — the cabinet's -5.0..+5.0 dial in 0.1 steps. Stored
  //   as TENTHS of a dial unit, so the range is -50..+50. Moves the arrows'
  //   aiming position: PLUS corrects a FAST bias, MINUS corrects SLOW.
  // AUDIO (判定タイミング) — natively in MILLISECONDS on the cabinet, where
  //   players work in roughly ±10-20ms. Stored as whole ms, clamped to ±50.
  //
  // Both default to an unset 0, which is correctly neutral for each.
  static const String chartPreviewVisualOffsetKey = "chartPreviewVisualOffset";
  static const String chartPreviewAudioOffsetMsKey =
      "chartPreviewAudioOffsetMs";

  // The song sync bias the stored offsets above were dialled against, in
  // HUNDREDTHS of a millisecond. The offsets cancel a per-song bias, so they
  // only mean anything for the song they were computed for; keeping the bias
  // alongside them lets the preview tell "these are this song's offsets" from
  // "these are the last song's offsets" and re-seed in the latter case.
  static const String chartPreviewOffsetForBiasKey =
      "chartPreviewOffsetForBias";

  // DDR WORLD speed options for the chart preview, mirroring the cabinet's
  // SPEED TYPE: 0 = SCROLL SPEED ("real speed" — a target scroll rate,
  // 10–1000 in steps of 10, pinned to the chart's max BPM), 1 = HI-SPEED
  // (raw multiplier in hundredths, 25–800 = x0.25–x8.00, dialled in x0.05).
  // Each type keeps its own dialled value, like the cabinet's separate
  // option fields; tapping the speed pane switches type.
  static const String chartPreviewSpeedTypeKey = "chartPreviewSpeedType";
  static const String chartPreviewHispeedKey = "chartPreviewHispeed";
  static const String chartPreviewScrollSpeedKey = "chartPreviewScrollSpeed";
  // Order of the song page's reorderable sections, as section ids joined by
  // "," (see SongSection in song_page.dart). Applies to every song, not one.
  //
  // Stored as ids rather than indices so it survives sections being added or
  // removed from the app: on read, unknown ids are dropped and ids missing
  // from the saved list fall back to their default position, so a stale value
  // degrades instead of corrupting the layout. An empty value means "default
  // order".
  static const String songSectionOrderKey = "songSectionOrder";

  // How the songlist renders: 0 = the plain list, 1 = the arcade jacket grid.
  // Defaults to the list, since getInt falls back to 0 when unset.
  static const String songlistViewModeKey = "songlistViewMode";

  // The songlist's sort: a SortType index, and 1 for descending.
  static const String songlistSortKey = "songlistSort";
  static const String songlistSortDescKey = "songlistSortDesc";

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
