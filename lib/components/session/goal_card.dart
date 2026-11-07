/// Name: GoalCard
/// Parent: SessionPage, SessionWrapPage
/// Description: A session's goal as a stamp in its kind's colour, like a
/// cheer: what it's after in the game's own art, how many so far against
/// any target as pips, and a GOAL HIT or to-go stamp once it's told. The
/// sheet that sets it, and the live card on Home that counts the running
/// session's synced plays, bursting the moment a sync takes it to target.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/circle/cheer_stamp.dart' show burstConfetti;
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/session/recent_plays.dart' show chartOf;
import 'package:ddr_md/components/session/visits.dart' show visitsFor;
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song/scores/score_card.dart'
    show clearLampIcon;
import 'package:ddr_md/components/song_json.dart' show Modes;
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show formatTime12;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/db_models.dart' show ClearLamp;
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/session_goal.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/visit_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

extension GoalLook on GoalKind {
  /// The cheer palette, one colour a kind; [ink] reads on it.
  Color get color => switch (this) {
        GoalKind.grade => FloorPop.sun,
        GoalKind.newGrade => FloorPop.grape,
        GoalKind.lamp => const Color(0xFF3D5AFE),
        GoalKind.flare => FloorPop.coral,
        GoalKind.upscore => FloorPop.volt,
        GoalKind.clear => const Color(0xFF3DDC84),
      };

  /// The hard edge under a raised stamp.
  Color get riser => Color.lerp(color, Colors.black, 0.35)!;

  Color get ink => this == GoalKind.lamp ? Colors.white : FloorPop.onVolt;

  IconData get icon => switch (this) {
        GoalKind.grade => Icons.workspace_premium_outlined,
        GoalKind.newGrade => Icons.auto_awesome,
        GoalKind.lamp => Icons.wb_sunny_outlined,
        GoalKind.flare => Icons.local_fire_department_outlined,
        GoalKind.upscore => Icons.trending_up,
        GoalKind.clear => Icons.check_circle_outline,
      };
}

/// The art for a goal's grade, lamp or flare; null for kinds without one.
String? goalValueArt(SessionGoal goal) => switch (goal.kind) {
      GoalKind.grade || GoalKind.newGrade => gradeIcon(Grade.values
          .firstWhere((g) => g.label == goal.value, orElse: () => Grade.aaa)),
      GoalKind.lamp => clearLampIcon(ClearLamp.values.asNameMap()[goal.value]),
      GoalKind.flare => flareRankIcon(goal.value),
      _ => null,
    };

/// What [goal] is after in the game's art: its grade, lamp or flare, the
/// level's numeral (with a + for and up), and the style when doubles.
class GoalArt extends StatelessWidget {
  const GoalArt(this.goal, {super.key, this.height = 22, this.ink});
  final SessionGoal goal;
  final double height;
  // The words' colour, off the goal's stamp; the kind's ink on it.
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final ink = this.ink ?? goal.kind.ink;
    final art = goalValueArt(goal);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (art != null) Image.asset(art, height: height),
      if (art != null && goal.level != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('on',
              style: TextStyle(
                  color: ink, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      if (goal.level != null) ...[
        LevelNumber(level: goal.level!, difficulty: 'EXPERT', height: height),
        if (goal.andUp)
          Text('+', style: FloorPop.display(height * 0.8, color: ink)),
      ],
      // Singles goes without saying; only doubles is marked.
      if (goal.mode == Modes.doubles) ...[
        const SizedBox(width: 8),
        Image.asset('assets/icons/style_double.png', height: height * 0.6),
      ],
    ]);
  }
}

/// [goal] as a raised stamp: its title and art, [count] against its target
/// in pips, [stamp] (GOAL HIT, 2 TO GO) on its corner, then [footer].
class GoalCard extends StatelessWidget {
  const GoalCard(
      {super.key,
      required this.goal,
      this.count,
      this.stamp,
      this.onEdit,
      this.footer});

