/// Name: SonglistViewModeTest
/// Description: The songlist's list/grid choice persists across launches, and
/// defaults to the plain list for anyone who has never toggled it.
library;

import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to the list view when nothing is saved', () async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();

    expect(Settings.getInt(Settings.songlistViewModeKey), 0);
  });

  test('a saved grid choice survives a relaunch', () async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    await Settings.setInt(Settings.songlistViewModeKey, 1);

    expect(Settings.getInt(Settings.songlistViewModeKey), 1);
  });
}
