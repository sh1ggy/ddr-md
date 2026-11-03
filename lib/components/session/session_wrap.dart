/// Name: SessionWrap
/// Parent: LastSessionCard, VisitPage, SessionPage
/// Description: A session told once its plays are synced: how it went
/// against your usual, who in your circle cheered it when it was broadcast,
/// then every card its plays collected or upgraded
/// dealt at once like a pack, each opening on its own beside what it was,
/// then into the binder, where they slot into their pockets sheet by sheet.
/// Ending a session opens it straight away and syncs while it shows; Home
/// offers it from a banner after a sync brings a session new plays, and the
/// session's Collected row opens it again.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:ddr_md/components/circle/cheer_stamp.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/session/goal_card.dart';
import 'package:ddr_md/components/settings/development_page.dart';
import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/session/session_summary.dart';
import 'package:ddr_md/components/session/visits.dart' show loadVisits;
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song/jacket_edition/compact_jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_binder_page.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_model.dart';
import 'package:ddr_md/components/song/jacket_edition/jacket_edition.dart';
import 'package:ddr_md/components/song/scores/art_badge.dart';
import 'package:ddr_md/components/song_json.dart' show Modes;
import 'package:ddr_md/components/song/scores/score_card.dart'
    show clearLampIcon;
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show formatScore, kInGameDifficultyNames;
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:ddr_md/models/session_goal.dart';
import 'package:ddr_md/models/session_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/version_group.dart';
import 'package:ddr_md/models/visit_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// How far off your usual a set reads as great, or rough.
const _verdictGap = 5000.0;

/// One chart's card and the gains that made it what it is now.
typedef WrapCard = ({
  ChartBest best,
  List<CardGain> gains,
  EditionFacts now,
  // Null for a card the session collected.
  EditionFacts? before,
  String title,
  int? level,
});

/// [gains]' charts, in the order first gained, each with its card now and
/// before the session.
List<WrapCard> wrapCards(List<CardGain> gains) {
  final byChart =
      <({String song, Modes mode, String difficulty}), List<CardGain>>{};
  for (final g in gains) {
    byChart.putIfAbsent(g.chart, () => []).add(g);
  }
  return [
    for (final MapEntry(key: chart, value: had) in byChart.entries)
      () {
        final best =
            had.skip(1).fold(had.first.best, (b, g) => mergeBest(b, g.best));
        final c = chartOf(chart.song, chart.mode, chart.difficulty);
        final key = kInGameDifficultyNames.entries
            .firstWhere((e) => e.value == chart.difficulty,
                orElse: () => const MapEntry('', ''))
            .key;
        EditionFacts facts(ChartBest b) => EditionFacts(
            chart: (song: chart.song, mode: chart.mode.name, difficulty: key),
            level: c.level,
            version: c.song == null ? null : flareGroup(c.song!.version),
            grade: b.grade,
            flare: b.flare,
            lamp: b.lamp,
            score: b.score);
        String? from(CardLayer layer) =>
            had.where((g) => g.layer == layer).firstOrNull?.from;
        String? orNull(String? s) => s == null || s.isEmpty ? null : s;
        final fresh = had.any((g) => g.layer == CardLayer.card);
        return (
          best: best,
          gains: had,
          now: facts(best),
          before: fresh
              ? null
              : facts((
                  score: had.first.fromScore ?? best.score,
                  grade: switch (from(CardLayer.finish)) {
                    null => best.grade,
                    final g =>
                      Grade.values.where((v) => v.label == g).firstOrNull,
                  },
                  lamp: switch (from(CardLayer.frame)) {
                    null => best.lamp,
                    final l => ClearLamp.values.asNameMap()[l],
                  },
                  flare: switch (from(CardLayer.aura)) {
                    null => best.flare,
                    final f => orNull(f),
                  },
                )),
          title: c.song?.title ?? chart.song,
          level: c.level,
        );
      }(),
  ];
}

const _cardOptions = (
  borderId: 'gilded',
  effects: true,
  motion: true,
  modeStamp: false,
  gradeStamp: false,
  difficultyStamp: false,
  tierSuffix: false
);

Widget _compact(WrapCard card, EditionFacts facts) => CompactJacketEdition(
    facts: facts,
    options: (
      borderId: _cardOptions.borderId,
      effects: true,
      motion: false,
      modeStamp: false,
      gradeStamp: false,
      difficultyStamp: false,
      tierSuffix: false
    ),
    child: SongArtwork(songName: card.now.chart.song, title: card.title));

/// Opens the wrap of [visit], whose plays made [gains]. [cheered] stands in
/// for the circle's cheers, for a preview.
Future<void> showSessionWrap(BuildContext context,
        {required Visit visit,
        required SetSummary summary,
        required List<CardGain> gains,
        List<CircleCredit>? cheered}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SessionWrapPage(
            visit: visit, summary: summary, gains: gains, cheered: cheered)));

/// Ends the running session and, with e-amusement linked, opens its wrap at
/// once, which collects the session's plays and cards while it shows.
Future<void> endSession(BuildContext context) async {
  final session = context.read<SessionState>();
  final eamuse = context.read<EamuseSyncState>();
  final navigator = Navigator.of(context, rootNavigator: true);
  final id = session.session!.id;
  await session.end();
  if (eamuse.charts == 0 || eamuse.status == EamuseStatus.signedOut) return;
  await navigator.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SessionWrapPage.ended(sessionId: id)));
}

/// Completes the next time [listenable] notifies.
Future<void> _heard(Listenable listenable) {
  final heard = Completer<void>();
  void once() {
    listenable.removeListener(once);
    heard.complete();
  }

  listenable.addListener(once);
  return heard.future;
}