  final SessionGoal goal;
  // Null while still counting.
  final int? count;
  final String? stamp;
  final VoidCallback? onEdit;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final kind = goal.kind;
    final ink = kind.ink;
    final target = goal.target;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 16),
      decoration: BoxDecoration(
        color: kind.color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: kind.riser, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(kind.icon, size: 18, color: ink),
            const SizedBox(width: 6),
            Expanded(
              child: Text("TONIGHT'S GOAL",
                  style: FloorPop.of(context).label.copyWith(color: ink)),
            ),
            if (onEdit != null)
              IconButton(
                tooltip: 'Change goal',
                visualDensity: VisualDensity.compact,
                color: ink,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit,
              )
            else
              const SizedBox(height: 40),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Lean(
                    child: Text(goal.title,
                        style: FloorPop.display(22, color: ink)),
                  ),
                  const SizedBox(height: 10),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: GoalArt(goal)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Before any counting (the picker's preview), just the target.
            if (count == null)
              Text(target == null ? '' : '×$target',
                  style: FloorPop.readout(32, color: ink))
            else
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: target == null ? '+$count' : '$count',
                      style: FloorPop.readout(48, color: ink)),
                  if (target != null)
                    TextSpan(
                        text: '/$target',
                        style: FloorPop.readout(20,
                            color: ink.withValues(alpha: 0.6))),
                ]),
              ),
          ]),
          if (target != null) ...[
            const SizedBox(height: 12),
            _Pips(count: count ?? 0, target: target, ink: ink),
          ],
          if (footer != null) ...[const SizedBox(height: 12), footer!],
        ],
      ),
    );
    return Semantics(
      label: '${goal.title}: ${count ?? 0}'
          '${target == null ? '' : ' of $target'}${stamp == null ? '' : ', $stamp'}',
      child: Transform.rotate(
        angle: -0.02,
        child: Stack(clipBehavior: Clip.none, children: [
          card,
          if (stamp != null)
            Positioned(
              top: -14,
              right: 14,
              child: Transform.rotate(
                angle: 0.1,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: count != null && target != null && count! >= target
                        ? FloorPop.volt
                        : FloorPop.onVolt,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 12)
                    ],
                  ),
                  child: Text(stamp!,
                      style: FloorPop.display(14,
                          color: count != null &&
                                  target != null &&
                                  count! >= target
                              ? FloorPop.onVolt
                              : kind.color)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Pips extends StatelessWidget {
  const _Pips({required this.count, required this.target, required this.ink});
  final int count, target;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    // Past a dozen, pips get too thin to count: one bar instead.
    if (target > 12) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LinearProgressIndicator(
            value: (count / target).clamp(0, 1),
            minHeight: 10,
            color: ink,
            backgroundColor: ink.withValues(alpha: 0.18)),
      );
    }
    return Row(children: [
      for (var i = 0; i < target; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: Lean(
            child: AnimatedContainer(
              duration: FloorPop.beat,
              height: 10,
              decoration: BoxDecoration(
                color: i < count ? ink : ink.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// How a session's goal went, told as it happens: the goal's colour floods up
/// a tank as the count ticks, each counted chart's jacket landing with its
/// tick, then GOAL HIT slams on with confetti, or the to-go stamp drops.
class GoalReveal extends StatefulWidget {
  const GoalReveal(this.progress, {super.key});
  final GoalProgress progress;

  @override
  State<GoalReveal> createState() => _GoalRevealState();
}

class _GoalRevealState extends State<GoalReveal> with TickerProviderStateMixin {
  static const _lead = 450.0, _landing = 320.0, _slam = 260.0;
  static const _shownJackets = 12;

  late final int _n = widget.progress.count;
  late final double _step = _n == 0 ? 0 : (1800 / _n).clamp(140.0, 420.0);
  late final double _stampAt = _lead + _step * _n + 200;
  late final double _total = _stampAt + _slam + 700;
  late final _clock = AnimationController(
      vsync: this, duration: Duration(milliseconds: _total.round()))
    ..addListener(_tick);
  late final _swell =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));
  final _stampKey = GlobalKey();
  int _ticked = 0;
  bool _slammed = false;

  double get _ms => _clock.value * _total;
  // Counted so far, with the part of the tick in progress.
  double get _ticks =>
      _step == 0 ? 0 : ((_ms - _lead) / _step).clamp(0.0, _n.toDouble());
  int get _shown => _clock.isCompleted
      ? widget.progress.count
      : _ms < _lead
          ? 0
          : math.min(_n, _ticks.floor() + 1);
  // 1 at the stamp's impact, gone 400ms on.
  double get _hit {
    final since = _ms - _stampAt - _slam;
    return since < 0 ? 0 : 1 - (since / 400).clamp(0.0, 1.0);
  }

  void _tick() {
    if (_shown > _ticked) {
      _ticked = _shown;
      HapticFeedback.selectionClick();
    }
    if (!_slammed && _ms >= _stampAt + _slam) {
      _slammed = true;
      _land();
    }
  }

  void _land() {
    if (!widget.progress.reached) {
      if (widget.progress.goal.target != null) HapticFeedback.lightImpact();
      return;
    }
    HapticFeedback.heavyImpact();
    final box = _stampKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.attached) {
      burstConfetti(context, box.localToGlobal(box.size.center(Offset.zero)),
          widget.progress.goal.kind.color);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _slammed = true;
        _ticked = _n;
        _clock.value = 1;
      } else {
        _clock.forward();
        _swell.repeat();
      }
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    _swell.dispose();
    super.dispose();
  }

  double get _level {
    final target = widget.progress.goal.target;
    final whole = _ticks.floor();
    final x = whole + Curves.easeOutCubic.transform(_ticks - whole);
    // An open goal has no full, so any haul fills it most of the way.
    return target == null
        ? (_n == 0 ? 0 : x / _n * .7)
        : (x / target).clamp(0.0, 1.0);
  }

  Widget _face(FloorPop pop, Color ink) {
    final goal = widget.progress.goal;
    final target = goal.target;
    final shown = _shown;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(goal.kind.icon, size: 18, color: ink),
          const SizedBox(width: 6),
          Text("TONIGHT'S GOAL", style: pop.label.copyWith(color: ink)),
        ]),
        const SizedBox(height: 10),
        FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Lean(
                child:
                    Text(goal.title, style: FloorPop.display(30, color: ink)))),
        const SizedBox(height: 8),
        FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: GoalArt(goal, height: 26, ink: ink)),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: target == null ? '+$shown' : '$shown',
                style: FloorPop.readout(92, color: ink)),
            if (target != null)
              TextSpan(
                  text: '/$target',
                  style:
                      FloorPop.readout(30, color: ink.withValues(alpha: .6))),
          ])),
        ),
        if (target != null) ...[
          const SizedBox(height: 10),
          _Pips(count: shown, target: target, ink: ink),
        ],
      ]),
    );
  }

  Widget _tank(FloorPop pop) {
    final kind = widget.progress.goal.kind;
    final level = _level, phase = _swell.value;
    return SizedBox(
      height: 280,
      child: DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: level > 0 ? kind.riser : pop.line,
                  offset: const Offset(0, 6))
            ]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: pop.riser),
            _face(
                pop,
                pop.riser.computeLuminance() < .5
                    ? Colors.white
                    : FloorPop.onVolt),
            // The swell behind, then the water, whose face reads in its ink.
            ClipPath(
                clipper: _Water(level, phase + .4),
                child: ColoredBox(color: kind.color.withValues(alpha: .35))),
            ClipPath(
                clipper: _Water(level, phase),
                child:
                    ColoredBox(color: kind.color, child: _face(pop, kind.ink))),
          ]),
        ),
      ),
    );
  }

  Widget _stamp() {
    final progress = widget.progress;
    final kind = progress.goal.kind;
    final target = progress.goal.target;
    if (target == null) return const SizedBox.shrink();
    final hit = progress.reached;
    final t = ((_ms - _stampAt) / _slam).clamp(0.0, 1.0);
    return Positioned(
      top: -18,
      right: 10,
      child: Opacity(
        opacity: t == 0 ? 0 : 1,
        child: Transform.scale(
          // Falls at the tank from above the screen when hit; else just drops.
          scale: (hit ? 3.0 : 1.6) -
              (hit ? 2.0 : .6) * Curves.easeInCubic.transform(t),
          child: Transform.rotate(
            angle: .1,
            child: Container(
              key: _stampKey,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: hit
                      ? (kind == GoalKind.upscore
                          ? Colors.white
                          : FloorPop.volt)
                      : FloorPop.onVolt,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 12)
                  ]),
              child: Text(hit ? 'GOAL HIT' : '${target - progress.count} TO GO',
                  style: FloorPop.display(20,
                      color: hit ? FloorPop.onVolt : Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  // A counted chart's jacket, slapped down on its tick.
  Widget _jacket(int i, GoalHit hit, double side) {
    final t = ((_ms - _lead - _step * i) / _landing).clamp(0.0, 1.0);
    final eased = Curves.easeOutBack.transform(t);
    return Opacity(
      opacity: t == 0 ? 0 : 1,
      child: Transform.scale(
        scale: 1.7 - .7 * eased,
        child: Transform.rotate(
          angle: (i.isEven ? -1 : 1) * (.05 + .25 * (1 - eased)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.square(
                dimension: side,
                child: SongArtwork(
                    songName: hit.song ?? hit.title, title: hit.title)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final progress = widget.progress;
    final hits = progress.hits;
    final extra = hits.length - _shownJackets;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${progress.goal.title}: ${goalSummary(progress)}'
          '${progress.reached ? ' Goal hit.' : ''}',
      child: AnimatedBuilder(
        animation: Listenable.merge([_clock, _swell]),
        builder: (context, _) => Column(children: [
          Transform.scale(
            scale: 1 + .035 * _hit,
            child: Transform.rotate(
              angle: -.02,
              child: Stack(clipBehavior: Clip.none, children: [
                _tank(pop),
                _stamp(),
              ]),
            ),
          ),
          if (hits.isNotEmpty) ...[
            const SizedBox(height: 26),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final (i, hit) in hits.take(_shownJackets).indexed)
                    _jacket(i, hit, 64),
                  if (extra > 0 && _shown > _shownJackets)
                    SizedBox.square(
                        dimension: 64,
                        child: Center(
                            child: Text('+${_shown - _shownJackets}',
                                style: FloorPop.readout(22, color: pop.haze)))),
                ]),
          ],
        ]),
      ),
    );
  }
}

// What's under the water line at [level] of the way up, its surface a swell
// that flattens out as the tank empties or fills.
class _Water extends CustomClipper<Path> {
  _Water(this.level, this.phase);
  final double level, phase;

  @override
  Path getClip(Size size) {
    final calm = math.min(1.0, math.min(level, 1 - level) * 8);
    final top = size.height * (1 - level);
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0;; x = math.min(x + 6, size.width)) {
      final slant = (x / size.width - .5) * -16;
      final swell = math.sin((x / size.width * 1.4 + phase) * 2 * math.pi) * 7;
      path.lineTo(x, top + (swell + slant) * calm);
      if (x >= size.width) break;
    }
    return path
      ..lineTo(size.width, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_Water old) => old.level != level || old.phase != phase;
}

/// The running session's goal on Home, counted over its synced plays. A
/// sync that first takes it to target bursts it and marks it reached.
class LiveGoalCard extends StatefulWidget {
  const LiveGoalCard({super.key});

  @override
  State<LiveGoalCard> createState() => _LiveGoalCardState();
}

class _LiveGoalCardState extends State<LiveGoalCard> {
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final sync = context.watch<EamuseSyncState>();
    final goal = session.session?.goal;
    if (goal == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Set a goal for this session'),
          onPressed: () => _edit(context, null),
        ),
      );
    }
    return FutureBuilder(
      future: (visitsFor(context), ChartBests.ensure(goal.mode)).wait,
      builder: (context, snapshot) {
        final progress = switch (snapshot.data) {
          (final data, _) => () {
              final visit = data.visits
                  .where((v) => v.session?.id == session.session!.id)
                  .firstOrNull;
              return goalProgressNow(
                  goal,
                  visit?.plays ?? const [],
                  visit == null ? const [] : gainsIn(visit, data.gains),
                  (song, mode, difficulty) =>
                      chartOf(song, mode, difficulty).level);
            }(),
          _ => null,
        };
        if (progress != null &&
            progress.reached &&
            session.session!.goalHitAt == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _hit(session));
        }
        final syncedAt = sync.syncedAt;
        final ink = goal.kind.ink;
        return Padding(
          key: _key,
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
          child: GoalCard(
            goal: goal,
            count: progress?.count,
            stamp: session.session!.goalHitAt != null ? 'GOAL HIT' : null,
            onEdit: () => _edit(context, goal),
            footer: Row(children: [
              Expanded(
                child: Text(
                    syncedAt == null ||
                            syncedAt.isBefore(session.session!.startedAt)
                        ? 'Counts as this session\'s plays sync'
                        : 'As of the ${formatTime12(syncedAt)} sync',
                    style: TextStyle(
                        color: ink, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: ink, foregroundColor: goal.kind.color),
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Sync'),
                onPressed: sync.status == EamuseStatus.syncing
                    ? null
                    : () => sync.sync(asked: true),
              ),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _hit(SessionState session) async {
    if (!mounted || session.session?.goalHitAt != null) return;
    await session.goalHit();
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.attached) {
      burstConfetti(context, box.localToGlobal(box.size.center(Offset.zero)),
          session.session!.goal!.kind.color);
    }
  }

  Future<void> _edit(BuildContext context, SessionGoal? goal) async {
    final session = context.read<SessionState>();
    final picked = await showGoalSheet(context, goal);
    if (picked != null) await session.setGoal(picked.$1);
  }
}

/// Picks a goal, starting from [initial]. Null when dismissed; `(null,)`
/// when the goal is taken away.
Future<(SessionGoal?,)?> showGoalSheet(
        BuildContext context, SessionGoal? initial) =>
    showModalBottomSheet<(SessionGoal?,)>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _GoalSheet(initial),
    );

class _GoalSheet extends StatefulWidget {
  const _GoalSheet(this.initial);
  final SessionGoal? initial;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late SessionGoal _goal = widget.initial ??
      SessionGoal(
          kind: GoalKind.grade,
          value: GoalKind.grade.aims.first,
          level: _levels.first + 3);

  static const _levels = [12, 13, 14, 15, 16, 17, 18, 19];
  static const _targets = [3, 5, 10];

  void _kind(GoalKind k) => setState(() => _goal =
      _goal.copyWith(kind: k, value: k.aims.isEmpty ? '' : k.aims.first));

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(text, style: pop.label),
        );
    Widget chip(
            {required bool selected,
            required VoidCallback onTap,
            required Widget child,
            String? semantics}) =>
        Semantics(
          selected: selected,
          button: true,
          label: semantics,
          child: Material(
            color: selected ? scheme.onSurface : pop.riser,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                child: DefaultTextStyle.merge(
                    style: TextStyle(
                        color: selected ? scheme.surface : scheme.onSurface,
                        fontWeight: FontWeight.w700),
                    child: child),
              ),
            ),
          ),
        );
    final aims = _goal.kind.aims;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Lean(
                    child: Text('Session goal',
                        style: FloorPop.display(22, color: scheme.onSurface))),
              ),
              if (widget.initial != null)
                TextButton(
                    onPressed: () => Navigator.pop(context, (null,)),
                    child: const Text('No goal')),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ]),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 3,
              children: [
                for (final k in GoalKind.values)
                  _KindTile(k,
                      selected: k == _goal.kind, onTap: () => _kind(k)),
              ],
            ),
            if (aims.length > 1) ...[
              label(switch (_goal.kind) {
                GoalKind.lamp => 'LAMP OR BETTER',
                GoalKind.flare => 'FLARE OR HIGHER',
                _ => 'GRADE OR BETTER',
              }),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final a in aims) ...[
                      chip(
                        selected: a == _goal.value,
                        semantics: a,
                        onTap: () =>
                            setState(() => _goal = _goal.copyWith(value: a)),
                        child: Image.asset(
                            goalValueArt(_goal.copyWith(value: a))!,
                            height: 22),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],
            label('CHART LEVEL'),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  chip(
                      selected: _goal.level == null,
                      onTap: () => setState(
                          () => _goal = _goal.copyWith(level: () => null)),
                      child: const Text('Any')),
                  for (final l in _levels) ...[
                    const SizedBox(width: 8),
                    chip(
                      selected: _goal.level == l,
                      semantics: 'Level $l',
                      onTap: () => setState(
                          () => _goal = _goal.copyWith(level: () => l)),
                      child: LevelNumber(level: l, difficulty: 'EXPERT'),
                    ),
                  ],
                ],
              ),
            ),
            if (_goal.level != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Higher levels count too'),
                value: _goal.andUp,
                onChanged: (on) =>
                    setState(() => _goal = _goal.copyWith(andUp: on)),
              ),
            label('STYLE'),
            SegmentedButton<Modes>(
              segments: [
                for (final (m, art) in const [
                  (Modes.singles, 'assets/icons/style_single.png'),
                  (Modes.doubles, 'assets/icons/style_double.png'),
                ])
                  ButtonSegment(
                      value: m,
                      label: Image.asset(art,
                          height: 18,
                          semanticLabel:
                              m == Modes.singles ? 'Singles' : 'Doubles')),
              ],
              selected: {_goal.mode},
              onSelectionChanged: (s) =>
                  setState(() => _goal = _goal.copyWith(mode: s.first)),
            ),
            label('HOW MANY'),
            Row(children: [
              chip(
                  selected: _goal.target == null,
                  onTap: () => setState(
                      () => _goal = _goal.copyWith(target: () => null)),
                  child: const Text('Open')),
              for (final t in _targets) ...[
                const SizedBox(width: 8),
                chip(
                    selected: _goal.target == t,
                    onTap: () =>
                        setState(() => _goal = _goal.copyWith(target: () => t)),
                    child: Text('$t')),
              ],
              const Spacer(),
              IconButton(
                tooltip: 'Fewer',
                onPressed: (_goal.target ?? 0) <= 1
                    ? null
                    : () => setState(() => _goal =
                        _goal.copyWith(target: () => _goal.target! - 1)),
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                tooltip: 'More',
                onPressed: () => setState(() => _goal =
                    _goal.copyWith(target: () => (_goal.target ?? 0) + 1)),
                icon: const Icon(Icons.add),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_counts(_goal),
                  style: TextStyle(color: pop.haze, fontSize: 12)),
            ),
            const SizedBox(height: 24),
            GoalCard(goal: _goal),
            const SizedBox(height: 24),
            VoltButton(
              onPressed: () => Navigator.pop(context, (_goal,)),
              child: const Text('Set goal'),
            ),
          ],
        ),
      ),
    );
  }
}

