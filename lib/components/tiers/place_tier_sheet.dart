/// Name: PlaceTierSheet
/// Parent: YourTiersPage, TierChips
/// Description: Puts one chart you've played on a rung of its level: − and +
/// step it, the ruler shows every rung with the calculated tier and your
/// circle's rungs on it, and the charts already on the rung sit below to
/// compare against.
library;

import 'package:ddr_md/components/circle/circle_page.dart' show CircleBubble;
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/components/tiers/tier_widgets.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/your_tiers.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Opens the sheet for [chart]; once placed or cleared, the circle gets the
/// change.
Future<void> showPlaceTierSheet(BuildContext context, LevelChart chart,
    {bool share = true}) async {
  final circle = context.read<CircleState>();
  final changed = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _PlaceSheet(chart),
  );
  if (changed == true && share) {
    await circle.shareTiers(post: (level: chart.level, count: 1));
  }
}

class _PlaceSheet extends StatefulWidget {
  const _PlaceSheet(this.chart);

  final LevelChart chart;

  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<_PlaceSheet> {
  late final int _step = tierStep(widget.chart.level);
  late int _rung = widget.chart.placement?.hundredths ??
      widget.chart.calc ??
      onRung(widget.chart.level, 50);

  void _move(int by) {
    final next = (_rung + by * _step).clamp(0, 100 - _step);
    if (next == _rung) return;
    HapticFeedback.selectionClick();
    setState(() => _rung = next);
  }

  Future<void> _save(int? rung) async {
    final c = widget.chart;
    await YourTiers.place(c.song.name, c.difficulty, c.level, rung);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final c = widget.chart;
    final circle = context.watch<CircleState>();
    final rungs = YourTiers.circleRungs(c.song.name, c.difficulty, c.level);
    final alongside = [
      for (final MapEntry(key: (song, difficulty), value: p)
          in YourTiers.all.entries)
        if (p.level == c.level &&
            p.hundredths == _rung &&
            (song, difficulty) != c.key)
          if (levelChart(song, difficulty, c.level) case final other?) other
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            SizedBox(
              width: 52,
              height: 52,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child:
                      SongArtwork(songName: c.song.name, title: c.song.title)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    DifficultyLabel(difficulty: c.difficulty, height: 14),
                  ]),
            ),
          ]),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            HeaderButton(
                tooltip: 'Easier',
                onPressed: _rung > 0 ? () => _move(-1) : null,
                icon: const Icon(Icons.remove_rounded)),
            const SizedBox(width: 18),
            LevelNumber(
                level: c.level,
                difficulty: c.difficulty,
                decimalHundredths: _rung,
                decimalKind: TierKind.mine,
                height: 56),
            const SizedBox(width: 10),
            HeaderButton(
                tooltip: 'Harder',
                onPressed: _rung < 100 - _step ? () => _move(1) : null,
                icon: const Icon(Icons.add_rounded)),
          ]),
          const SizedBox(height: 26),
          _Ruler(
            level: c.level,
            rung: _rung,
            calc: c.calc,
            circle: {
              for (final MapEntry(:key, :value) in rungs.entries)
                if (circle.tierPeople[key] case final p?) p: value
            },
            onPick: (h) {
              HapticFeedback.selectionClick();
              setState(() => _rung = h);
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: Row(children: [
              Text('ALSO ON ${rungLabel(_rung)}', style: pop.label),
              const SizedBox(width: 12),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  itemCount: alongside.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => TierJacket(alongside[i], size: 40),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          Row(children: [
            if (c.placement != null) ...[
              Expanded(
                  child: GhostButton(
                      height: 56,
                      onPressed: () => _save(null),
                      child: const Text('Clear'))),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: VoltButton(
                  onPressed: () => _save(_rung),
                  child: Text('Place at ${rungLabel(_rung)}',
                      style: FloorPop.display(16))),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Every rung of the level as a tick, tappable: yours boxed in Volt, the
/// calculated one under a triangle, the circle's as bubbles above.
class _Ruler extends StatelessWidget {
  const _Ruler(
      {required this.level,
      required this.rung,
      required this.calc,
      required this.circle,
      required this.onPick});

  final int level, rung;
  final int? calc;
  final Map<CirclePerson, int> circle;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final rungs = rungsOf(level).reversed.toList();
    return LayoutBuilder(builder: (context, box) {
      final gap = box.maxWidth / rungs.length;
      double x(int h) => (rungs.indexOf(h) + .5) * gap;
      final byRung = <int, List<CirclePerson>>{};
      for (final MapEntry(:key, :value) in circle.entries) {
        byRung.putIfAbsent(value, () => []).add(key);
      }
      return SizedBox(
        height: 84,
        child: Stack(clipBehavior: Clip.none, children: [
          for (final MapEntry(key: h, value: people) in byRung.entries)
            for (final (i, p) in people.take(3).indexed)
              Positioned(
                  left: x(h) - 9 + i * 6,
                  top: 0,
                  child: CircleBubble(p, size: 18)),
          if (calc != null)
            Positioned(
              left: x(calc!) - 7,
              top: 18,
              child: Icon(Icons.arrow_drop_down_rounded,
                  size: 14, color: pop.haze, semanticLabel: 'Calculated'),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: 30,
            height: 28,
            child: Row(children: [
              for (final h in rungs)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: h == rung,
                    label: rungLabel(h),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onPick(h),
                      child: Center(
                        child: AnimatedContainer(
                          duration: FloorPop.sixteenth,
                          width: h == rung ? 14 : 3,
                          height: h == rung ? 28 : (h % 25 == 0 ? 16 : 10),
                          decoration: BoxDecoration(
                            color: h == rung ? Colors.transparent : pop.line,
                            borderRadius: BorderRadius.circular(7),
                            border: h == rung
                                ? Border.all(color: pop.voltText, width: 2.5)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          for (final h in [0, 25, 50, 75, 100 - tierStep(level)])
            if (rungs.contains(h))
              Positioned(
                left: x(h) - 14,
                width: 28,
                top: 62,
                child: Text(rungLabel(h),
                    textAlign: TextAlign.center,
                    style: FloorPop.readout(11, color: pop.haze)),
              ),
        ]),
      );
    });
  }
}