class SessionWrapPage extends StatefulWidget {
  const SessionWrapPage(
      {super.key,
      required Visit this.visit,
      required SetSummary this.summary,
      required this.gains,
      this.cheered})
      : sessionId = null;

  const SessionWrapPage.ended({super.key, required String this.sessionId})
      : visit = null,
        summary = null,
        gains = const [],
        cheered = null;

  final Visit? visit;
  final SetSummary? summary;
  final List<CardGain> gains;
  final List<CircleCredit>? cheered;

  /// The session just ended, whose plays and cards a sync is collecting.
  final String? sessionId;

  @override
  State<SessionWrapPage> createState() => _SessionWrapPageState();
}

class _SessionWrapPageState extends State<SessionWrapPage>
    with TickerProviderStateMixin {
  late Visit? _visit = widget.visit;
  late SetSummary? _summary = widget.summary;
  late List<CardGain> _gains = widget.gains;
  late List<WrapCard> _cards = wrapCards(widget.gains);
  // Into [_beats]; after the cards, the binder they go into.
  int _beat = 0;
  // The beats as they stood on leaving the first, so cheers landing later
  // don't shift the one on screen.
  List<_Beat>? _shown;
  late bool _collecting = widget.sessionId != null;
  EamuseSyncState? _eamuse;
  int? _revision;
  // Bumped per load, so only the latest lands.
  int _loads = 0;
  Future<void>? _loading;
  late final _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 14))
        ..repeat();

  @override
  void initState() {
    super.initState();
    if (widget.sessionId != null) _collect();
    // The latest cheers on this session.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<CircleState>().poll());
  }

  String? get _sessionId => widget.sessionId ?? _visit?.session?.id;

  /// Your shared credits of this session that were cheered, oldest first.
  List<CircleCredit> _cheered(CircleState circle) =>
      widget.cheered ??
      [
        for (final c in circle.yours.reversed)
          if (c.session == _sessionId && c.cheers.isNotEmpty) c
      ];

  List<_Beat> _beats(CircleState circle) =>
      _shown ??
      [
        _Beat.verdict,
        if (_cheered(circle).isNotEmpty) _Beat.circle,
        if (_cards.isNotEmpty) _Beat.pack,
      ];

  @override
  void dispose() {
    _eamuse?.removeListener(_synced);
    _spin.dispose();
    super.dispose();
  }

  Future<void> _collect() async {
    final eamuse =
        _eamuse = context.read<EamuseSyncState>()..addListener(_synced);
    _revision = eamuse.revision;
    // One already running may have read the plays before the session ended.
    while (eamuse.status == EamuseStatus.syncing) {
      await _heard(eamuse);
    }
    await eamuse.sync(asked: true);
    _load();
    // A load started since (a cloud sync pulling, say) drops this one, so
    // collecting is over only once the latest has landed.
    Future<void>? landed;
    while (landed != _loading) {
      await (landed = _loading);
    }
    // Seen here, so Home doesn't offer it again.
    await Settings.setString(Settings.sessionWrapSinceKey, '');
    if (mounted) setState(() => _collecting = false);
  }

  // The plays land before the charts, so how it went shows while the cards
  // are still coming.
  void _synced() {
    final revision = _eamuse!.revision;
    if (revision != _revision) {
      _revision = revision;
      _load();
    }
    if (mounted) setState(() {});
  }

  Future<void> _load() => _loading = _read(++_loads);

  Future<void> _read(int load) async {
    final data = await loadVisits(null);
    final visit = data.visits
        .where((v) => v.session?.id == widget.sessionId && v.plays.isNotEmpty)
        .firstOrNull;
    if (!mounted || load != _loads || visit == null) return;
    final gains = gainsIn(visit, data.gains);
    // For an upscore goal, which plays set a best.
    if (visit.session?.goal case final goal?) {
      await ChartBests.ensure(goal.mode);
    }
    if (!mounted || load != _loads) return;
    setState(() {
      _visit = visit;
      _summary = data.model.summarize(visit.plays);
      _gains = gains;
      _cards = wrapCards(gains);
    });
  }

  /// How the session's goal went, once its plays are in.
  GoalProgress? _goalProgress() {
    final visit = _visit;
    final goal = visit?.session?.goal;
    if (visit == null || goal == null) return null;
    return goalProgressNow(goal, visit.plays, _gains,
        (song, mode, difficulty) => chartOf(song, mode, difficulty).level);
  }

  void _next() {
    final beats = _beats(context.read<CircleState>());
    if (_beat < beats.length - 1) {
      setState(() {
        _shown = beats;
        _beat++;
      });
    } else if (beats[_beat] == _Beat.pack) {
      _intoBinder();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Hands over to the binder, in the profile's style, where the cards slot
  /// into their pockets.
  void _intoBinder() {
    final mode = context.read<SongState>().modes;
    final cards = [
      for (final c in _cards)
        if (c.gains.first.mode == mode) c
    ];
    if (cards.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: FloorPop.beat,
        pageBuilder: (_, __, ___) =>
            EditionBinderPage(level: cards.first.level, arrivals: {
              for (final c in cards)
                (song: c.now.chart.song, difficulty: c.gains.first.difficulty):
                    c.before,
            }),
        // Coming up out of the stage colour rather than faded itself, as a
        // card's finish doesn't draw while it's faded.
        transitionsBuilder: (context, a, __, child) =>
            Stack(fit: StackFit.expand, children: [
              child,
              IgnorePointer(
                  child: FadeTransition(
                      opacity: ReverseAnimation(a),
                      child: ColoredBox(color: FloorPop.of(context).stage))),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final visit = _visit;
    final eamuse = _eamuse;
    final n = _cards.length;
    final circle = context.watch<CircleState>();
    final beats = _beats(circle);
    final beat = beats[_beat];
    final action = switch (_beat) {
      0 when _collecting => _summary == null
          ? 'Collecting your plays'
          : 'Collecting cards · ${((eamuse?.progress ?? 0) * 100).round()}%',
      // On to the next beat, or the binder after the cards: an arrow alone.
      _ when _beat == beats.length - 1 && beat != _Beat.pack => 'Done',
      _ => null,
    };
    // Why a finished collection found nothing.
    final missing = _collecting || visit != null
        ? null
        : switch (eamuse?.status) {
            EamuseStatus.signedOut => 'Sign in to e-amusement on Home, then '
                'sync to collect this session.',
            EamuseStatus.failed => eamuse!.error,
            _ => 'e-amusement hasn\'t listed these plays yet. Sync from Home '
                'in a minute to collect them.',
          };
    return Scaffold(
      backgroundColor: pop.stage,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SESSION WRAP',
                          style: pop.label.copyWith(color: pop.voltText)),
                      const SizedBox(height: 6),
                      visit == null
                          ? const VisitTag(
                              Icons.cloud_download_rounded, 'From e-amusement')
                          : VisitTags(visit, venue: true),
                    ]),
              ),
              IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(spacing: 6, children: [
              for (var i = 0; i < beats.length + (n == 0 ? 0 : 1); i++)
                Expanded(
                    child: AnimatedContainer(
                        duration: FloorPop.eighth,
                        height: 4,
                        decoration: BoxDecoration(
                            color: i <= _beat ? FloorPop.volt : pop.line,
                            borderRadius: BorderRadius.circular(2)))),
            ]),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: FloorPop.beat,
              switchInCurve: FloorPop.settle,
              // The outgoing beat fades; the incoming one comes in whole, as a card's
              // finish doesn't draw while it's faded.
              transitionBuilder: (child, a) => child.key == ValueKey(_beat)
                  ? child
                  : FadeTransition(opacity: a, child: child),
              child: KeyedSubtree(
                key: ValueKey(_beat),
                child: switch (beat) {
                  _Beat.verdict => _Verdict(_summary,
                      cards: n,
                      spin: _spin,
                      missing: missing,
                      goal: _goalProgress()),
                  _Beat.circle => _ShowedUp(_cheered(circle)),
                  _Beat.pack => _Pack(_cards, gains: _gains),
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(children: [
              if (_beat > 0) ...[
                IconButton.filledTonal(
                    tooltip: 'Back',
                    iconSize: 24,
                    onPressed: () => setState(() => _beat--),
                    icon: const Icon(Icons.arrow_back_rounded)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: VoltButton(
                    onPressed: _beat == 0 && _collecting ? null : _next,
                    child: action == null
                        ? const Icon(Icons.arrow_forward_rounded, size: 28)
                        : Text(action, style: FloorPop.display(16))),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

enum _Beat { verdict, circle, pack }

// The circle's beat: everyone who cheered the broadcast, each cheer a card
// in its own colour slapped on at its own lean, with the credit it was for.
// Confetti bursts from each friend's first card in turn, so more friends
// throw more of it.
class _ShowedUp extends StatefulWidget {
  const _ShowedUp(this.credits);
  final List<CircleCredit> credits;

  @override
  State<_ShowedUp> createState() => _ShowedUpState();
}

class _ShowedUpState extends State<_ShowedUp> {
  late final _cheers = [
    for (final c in widget.credits)
      for (final x in c.cheers) (credit: c.credit, cheer: x)
  ];
  // Each friend's first card, where their confetti comes from.
  final _firsts = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    for (final c in _cheers) {
      _firsts.putIfAbsent(c.cheer.id ?? c.cheer.name, GlobalKey.new);
    }
    // Once the beat has settled in.
    Future.delayed(FloorPop.beat, () async {
      for (final (i, key) in _firsts.values.indexed) {
        if (!mounted) return;
        final box = key.currentContext?.findRenderObject() as RenderBox?;
        final cheer = _cheers
            .firstWhere((c) => _firsts[c.cheer.id ?? c.cheer.name] == key)
            .cheer
            .cheer;
        if (box != null && box.attached) {
          if (i > 0) HapticFeedback.lightImpact();
          burstConfetti(context,
              box.localToGlobal(box.size.center(Offset.zero)), cheer.color);
        }
        await Future.delayed(const Duration(milliseconds: 220));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
      children: [
        Transform(
            transform: FloorPop.titleLean,
            child: Text('Your circle\nshowed up',
                style: FloorPop.display(28,
                    color: Theme.of(context).colorScheme.onSurface))),
        const SizedBox(height: 20),
        for (final (i, (:credit, :cheer)) in _cheers.indexed)
          Align(
            alignment: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Transform.rotate(
                key: seen.add(cheer.id ?? cheer.name)
                    ? _firsts[cheer.id ?? cheer.name]
                    : null,
                angle: cheer.cheer.tilt,
                child: Container(
                  width: 250,
                  padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: cheer.cheer.color,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                          color: cheer.cheer.color.withValues(alpha: 0.4),
                          blurRadius: 18,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                          color: cheer.cheer.ink, shape: BoxShape.circle),
                      child: CircleAvatar(
                          radius: 20,
                          backgroundColor: avatarColour(cheer.id ?? cheer.name),
                          child: Text(
                              cheer.name.isEmpty
                                  ? '?'
                                  : cheer.name.substring(0, 1),
                              style: FloorPop.display(16,
                                  color: avatarInk(
                                      avatarColour(cheer.id ?? cheer.name))))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${cheer.name} · credit $credit',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color:
                                        cheer.cheer.ink.withValues(alpha: 0.75),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                            Row(children: [
                              Icon(cheer.cheer.icon,
                                  size: 18, color: cheer.cheer.ink),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(cheer.cheer.label,
                                    style: FloorPop.display(18,
                                        color: cheer.cheer.ink)),
                              ),
                            ]),
                          ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Beat one: the gap from your usual, counting up inside a spinning ring; the
// ring alone while the plays are still coming, or with why they never came.
class _Verdict extends StatelessWidget {
  const _Verdict(this.summary,
      {required this.cards, required this.spin, this.missing, this.goal});
  final SetSummary? summary;
  final int cards;
  final Animation<double> spin;
  final String? missing;
  final GoalProgress? goal;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final summary = this.summary;
    if (summary == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox.square(
            dimension: 250,
            child: Stack(alignment: Alignment.center, children: [
              RotationTransition(
                  turns: spin,
                  child: CustomPaint(
                      size: const Size.square(250),
                      painter: _RingPainter(pop.voltText))),
              Container(
                  width: 206,
                  height: 206,
                  decoration:
                      BoxDecoration(color: pop.riser, shape: BoxShape.circle)),
              Icon(missing == null ? Icons.style : Icons.hourglass_empty,
                  size: 56, color: pop.haze),
            ]),
          ),
          const SizedBox(height: 24),
          Transform(
              alignment: Alignment.center,
              transform: FloorPop.titleLean,
              child: Text(missing == null ? 'SESSION DONE' : 'NO PLAYS YET',
                  style: FloorPop.display(30, color: pop.voltText))),
          const SizedBox(height: 10),
          Text(missing ?? 'Reading your plays from e-amusement',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: pop.haze)),
        ]),
      );
    }
    final gap = summary.gap;
    final (headline, color) = switch (gap) {
      null => ('SESSION DONE', pop.voltText),
      >= _verdictGap => ('GREAT SET', pop.up),
      <= -_verdictGap => ('ROUGH ONE', pop.down),
      _ => ('RIGHT ON YOUR USUAL', pop.voltText),
    };
    final best = summary.byLevel.where((l) => l.plays >= 2).fold<LevelSummary?>(
        null,
        (b, l) =>
            b == null || l.average - l.usual > b.average - b.usual ? l : b);
    const ring = 270.0;
    return Center(
        child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox.square(
          dimension: ring,
          child: Stack(alignment: Alignment.center, children: [
            RotationTransition(
                turns: spin,
                child: CustomPaint(
                    size: const Size.square(ring),
                    painter: _RingPainter(color))),
            Container(
                width: ring - 44,
                height: ring - 44,
                decoration:
                    BoxDecoration(color: pop.riser, shape: BoxShape.circle)),
            Column(mainAxisSize: MainAxisSize.min, children: [
              if (gap != null)
                Icon(
                    gap >= _verdictGap
                        ? Icons.trending_up_rounded
                        : gap <= -_verdictGap
                            ? Icons.trending_down_rounded
                            : Icons.trending_flat_rounded,
                    size: 30,
                    color: color),
              if (gap == null)
                Text('${summary.points.length}',
                    style: FloorPop.readout(56, color: color))
              else
                TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: gap),
                    duration: const Duration(milliseconds: 1400),
                    curve: Curves.easeOutCubic,
                    // One line, shrinking to fit inside the disc.
                    builder: (context, v, _) => SizedBox(
                        width: ring - 84,
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                                '${v >= 0 ? '+' : '−'}${formatScore(v.abs().round())}',
                                maxLines: 1,
                                style: FloorPop.readout(52, color: color))))),
              const SizedBox(height: 8),
              Text(gap == null ? 'plays' : 'vs your usual',
                  style: TextStyle(fontSize: 13, color: pop.haze)),
            ]),
          ]),
        ),
        const SizedBox(height: 32),
        Transform(
            alignment: Alignment.center,
            transform: FloorPop.titleLean,
            child: Text(headline,
                textAlign: TextAlign.center,
                style: FloorPop.display(30, color: color))),
        const SizedBox(height: 24),
        // What went well, each in its own colour.
        Row(spacing: 8, children: [
          if (best != null && best.average > best.usual)
            _VerdictTile(
                label: 'BEST LEVEL',
                color: pop.up,
                fill: FloorPop.night.up,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  LevelNumber(
                      level: best.level, difficulty: 'EXPERT', height: 20),
                  const SizedBox(width: 6),
                  Flexible(
                      child: FittedBox(
                          child: Text(
                              '+${formatScore((best.average - best.usual).round())}',
                              style: FloorPop.readout(20, color: pop.up)))),
                ]))
          else
            _VerdictTile(
                label: 'PLAYS',
                color: pop.haze,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.music_note_rounded, size: 20, color: pop.haze),
                  const SizedBox(width: 4),
                  Text('${summary.points.length}',
                      style: FloorPop.readout(20, color: pop.haze)),
                ])),
          _VerdictTile(
              label: 'UPSCORES',
              color: summary.upscores > 0 ? pop.sunText : pop.haze,
              fill: summary.upscores > 0 ? FloorPop.sun : pop.haze,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                UpscoreBadge(
                    color: summary.upscores > 0 ? pop.sunText : pop.haze),
                const SizedBox(width: 6),
                Text('${summary.upscores}',
                    style: FloorPop.readout(20,
                        color: summary.upscores > 0 ? pop.sunText : pop.haze)),
              ])),
          if (cards > 0)
            _VerdictTile(
                label: 'CARDS',
                color: pop.voltText,
                fill: FloorPop.volt,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.style_rounded, size: 20, color: pop.voltText),
                  const SizedBox(width: 4),
                  Text('$cards',
                      style: FloorPop.readout(20, color: pop.voltText)),
                ])),
        ]),
        if (goal case final goal?) ...[
          const SizedBox(height: 30),
          GoalCard(
            goal: goal.goal,
            count: goal.count,
            stamp: goal.reached
                ? 'GOAL HIT'
                : goal.goal.target == null
                    ? null
                    : '${goal.goal.target! - goal.count} TO GO',
            footer: Text(goalSummary(goal),
                style: TextStyle(
                    color: goal.goal.kind.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    ));
  }
}

