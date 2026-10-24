/// Name: SongBpm
/// Parent: SongPage
/// Description: Widgets relating to the song's BPM & mods
library;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/song/notes/chart_chrome.dart';
import 'package:ddr_md/components/song/notes/constant_speed.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/theme.dart';
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

  // Matches the chart preview's read-speed dial, so both controls turn at the
  // same rate under the finger.
  static const double _pxPerStep = 7;
  double _dragAccum = 0;

  void _step(int delta) {
    final newIndex = _modIndex + delta;
    if (newIndex < 0 || newIndex >= constants.mods.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _modIndex = newIndex;
    });
  }

  void _reset() {
    if (_modIndex == widget.nearestModIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _modIndex = widget.nearestModIndex;
      _dragAccum = 0;
    });
  }

  void _onDrag(double dx) {
    _dragAccum += dx;
    while (_dragAccum.abs() >= _pxPerStep) {
      final dir = _dragAccum > 0 ? 1 : -1;
      _dragAccum -= dir * _pxPerStep;
      final before = _modIndex;
      _step(dir);
      if (_modIndex == before) {
        _dragAccum = 0; // pinned at an end of the ladder
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
    final scheme = Theme.of(context).colorScheme;
    final mod = constants.mods[_modIndex];
    final readSpeed = (mod * chart.dominantBpm).round();
    final constant = widget.isBpmChange
        ? constantForReadSpeed(Settings.getInt(Settings.chosenReadSpeedKey))
        : null;
    final pop = FloorPop.of(context);
    String n(int v) => v.toString();

    // Framed like the chart preview's speed dial ([SpeedPane]), so both places
    // you pick a mod handle the same way: tap resets, drag turns. One read
    // speed headlines it; a BPM-changing chart adds its slowest and fastest
    // reads, and the CONSTANT equivalent, on one quiet line under it.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ControlPane(
        onTap: _reset,
        onDragUpdate: (d) => _onDrag(d.primaryDelta ?? 0),
        borderRadius: 0,
        fill: Colors.transparent,
        // Minimum, not fixed: this pane sits in a scrolling page and must grow
        // rather than overflow at large text scales.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: IntrinsicHeight(
            child: Row(
              children: [
                EdgeButton(
                  label: "−10",
                  enabled: _modIndex > 0,
                  onTap: () => _step(-1),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Lean(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: FloorPop.volt,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Upright(
                                    child: Text("×${_formatMod(mod)}",
                                        semanticsLabel:
                                            'Speed mod ${_formatMod(mod)}',
                                        style: FloorPop.readout(22,
                                            color: FloorPop.onVolt)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text('reads ',
                                  style:
                                      TextStyle(fontSize: 13, color: pop.haze)),
                              Text(n(readSpeed),
                                  style: FloorPop.readout(24,
                                      color: scheme.onSurface)),
                            ],
                          ),
                        ),
                        if (widget.isBpmChange || constant != null) ...[
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              [
                                if (widget.isBpmChange)
                                  '${n((mod * chart.trueMin).round())} slowest'
                                      ' · ${n((mod * chart.trueMax).round())} fastest',
                                if (constant != null)
                                  '${constant.ms} ms ≈ C${constant.c}',
                              ].join('  ·  '),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: pop.haze,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                EdgeButton(
                  label: "+10",
                  enabled: _modIndex < constants.mods.length - 1,
                  onTap: () => _step(1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatMod(double mod) =>
      mod == mod.roundToDouble() ? mod.toStringAsFixed(0) : mod.toString();
}
