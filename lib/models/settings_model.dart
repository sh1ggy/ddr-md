/// Name: SettingsState
/// Description: Model for state relating to settings
library;

import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  // Appearance follows the player; reduced motion remains a device preference.
  static const jacketBorderKey = 'jacketEditionBorder';
  static const jacketEffectsOffKey = 'jacketEditionEffectsOff';
  static const jacketMotionOffKey = 'jacketEditionMotionOff';
  static const jacketModeOffKey = 'jacketEditionModeOff';
  static const jacketGradeOffKey = 'jacketEditionGradeOff';
  static const jacketDifficultyOffKey = 'jacketEditionDifficultyOff';
  static const jacketTierOffKey = 'jacketEditionTierOff';

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

  // GUIDELINE for the chart preview, a [Guideline] index: 0 = OFF, 1 = CENTER,
  // 2 = BORDER.
  static const String guidelineKey = "chartPreviewGuideline";

  // FOOT TRAILS for the chart preview: the lines joining each note to the
  // previous one struck by the same foot. Separate from the badges because the
  // trails read the chart's movement while the badges read its footing, and
  // either is useful without the other. 0/1.
  static const String footTrailsOnKey = "chartPreviewFootTrailsOn";

  // DANCING FEET for the chart preview: the mini pad under the field showing
  // where the parity solve stands the player at the playhead. 0/1.
  static const String dancingFeetOnKey = "chartPreviewDancingFeetOn";

  // The 3D dancer behind the chart preview. 0/1.
  static const String padDancerOnKey = "chartPreviewPadDancerOn";

  // The pad dancer without the cabinet's back bar, hands free. 0/1.
  static const String padDancerNoBarKey = "chartPreviewPadDancerNoBar";

  // DancerView index: where the pad dancer's camera looks from.
  static const String dancerViewKey = "chartPreviewDancerView";

  // DancerForm index shared by the dancing feet and the pad dancer.
  static const String dancerFormKey = "chartPreviewDancerForm";

  // Profile: the player's height in cm for the pad dancer (0 = unset), and
  // how they hold the bar (BarGrip / GripSpot index).
  static const String heightKey = "profileHeightCm";
  static const String barGripKey = "profileBarGrip";
  static const String gripSpotKey = "profileGripSpot";
  // Men's US shoe size, tenths (95 = 9.5); 0 = unset.
  static const String shoeSizeKey = "profileShoeSizeUs10";

  // Where the user has dragged the dancing-feet pad, as THOUSANDTHS of the
  // field's free space, PLUS ONE. Stored as a fraction rather than pixels so
  // the pad returns to the same spot on a different screen size or after a
  // rotation; biased by one so getInt's 0 default still reads as "never placed"
  // even for a pad parked hard in a corner. See [kDancingFeetUnset].
  static const String dancingFeetXKey = "chartPreviewDancingFeetX";
  static const String dancingFeetYKey = "chartPreviewDancingFeetY";

  // QUANT COLORS for the chart preview: colour arrows with the full ITG-style
  // palette instead of the cabinet's coarser one (4ths/8ths/16ths only,
  // everything else green). Stored as 0/1. See [QuantColors.arcadeMode].
  static const String quantColorsOnKey = "chartPreviewQuantColorsOn";

  // BLINKING for the chart preview, stored inverted so the 0 default keeps the
  // cabinet's blinking arrow art on: 1 draws static sprites instead.
  static const String staticArrowsOnKey = "chartPreviewStaticArrowsOn";

  // QUANT FREEZES for the chart preview: draw freeze heads as quantised taps
  // instead of the freeze head art, so a freeze's timing reads like a tap's.
  // Stored as 0/1.
  static const String quantFreezeHeadsOnKey = "chartPreviewQuantFreezeHeadsOn";

  // ARCADE SYNC for the chart preview: master switch for the cabinet timing
  // simulation below. Off by default; while off both offsets are ignored and
  // their controls stay hidden. Stored as 0/1.
  static const String arcadeSyncOnKey = "chartPreviewArcadeSyncOn";

  // Display timing is ±5.0 in 0.1 steps (0.1 = 1ms); audio correction shifts
  // both judgement and display against the music. Store both delays as whole ms.
  // Keep the legacy visual key for migration from its tenths dial.
  static const String chartPreviewVisualOffsetKey = "chartPreviewVisualOffset";
  static const String chartPreviewVisualOffsetMsKey =
      "chartPreviewVisualOffsetMs";
  static const String chartPreviewTimingFormatKey = "chartPreviewTimingFormat";
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

  // 1 hides the songlist's grade/flare/lamp cards; unset shows them.
  static const String songlistHideStatsKey = "songlistHideStats";

  // The songlist's sort: a SortType index, and 1 for descending.
  static const String songlistSortKey = "songlistSort";
  static const String songlistSortDescKey = "songlistSortDesc";

  static const String rivalCodeSpeedKey = "rivalCode";
  static const String detectionSideKey = "detectionSide";
  static const String playModeKey = "playMode";
  static const String parityProfileKey = "parityProfile";
  static const String parityProfileOnKey = "parityProfileOn";

  // Id of the running play session ('' = none).
  static const String sessionIdKey = "sessionId";

  // When the last e-amusement sync finished (ISO-8601, '' = never), and the
  // newest play it saw on the recent plays page (e-amusement's own Japan-time
  // "YYYY-MM-DD HH:MM:SS", '' = walk every page next time).
  static const String eamuseSyncedAtKey = "eamuseSyncedAt";
  static const String eamuseLastPlayKey = "eamuseLastPlay";

  // An unfinished walk of every music_data page, as JSON: the style and page
  // it carries on from, and the newest play it covers ('' = none).
  static const String eamuseWalkKey = "eamuseWalk";

  // 1 = leave doubles charts out of e-amusement syncs.
  static const String eamuseSkipDoublesKey = "eamuseSkipDoubles";

  // The e-amusement player status, from the play data index: dancer name,
  // total plays and last play (Japan-time text, as above). The rival code is
  // kept under [rivalCodeSpeedKey].
  static const String eamuseNameKey = "eamuseName";
  static const String eamusePlayCountKey = "eamusePlayCount";
  static const String eamuseProfileLastPlayKey = "eamuseProfileLastPlay";

  // Cloud sync (see CloudSync): on/off (0/1), this device's copy of the
  // account key, and when the last sync finished (ISO-8601, '' = never).
  static const String cloudSyncOnKey = "cloudSyncOn";
  static const String cloudSyncKeyKey = "cloudSyncKey";
  static const String cloudSyncedAtKey = "cloudSyncedAt";

  // Settings that follow the player to their other devices. Left out: the
  // timing offsets (they depend on the device's own audio and display), the
  // running session, and e-amusement sync bookkeeping.
  static const syncedKeys = {
    jacketBorderKey,
    jacketEffectsOffKey,
    jacketModeOffKey,
    jacketGradeOffKey,
    jacketDifficultyOffKey,
    jacketTierOffKey,
    chosenReadSpeedKey,
    constantOnKey,
    chartPreviewTurnKey,
    assistTickOnKey,
    measureLinesOnKey,
    guidelineKey,
    footTrailsOnKey,
    dancingFeetOnKey,
    padDancerOnKey,
    padDancerNoBarKey,
    dancerViewKey,
    dancerFormKey,
    heightKey,
    barGripKey,
    gripSpotKey,
    shoeSizeKey,
    quantColorsOnKey,
    staticArrowsOnKey,
    quantFreezeHeadsOnKey,
    arcadeSyncOnKey,
    chartPreviewSpeedTypeKey,
    chartPreviewHispeedKey,
    chartPreviewScrollSpeedKey,
    songSectionOrderKey,
    songlistViewModeKey,
    songlistSortKey,
    songlistSortDescKey,
    rivalCodeSpeedKey,
    detectionSideKey,
    playModeKey,
    parityProfileKey,
    parityProfileOnKey,
    eamuseNameKey,
    eamusePlayCountKey,
    eamuseProfileLastPlayKey,
  };

  static Map<String, Object> syncedPrefs() => {
        for (final k in syncedKeys)
          if (_prefsInstance?.get(k) case final Object v) k: v,
      };

  static Future<void> applySyncedPrefs(Map<String, Object?> prefs) async {
    for (final MapEntry(:key, :value) in prefs.entries) {
      if (!syncedKeys.contains(key)) continue;
      if (value is int) await _prefsInstance?.setInt(key, value);
      if (value is String) await _prefsInstance?.setString(key, value);
    }
  }

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