// One of the verdict's tiles: a tile washed in [color], its figure over a
// small caps label.
class _VerdictTile extends StatelessWidget {
  const _VerdictTile(
      {required this.label,
      required this.color,
      this.fill,
      required this.child});
  final String label;
  // Its text, and the bright colour its fill is tinted with (the text's
  // unless given; Day's text colours are too dark to tint with).
  final Color color;
  final Color? fill;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Expanded(
        child: Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
                color: Color.alphaBlend(
                    (fill ?? color).withValues(alpha: .16), pop.riser),
                borderRadius: BorderRadius.circular(14)),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(height: 24, child: FittedBox(child: child)),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: color.withValues(alpha: .8))),
            ])));
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawCircle(
        rect.center,
        size.width / 2,
        Paint()
          ..shader = SweepGradient(colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0),
            color.withValues(alpha: .35),
            color,
            Colors.white,
          ], stops: const [
            0,
            .55,
            .7,
            .96,
            1
          ]).createShader(rect));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}

/// The light a card's gains throw: its new frame's, gold for AAA, white for a
/// flare rank, else volt for a new card.
Color _glow(WrapCard card) {
  final layers = {for (final g in card.gains) g.layer};
  return layers.contains(CardLayer.frame)
      ? switch (card.best.lamp) {
          ClearLamp.mfc => Colors.white,
          ClearLamp.pfc => const Color(0xFFFFE3A0),
          ClearLamp.gfc => const Color(0xFFEAF1FA),
          _ => const Color(0xFFF2C394),
        }
      : layers.contains(CardLayer.finish)
          ? const Color(0xFFFFE98A)
          : layers.contains(CardLayer.aura)
              ? Colors.white
              : FloorPop.volt;
}

