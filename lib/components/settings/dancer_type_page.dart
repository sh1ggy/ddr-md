/// Name: DancerTypePage
/// Parent: SettingsPage
/// Description: Who the pad dancer is: the player's height, shoe size and how
/// they hold the bar.
library;

import 'package:ddr_md/components/settings/setting_card.dart';
import 'package:ddr_md/components/song/notes/dancing_feet.dart';
import 'package:ddr_md/components/song/notes/pad_dancer.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/material.dart';

class DancerTypePage extends StatefulWidget {
  const DancerTypePage({super.key});
  @override
  State<DancerTypePage> createState() => _DancerTypePageState();
}

class _DancerTypePageState extends State<DancerTypePage> {
  int _heightCm = Settings.getInt(Settings.heightKey);
  int _shoeTenths = Settings.getInt(Settings.shoeSizeKey);

  /// Men's US shoe size, which sizes the pad dancer's shoes against the panels.
  Future<void> _setShoeSize(String newValue) async {
    final size = double.tryParse(newValue.replaceAll(',', '.'));
    if (size == null) return;
    setState(() {
      Settings.setInt(Settings.shoeSizeKey, (size * 10).round().clamp(30, 180));
      _shoeTenths = Settings.getInt(Settings.shoeSizeKey);
    });
  }

  /// The player's height in cm, which sizes the pad dancer.
  Future<void> _setHeight(String newValue) async {
    setState(() {
      Settings.setInt(Settings.heightKey, int.parse(newValue).clamp(120, 220));
      _heightCm = Settings.getInt(Settings.heightKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          surfaceTintColor: Colors.black,
          shadowColor: Colors.black,
          elevation: 2,
          title: const Text(
            'Dancer Type',
            style: TextStyle(
              fontSize: 20,
              color: Colors.blueGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.blueGrey),
        ),
        body: ListView(
          padding: const EdgeInsets.all(8),
          children: [
            SettingCard<int>(
              setValue: _setHeight,
              chosenValue:
                  _heightCm == 0 ? (kDancerHeight * 100).round() : _heightCm,
              field: "Height (cm)",
              maxLength: 3,
            ),
            SettingCard<String>(
              setValue: _setShoeSize,
              chosenValue:
                  ((_shoeTenths == 0 ? kShoeSize * 10 : _shoeTenths) / 10)
                      .toString()
                      .replaceFirst(RegExp(r'\.0$'), ''),
              field: "Shoe Size (US)",
              maxLength: 4,
              digitsOnly: false,
            ),
            const BarGripCard(),
          ],
        ),
      ),
    );
  }
}

/// How the player holds the bar, for the pad dancer: overhand or underhand,
/// in the middle or out on the bends.
class BarGripCard extends StatefulWidget {
  const BarGripCard();

  @override
  State<BarGripCard> createState() => BarGripCardState();
}

class BarGripCardState extends State<BarGripCard> {
  BarGrip _grip = BarGrip.values[
      Settings.getInt(Settings.barGripKey).clamp(0, BarGrip.values.length - 1)];
  GripSpot _spot = GripSpot.values[Settings.getInt(Settings.gripSpotKey)
      .clamp(0, GripSpot.values.length - 1)];
  bool _bar = Settings.getInt(Settings.padDancerNoBarKey) == 0;

  @override
  Widget build(BuildContext context) {
    SegmentedButton<T> choice<T>(
            Map<T, String> labels, T selected, void Function(T) onChanged) =>
        SegmentedButton<T>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            for (final MapEntry(:key, :value) in labels.entries)
              ButtonSegment(value: key, label: Text(value)),
          ],
          selected: {selected},
          onSelectionChanged: (s) => onChanged(s.first),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            const Text("Bar Grip",
                style: TextStyle(fontWeight: FontWeight.w600)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text("Back bar"),
              subtitle: const Text("Off: the pad dancer has hands free"),
              value: _bar,
              onChanged: (v) {
                Settings.setInt(Settings.padDancerNoBarKey, v ? 0 : 1);
                setState(() => _bar = v);
              },
            ),
            choice(
                {BarGrip.overhand: "Overhand", BarGrip.underhand: "Underhand"},
                _grip, (g) {
              Settings.setInt(Settings.barGripKey, g.index);
              setState(() => _grip = g);
            }),
            choice({GripSpot.middle: "Middle", GripSpot.edges: "Edges"}, _spot,
                (g) {
              Settings.setInt(Settings.gripSpotKey, g.index);
              setState(() => _spot = g);
            }),
          ],
        ),
      ),
    );
  }
}
