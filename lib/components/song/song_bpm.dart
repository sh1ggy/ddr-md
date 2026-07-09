/// Name: SongBpm
/// Parent: SongPage
/// Description: Widgets relating to the song's BPM & mods
library;

import 'package:ddr_md/components/song_json.dart';
import 'package:flutter/material.dart';
import 'package:ddr_md/constants.dart' as constants;
import 'package:flutter/services.dart';

class SongBpm extends StatefulWidget {
  const SongBpm(
      {super.key,
      required this.nearestModIndex,
      required this.isBpmChange,
      required this.chart});
  final int nearestModIndex;
  final bool isBpmChange;
  final Chart chart;

  @override
  State<SongBpm> createState() => _SongBpmState();
}

class _SongBpmState extends State<SongBpm> {
  late int _modIndex;

  @override
  void initState() {
    super.initState();
    _modIndex = widget.nearestModIndex;
  }

  @override
  void didUpdateWidget(SongBpm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nearestModIndex != widget.nearestModIndex) {
      _modIndex = widget.nearestModIndex;
    }
  }

  void _step(int delta) {
    final newIndex = _modIndex + delta;
    if (newIndex < 0 || newIndex >= constants.mods.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _modIndex = newIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
    final mod = constants.mods[_modIndex];
    final readSpeed = (mod * chart.dominantBpm).round();
    final readsAt = widget.isBpmChange
        ? "${(mod * chart.trueMin).round()}"
            "~$readSpeed"
            "~${(mod * chart.trueMax).round()}"
        : "$readSpeed";

    return Container(
      padding: const EdgeInsets.all(7.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton(
            onPressed: () => _step(-1),
            child: const Text("−10"),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: "×${_formatMod(mod)}",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const TextSpan(text: "  →  "),
                    TextSpan(
                      text: readsAt,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => _step(1),
            child: const Text("+10"),
          ),
        ],
      ),
    );
  }

  String _formatMod(double mod) =>
      mod == mod.roundToDouble() ? mod.toStringAsFixed(0) : mod.toString();
}