Object _heroTag(WrapCard card) => ('wrap', card.now.chart);

// Beat two: the whole haul dealt face up at once, like a pack torn open, each
// card flashing its glow as it lands. A card tapped opens on its own.
class _Pack extends StatefulWidget {
  const _Pack(this.cards, {required this.gains});
  final List<WrapCard> cards;
  final List<CardGain> gains;

  @override
  State<_Pack> createState() => _PackState();
}

class _PackState extends State<_Pack> with SingleTickerProviderStateMixin {
  final _landing = PackLanding.current;
  // The deal, then a tail for the last card's landing to play out.
  static const _tail = 600;
  late final _dealt = math.min(2600, 500 + 120 * widget.cards.length);
  late final _deal = AnimationController(
      vsync: this, duration: Duration(milliseconds: _dealt + _tail))
    ..addListener(_tick);
  int _landed = 0;
  // Each card's own subtree, kept whole as the layers round it come and go
  // so its jacket never reloads.
  late final _keys = [for (final _ in widget.cards) GlobalKey()];

  static const _gap = 10.0, _least = 72.0, _most = 180.0;

  Interval _interval(int i) {
    final n = widget.cards.length;
    final flight = n == 1 ? 1.0 : .4;
    final step = n == 1 ? 0.0 : (1 - flight) / (n - 1);
    final d = _dealt / (_dealt + _tail);
    return Interval(i * step * d, (i * step + flight) * d,
        curve: switch (_landing) {
          PackLanding.slam || PackLanding.flip => Curves.easeInCubic,
          _ => Curves.easeOutBack,
        });
  }