String _counts(SessionGoal g) => switch (g.kind) {
      GoalKind.grade =>
        'Every play at ${g.value} or better counts, repeats too.',
      GoalKind.newGrade =>
        'Each chart counts once, when its best first reaches ${g.value}.',
      GoalKind.lamp =>
        'Each chart counts once, when its lamp first reaches ${g.value.toUpperCase()} or better.',
      GoalKind.flare =>
        'Each chart counts once, when its flare first reaches ${g.value} or higher.',
      GoalKind.upscore => 'Each chart whose best score goes up counts once.',
      GoalKind.clear => 'Every play that clears counts, repeats too.',
    };

/// A kind to pick: tinted in its colour, or stamped full colour, leaning and
/// raised, when picked.
class _KindTile extends StatelessWidget {
  const _KindTile(this.kind, {required this.selected, required this.onTap});
  final GoalKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? kind.ink : Theme.of(context).colorScheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: FloorPop.eighth,
        curve: FloorPop.step,
        transform: Matrix4.translationValues(0, selected ? -2 : 0, 0)
          ..rotateZ(selected ? -0.03 : 0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? kind.color : kind.color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (selected)
              BoxShadow(color: kind.riser, offset: const Offset(0, 5)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Icon(kind.icon,
                    size: 20, color: selected ? kind.ink : kind.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(kind.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FloorPop.display(12, color: fg)),
                ),
                if (selected) Icon(Icons.check, size: 18, color: kind.ink),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A past session's goal in a row: a flag in the goal's colour when reached,
/// faded when missed, and the count for an open goal.
class GoalMark extends StatelessWidget {
  const GoalMark(this.progress, {super.key});
  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final kind = progress.goal.kind;
    final open = progress.goal.target == null;
    final on = open || progress.reached;
    return Tooltip(
      message: '${progress.goal.title}: ${progress.count}'
          '${open ? '' : ' of ${progress.goal.target}'}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: on ? kind.color : kind.color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
          Icon(on ? Icons.flag : Icons.outlined_flag,
              size: 14, color: on ? kind.ink : kind.color),
          Text(
              open
                  ? '+${progress.count}'
                  : '${progress.count}/${progress.goal.target}',
              style: FloorPop.readout(12, color: on ? kind.ink : kind.color)),
        ]),
      ),
    );
  }
}

/// "Goals 4/6": of the last finished sessions with a target, how many hit.
class GoalRecord extends StatelessWidget {
  const GoalRecord(this.record, {super.key});
  final ({int hit, int of}) record;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Goals hit in the last ${record.of} sessions with a target',
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
          Icon(Icons.flag_outlined, size: 16, color: FloorPop.of(context).haze),
          Text('${record.hit}/${record.of}',
              style: FloorPop.readout(14, color: FloorPop.of(context).haze)),
        ]),
      );
}
