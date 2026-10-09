/// Name: SongBpm
/// Parent: SongPage
/// Description: Widgets relating to the song's BPM & mods
library;

import 'package:ddr_md/components/song/notes/chart_chrome.dart';
import 'package:ddr_md/components/song/notes/constant_speed.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/settings_model.dart';
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
    // The cabinet's num_min/num_core/num_max trio.
    final reads = widget.isBpmChange
        ? [
            ((mod * chart.trueMin).round(), "min"),
            (readSpeed, "core"),
            ((mod * chart.trueMax).round(), "max"),
          ]
        : [(readSpeed, null)];

    // Framed like the chart preview's speed dial ([SpeedPane]), so both places
    // you pick a mod handle the same way. The Card supplies the rounding and
    // fill the section cards use, so the pane draws neither.
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
          child: Stack(
            children: [
              IntrinsicHeight(
                child: Row(
                  children: [
                    EdgeButton(
                      label: "−10",
                      enabled: _modIndex > 0,
                      onTap: () => _step(-1),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.speed,
                                      size: 18,
                                      color: scheme.onSurfaceVariant,
                                      semanticLabel: 'Speed mod'),
                                  const SizedBox(width: 6),
                                  Text(
                                    "×${_formatMod(mod)}",
                                    style: TextStyle(
                                      fontSize: 19,
                                      height: 1.1,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.primary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Keep the read speeds on their own row so core stays
                            // easy to scan as its digit count changes.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final (i, (value, caption))
                                      in reads.indexed) ...[
                                    if (i > 0)
                                      const Padding(
                                        padding:
                                            EdgeInsets.symmetric(horizontal: 3),
                                        child: Text(
                                          "–",
                                          style: TextStyle(
                                            fontSize: 18,
                                            height: 1.1,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          "$value",
                                          style: const TextStyle(
                                            fontSize: 20,
                                            height: 1.1,
                                            fontWeight: FontWeight.bold,
                                            fontFeatures: [
                                              FontFeature.tabularFigures()
                                            ],
                                          ),
                                        ),
                                        if (caption != null)
                                          Text(
                                            caption,
                                            style: TextStyle(
                                              fontSize: 10,
                                              height: 1.0,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onSurface
                                                  .withValues(alpha: 0.55),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
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
              if (constant != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IgnorePointer(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${constant.ms}ms ≈ C${constant.c}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMod(double mod) =>
      mod == mod.roundToDouble() ? mod.toStringAsFixed(0) : mod.toString();
}