  // Milliseconds since card [i] landed, negative before.
  double _since(int i) => (_deal.value - _interval(i).end) * (_dealt + _tail);

  void _tick() {
    final landed = [
      for (var i = 0; i < widget.cards.length; i++)
        if (_deal.value >= _interval(i).end) i
    ].length;
    if (landed > _landed) {
      switch (_landing) {
        case PackLanding.slam || PackLanding.flip:
          HapticFeedback.heavyImpact();
        case PackLanding.shockwave:
          HapticFeedback.mediumImpact();
        case PackLanding.rise:
          HapticFeedback.lightImpact();
      }
    }
    _landed = landed;
  }

  // The pack jolts as each slammed card hits.
  Offset _shake(double side) {
    if (_landing != PackLanding.slam && _landing != PackLanding.flip) {
      return Offset.zero;
    }
    final since = [
      for (var i = 0; i < widget.cards.length; i++)
        if (_since(i) >= 0) _since(i)
    ].fold(double.infinity, math.min);
    // Flip's sheet knocks down once and springs back, no rattle.
    if (_landing == PackLanding.flip) {
      return since >= 140
          ? Offset.zero
          : Offset(0, side * .012 * math.sin(since / 140 * math.pi));
    }
    if (since >= 260) return Offset.zero;
    final amp = side * .035 * (1 - since / 260);
    return Offset(
        math.sin(since * .09) * amp, math.cos(since * .13) * amp * .6);
  }

  Widget _land(int i, WrapCard card, double side, Widget child) {
    final t = _interval(i).transform(_deal.value);
    final since = _since(i);
    // 1 as it lands, gone 450ms on.
    final hit = since < 0 ? 0.0 : 1 - (since / 450).clamp(0.0, 1.0);
    final glow = _glow(card);
    // A flash as it lands, settling to a glow.
    final lit = DecoratedBox(
        decoration:
            BoxDecoration(borderRadius: BorderRadius.circular(8), boxShadow: [
          if (t >= 1)
            BoxShadow(
                color: glow.withValues(alpha: .35 + .65 * hit),
                blurRadius: 10 + 14 * hit,
                spreadRadius: 1 + 5 * hit),
        ]),
        child: child);
    if (t <= 0) {
      return _landing == PackLanding.flip
          ? _CardBack(side)
          : Opacity(opacity: 0, child: child);
    }
    switch (_landing) {
      case PackLanding.rise:
        return Transform.translate(
            offset: Offset(0, (1 - t) * side * 1.6),
            child: Transform.rotate(
                angle: (1 - t) * (i.isEven ? -.3 : .3),
                child: Transform.scale(scale: .5 + .5 * t, child: lit)));
      case PackLanding.slam:
        // Falls at the screen from above, then squashes on the hit.
        final squash = since >= 0 && since < 220
            ? math.sin(since / 220 * math.pi) * .12
            : 0.0;
        final s = 2.6 - 1.6 * t;
        return Transform.scale(
            scaleX: s * (1 + squash),
            scaleY: s * (1 - squash),
            child: Transform.rotate(
                angle: (1 - t) * (i.isEven ? -.12 : .12), child: lit));
      case PackLanding.flip:
        // Laid out face down from the start, each turning over in place in
        // turn: it swells once on the reveal, throwing a ring out in its
        // glow, then sits still.
        final angle = (1 - t) * math.pi;
        final pop = since < 0 || since >= 220
            ? 0.0
            : .08 * math.sin(since / 220 * math.pi);
        final scale = 1 + pop;
        return Stack(clipBehavior: Clip.none, children: [
          Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0015)
                ..rotateY(angle)
                ..scaleByDouble(scale, scale, 1, 1),
              child: angle > math.pi / 2
                  ? _CardBack(side)
                  : CustomPaint(
                      foregroundPainter: since >= 0 && since < 600
                          ? ShockPainter(since / 600, glow)
                          : null,
                      child: Stack(children: [
                        lit,
                        Positioned.fill(
                            child: IgnorePointer(
                                child: DecoratedBox(
                                    decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: .8 * hit * hit),
                                        borderRadius:
                                            BorderRadius.circular(8))))),
                      ]))),
        ]);
      case PackLanding.shockwave:
        // Rises in, punches up on the hit and throws a ring out.
        return Transform.translate(
            offset: Offset(0, (1 - t) * side * 1.6),
            child: Transform.scale(
                scale: (.5 + .5 * t) * (1 + .1 * hit),
                child: CustomPaint(
                    foregroundPainter: since >= 0 && since < 600
                        ? ShockPainter(since / 600, glow)
                        : null,
                    child: lit)));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) _deal.value = 1;
      _deal.forward();
    });
  }

  @override
  void dispose() {
    _deal.dispose();
    super.dispose();
  }

  // The columns and side that show every card biggest, no smaller than
  // [_least] (scrolling past what fits then) nor bigger than [_most].
  ({int columns, double side}) _fit(Size box) {
    final n = widget.cards.length;
    var best = (columns: 1, side: 0.0);
    for (var c = 1; c <= n; c++) {
      final rows = (n / c).ceil();
      final side = math.min((box.width - (c - 1) * _gap) / c,
          (box.height - (rows - 1) * _gap) / rows);
      if (side > best.side) best = (columns: c, side: side);
    }
    if (best.side >= _least) {
      return (columns: best.columns, side: math.min(best.side, _most));
    }
    final columns = ((box.width + _gap) / (_least + _gap)).floor();
    return (
      columns: columns,
      side: (box.width - (columns - 1) * _gap) / columns
    );
  }

  void _open(int index) => Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      transitionDuration: FloorPop.beat,
      reverseTransitionDuration: FloorPop.beat,
      pageBuilder: (_, __, ___) => _CardPages(widget.cards, initial: index),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child)));

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: CardTally(widget.gains, height: 28),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final fit = _fit(Size(box.maxWidth - 32, box.maxHeight - 32));
          final side = fit.side;
          return Stack(alignment: Alignment.center, children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: AnimatedBuilder(
                  animation: _deal,
                  builder: (context, child) =>
                      Transform.translate(offset: _shake(side), child: child),
                  child: SizedBox(
                    width: fit.columns * side + (fit.columns - 1) * _gap,
                    child: Wrap(
                        spacing: _gap,
                        runSpacing: _gap,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final (i, card) in cards.indexed)
                            AnimatedBuilder(
                              animation: _deal,
                              builder: (context, child) =>
                                  _land(i, card, side, child!),
                              child: KeyedSubtree(
                                  key: _keys[i],
                                  child: _PackCard(card,
                                      side: side, onTap: () => _open(i))),
                            ),
                        ]),
                  ),
                ),
              ),
            ),
          ]);
        }),
      ),
    ]);
  }
}

/// How a card in the pack lands, picked on the development page.
// The first is the default.
enum PackLanding {
  flip('Flip'),
  rise('Rise'),
  slam('Slam'),
  shockwave('Shockwave');

  const PackLanding(this.label);
  final String label;

  static PackLanding get current => values[
      Settings.getInt(Settings.wrapLandingKey).clamp(0, values.length - 1)];
}

// A card dealt face down, before it turns over.
class _CardBack extends StatelessWidget {
  const _CardBack(this.side);
  final double side;

  @override
  Widget build(BuildContext context) => Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
          color: FloorPop.volt, borderRadius: BorderRadius.circular(8)),
      child:
          Icon(Icons.style_rounded, size: side * .4, color: FloorPop.onVolt));
}

/// A ring thrown out from a card as it lands, [t] 0 to 1 over its life.
class ShockPainter extends CustomPainter {
  ShockPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Curves.easeOutCubic.transform(t);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: size.center(Offset.zero),
                width: size.width * (1 + .35 * r),
                height: size.height * (1 + .35 * r)),
            Radius.circular(8 + 10 * r)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - r) + .5
          ..color = color.withValues(alpha: .7 * (1 - r)));
  }

  @override
  bool shouldRepaint(ShockPainter old) => old.t != t || old.color != color;
}

// A card in the pack, tagged NEW or UP.
class _PackCard extends StatelessWidget {
  const _PackCard(this.card, {required this.side, required this.onTap});
  final WrapCard card;
  final double side;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final fresh = card.before == null;
    final ink = math.max(9.0, side * .09);
    return Semantics(
      button: true,
      label: '${card.title} card, ${fresh ? 'new' : 'upgraded'}',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox.square(
          dimension: side,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
                child:
                    Hero(tag: _heroTag(card), child: _compact(card, card.now))),
            Positioned(
              left: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: fresh ? FloorPop.volt : pop.stage,
                    border: Border.all(color: FloorPop.volt, width: 1.5),
                    borderRadius: BorderRadius.circular(5)),
                child: Text(fresh ? 'NEW' : 'UP',
                    style: FloorPop.display(ink,
                        color: fresh ? FloorPop.onVolt : pop.voltText)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// A card opened from the pack, floating over it, with the rest a swipe
// either side. Tapping the pack around it closes.
class _CardPages extends StatefulWidget {
  const _CardPages(this.cards, {required this.initial});
  final List<WrapCard> cards;
  final int initial;

  @override
  State<_CardPages> createState() => _CardPagesState();
}

class _CardPagesState extends State<_CardPages> {
  late final _pages =
      PageController(initialPage: widget.initial, viewportFraction: .88);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).pop();
    // The card floats over the dimmed pack with no panel, which is dark
    // whatever the theme, so its text is Night's.
    return Theme(
      data: floorPopTheme(Brightness.dark),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: close,
              child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child:
                      ColoredBox(color: Colors.black.withValues(alpha: .72))),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: PageView.builder(
                  controller: _pages,
                  itemCount: widget.cards.length,
                  itemBuilder: (context, i) => AnimatedBuilder(
                      animation: _pages,
                      builder: (context, child) {
                        final page = _pages.position.haveDimensions
                            ? _pages.page!
                            : widget.initial.toDouble();
                        final off = (page - i).abs();
                        // Only the card in front shows and flies back to the
                        // pack; the ones beside it would leave their headers
                        // floating at the edges.
                        return HeroMode(
                            enabled: off < .5,
                            child: Opacity(
                                opacity: (1 - off).clamp(0.0, 1.0),
                                child: child));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _Deal(widget.cards, index: i, onClose: close),
                      ))),
            ),
          ),
        ]),
      ),
    );
  }
}

// One card on its own, beside what it was.
class _Deal extends StatelessWidget {
  const _Deal(this.cards, {required this.index, required this.onClose});
  final List<WrapCard> cards;
  final int index;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final card = cards[index];
    final fresh = card.before == null;
    final difficulty = card.gains.first.difficulty;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
        child: Row(children: [
          Transform(
            transform: FloorPop.lean,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: fresh ? FloorPop.volt : null,
                  border: Border.all(color: FloorPop.volt, width: 1.5),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(fresh ? 'NEW CARD' : 'UPGRADE',
                  style: FloorPop.display(13,
                      color: fresh ? FloorPop.onVolt : pop.voltText)),
            ),
          ),
          const Spacer(),
          IconButton(
              tooltip: 'Back to the pack',
              onPressed: onClose,
              icon: const Icon(Icons.close),
              style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: .16),
                  foregroundColor: Colors.white,
                  fixedSize: const Size(44, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)))),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final side = math.min(240.0, box.maxHeight - 40);
          return Stack(alignment: Alignment.center, children: [
            Hero(
              tag: _heroTag(card),
              child: SizedBox.square(
                dimension: side,
                child: Semantics(
                  label: '${card.title} card',
                  child: JacketEdition(
                      facts: card.now,
                      options: _cardOptions,
                      child: SongArtwork(
                          songName: card.now.chart.song,
                          title: card.title,
                          fullResolution: true)),
                ),
              ),
            ),
          ]);
        }),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          Text(card.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: FloorPop.display(20)),
          const SizedBox(height: 6),
          DifficultyLabel(
              difficulty: difficulty, level: card.level, height: 20),
          const SizedBox(height: 12),
          _Change(card),
        ]),
      ),
      const SizedBox(height: 14),
      PageDots(cards.length, index: index),
      const SizedBox(height: 16),
    ]);
  }
}

// Each gain from what the card showed to what it shows now, and its score
// with how far it rose; a new card shows what it came with.
class _Change extends StatelessWidget {
  const _Change(this.card);
  final WrapCard card;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    Widget badge(String? art, double aspect, {bool was = false}) => Opacity(
        opacity: was ? .5 : 1,
        child: ArtBadge(art, aspect: aspect, ink: 13, height: 24));
    final before = card.before;
    final best = card.best;
    final List<Widget> changes;
    if (before == null) {
      changes = [
        if (best.flare != null) badge(flareRankIcon(best.flare!), kFlareAspect),
        if (best.grade != null) badge(gradeIcon(best.grade!), kGradeAspect),
        if (clearLampIcon(best.lamp) case final l?) badge(l, kLampAspect),
      ];
    } else {
      changes = [
        for (final g in card.gains)
          Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            switch (g.layer) {
              CardLayer.finish => badge(
                  g.from.isEmpty
                      ? null
                      : gradeIcon(
                          Grade.values.firstWhere((v) => v.label == g.from)),
                  kGradeAspect,
                  was: true),
              CardLayer.frame => badge(
                  clearLampIcon(ClearLamp.values.asNameMap()[g.from]),
                  kLampAspect,
                  was: true),
              _ => badge(
                  g.from.isEmpty ? null : flareRankIcon(g.from), kFlareAspect,
                  was: true),
            },
            Icon(Icons.arrow_forward, size: 16, color: pop.voltText),
            switch (g.layer) {
              CardLayer.finish => badge(gradeIcon(Grade.aaa), kGradeAspect),
              CardLayer.frame => badge(
                  clearLampIcon(ClearLamp.values.byName(g.to)), kLampAspect),
              _ => badge(flareRankIcon(g.to), kFlareAspect),
            },
          ]),
      ];
    }
    final rise = switch ((before?.score, best.score)) {
      (final was?, final now?) when now > was => now - was,
      _ => null,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: pop.riser.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Expanded(
          child: Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: changes),
        ),
        if (best.score case final s?)
          Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatScore(s), style: FloorPop.readout(17)),
                if (rise != null)
                  Text('+${formatScore(rise)}',
                      style: FloorPop.readout(13, color: pop.voltText)),
              ]),
      ]),
    );
  }
}

/// How many of [gains]' cards are new and how many upgraded; the cards
/// themselves show what each gained.
class CardTally extends StatelessWidget {
  const CardTally(this.gains,
      {super.key, this.height = 26, this.alignment = WrapAlignment.center});
  final List<CardGain> gains;
  final double height;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final ink = height * .42;
    final cards = wrapCards(gains);
    final fresh = cards.where((c) => c.before == null).length;
    // Statistics' tiles: the label and its count in one, sized to fit both.
    final count = TextStyle(
        fontSize: height * .46,
        height: 1,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()]);
    return Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: alignment,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (label, n) in [
            ('NEW', fresh),
            ('UP', cards.length - fresh),
          ])
            if (n > 0)
              () {
                final style = FloorPop.display(ink, color: pop.voltText);
                double wide(String text, TextStyle style) => (TextPainter(
                        text: TextSpan(text: text, style: style),
                        textDirection: TextDirection.ltr)
                      ..layout())
                    .width;
                // The tile gives its label two thirds of the row, so the
                // label sets the width; the count only widens it past that.
                final inner = math.max(wide(label, style) * 1.5,
                    wide(label, style) + 4 + wide('$n', count));
                return ArtTile(null,
                    aspect: 0,
                    ink: ink,
                    width: inner + 14,
                    height: height,
                    color: pop.voltText,
                    label: Text(label, style: style),
                    trailing: Text('$n', style: count));
              }(),
          if (gains.isEmpty)
            Text('No cards', style: TextStyle(color: pop.haze)),
        ]);
  }
}

/// A session's cards as one of its summary's tiles: a few of them stacked,
/// how many, and how many are new or upgraded. Tapped, it opens the wrap.
class CollectedTile extends StatelessWidget {
  const CollectedTile(this.gains, {super.key, this.onTap});
  final List<CardGain> gains;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cards = wrapCards(gains);
    final stack = cards.take(3).toList();
    const side = 30.0;
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(children: [
            SizedBox(
              width: side + (stack.length - 1) * 12 + 4,
              height: side + 6,
              child: Stack(clipBehavior: Clip.none, children: [
                for (final (i, card) in stack.indexed.toList().reversed)
                  Positioned(
                    left: i * 12.0,
                    top: 3,
                    child: Transform.rotate(
                      angle: (i - (stack.length - 1) / 2) * .14,
                      child: SizedBox.square(
                          dimension: side, child: _compact(card, card.now)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Cards',
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              Text('${cards.length}', style: FloorPop.readout(17)),
            ]),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                  alignment: Alignment.centerRight,
                  child: CardTally(gains,
                      height: 22, alignment: WrapAlignment.end)),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

/// Home's way in after a sync brings [visit] new plays: tapped, it opens the
/// wrap; either way it's gone until the next such sync.
class SessionWrapBanner extends StatefulWidget {
  const SessionWrapBanner(
      {super.key,
      required this.visit,
      required this.summary,
      required this.gains,
      this.preview = false});

  final Visit visit;
  final SetSummary summary;
  final List<CardGain> gains;

  /// Held up from Development: it stays, however often it's opened.
  final bool preview;

  /// Whether a sync left [visit] new plays to wrap.
  static bool waiting(Visit visit) {
    final since =
        DateTime.tryParse(Settings.getString(Settings.sessionWrapSinceKey));
    return since != null &&
        visit.session != null &&
        visit.plays.any((p) => p.playedAt.isAfter(since));
  }

  @override
  State<SessionWrapBanner> createState() => _SessionWrapBannerState();
}

class _SessionWrapBannerState extends State<SessionWrapBanner> {
  bool _gone = false;

  Future<void> _clear() async {
    if (widget.preview) {
      await Settings.setInt(Settings.wrapBannerPreviewKey, 0);
      wrapBannerPreview.value = false;
      return;
    }
    setState(() => _gone = true);
    await Settings.setString(Settings.sessionWrapSinceKey, '');
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final gap = widget.summary.gap;
    final cards = wrapCards(widget.gains).length;
    return BeatIn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: VoltButton(
          height: 64,
          radius: 20,
          onPressed: () {
            if (!widget.preview) _clear();
            showSessionWrap(context,
                visit: widget.visit,
                summary: widget.summary,
                gains: widget.gains);
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Row(children: [
              const Icon(Icons.style, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Session wrapped',
                          style: FloorPop.display(16, color: FloorPop.onVolt)),
                      Text(
                          [
                            // A set no session covers, held up from Development.
                            widget.visit.session?.venue.name ?? 'Last set',
                            if (gap != null)
                              '${gap >= 0 ? '+' : '−'}${formatScore(gap.abs().round())}',
                            if (cards > 0)
                              '$cards ${cards == 1 ? 'card' : 'cards'}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: FloorPop.onVolt)),
                    ]),
              ),
              // Dismissed from inside the banner, the rest of it opening the wrap.
              IconButton(
                  tooltip: 'Dismiss',
                  onPressed: _clear,
                  color: FloorPop.onVolt,
                  icon: const Icon(Icons.close)),
            ]),
          ),
        ),
      ),
    );
  }
}
