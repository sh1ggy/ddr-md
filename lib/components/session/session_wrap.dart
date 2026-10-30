/// Name: SessionWrap
/// Parent: LastSessionCard, VisitPage
/// Description: A session told once a sync lands its plays: how it went
/// against your usual, then each card its plays collected or upgraded dealt
/// one at a time beside what it was, then into the binder, where they slot
/// into their pockets. Home offers it from a banner after a
/// sync brings a session new plays; the session's Collected row opens it
/// again.
library;

import 'dart:math' as math;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/session/recent_plays.dart';
import 'package:ddr_md/components/session/session_summary.dart';
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
import 'package:ddr_md/helpers.dart'
    show formatScore, kFlareRanks, kInGameDifficultyNames;
import 'package:ddr_md/models/card_gains.dart';
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/version_group.dart';
import 'package:ddr_md/models/visit_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
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
                  score: best.score,
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

typedef _Tally = ({String? art, double aspect, int count});

/// Each kind of gain with how many: new cards first, then AAA, lamps and
/// flare ranks, best first.
List<_Tally> _tally(List<CardGain> gains) {
  final counts = <String?, ({double aspect, int count})>{};
  void add(String? art, double aspect) =>
      counts[art] = (aspect: aspect, count: (counts[art]?.count ?? 0) + 1);
  final sorted = [...gains]..sort((a, b) {
      if (a.layer != b.layer) return a.layer.index - b.layer.index;
      return switch (a.layer) {
        CardLayer.frame => ClearLamp.values.byName(b.to).index -
            ClearLamp.values.byName(a.to).index,
        CardLayer.aura => kFlareRanks.indexOf(b.to) - kFlareRanks.indexOf(a.to),
        _ => 0,
      };
    });
  for (final g in sorted) {
    switch (g.layer) {
      case CardLayer.card:
        add(null, 0);
      case CardLayer.finish:
        add(gradeIcon(Grade.aaa), kGradeAspect);
      case CardLayer.frame:
        add(clearLampIcon(ClearLamp.values.byName(g.to)), kLampAspect);
      case CardLayer.aura:
        add(flareRankIcon(g.to), kFlareAspect);
    }
  }
  return [
    for (final MapEntry(:key, :value) in counts.entries)
      (art: key, aspect: value.aspect, count: value.count)
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

/// Opens the wrap of [visit], whose plays made [gains].
Future<void> showSessionWrap(BuildContext context,
        {required Visit visit,
        required SetSummary summary,
        required List<CardGain> gains}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            SessionWrapPage(visit: visit, summary: summary, gains: gains)));

class SessionWrapPage extends StatefulWidget {
  const SessionWrapPage(
      {super.key,
      required this.visit,
      required this.summary,
      required this.gains});

  final Visit visit;
  final SetSummary summary;
  final List<CardGain> gains;

  @override
  State<SessionWrapPage> createState() => _SessionWrapPageState();
}

class _SessionWrapPageState extends State<SessionWrapPage>
    with TickerProviderStateMixin {
  late final _cards = wrapCards(widget.gains);
  // 0 how it went, 1 the cards; then the binder they go into.
  int _beat = 0;
  int _card = 0;
  late final _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 14))
        ..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _next() {
    if (_beat == 1 && _card < _cards.length - 1) {
      setState(() => _card++);
    } else if (_beat == 0 && _cards.isEmpty) {
      Navigator.of(context).pop();
    } else if (_beat == 1) {
      _intoBinder();
    } else {
      setState(() => _beat++);
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
        pageBuilder: (_, __, ___) => EditionBinderPage(
                level: cards.first.level,
                song: cards.first.now.chart.song,
                difficulty: cards.first.gains.first.difficulty,
                arrivals: {
                  for (final c in cards)
                    (
                      song: c.now.chart.song,
                      difficulty: c.gains.first.difficulty
                    ): c.before,
                },
                haul: [
                  for (final g in widget.gains)
                    if (g.mode == mode) g
                ]),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child)));
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final visit = widget.visit;
    final n = _cards.length;
    final action = switch (_beat) {
      0 when n == 0 => 'Done',
      0 => 'Deal your ${n == 1 ? 'card' : '$n cards'}',
      1 when _card < n - 1 => 'Next card',
      _ => 'Into the binder',
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
                      const SizedBox(height: 2),
                      Text(
                          [
                            if (visit.session case final s?) s.venue.name,
                            visitSpan(visit.start, visit.end),
                            playCount(visit.plays.length),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: pop.haze)),
                    ]),
              ),
              if (_beat == 1)
                TextButton(onPressed: _intoBinder, child: const Text('Skip'))
              else
                IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(spacing: 6, children: [
              for (var i = 0; i < (n == 0 ? 1 : 3); i++)
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
              child: KeyedSubtree(
                key: ValueKey(_beat),
                child: switch (_beat) {
                  0 => _Verdict(widget.summary, cards: n, spin: _spin),
                  _ => _Deal(_cards, index: _card, spin: _spin),
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              VoltButton(
                  onPressed: _next,
                  child: Text(action, style: FloorPop.display(16))),
            ]),
          ),
        ]),
      ),
    );
  }
}

// Beat one: the gap from your usual, counting up inside a spinning ring.
class _Verdict extends StatelessWidget {
  const _Verdict(this.summary, {required this.cards, required this.spin});
  final SetSummary summary;
  final int cards;
  final Animation<double> spin;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
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
    final muted = TextStyle(fontSize: 15, color: pop.haze);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox.square(
          dimension: 250,
          child: Stack(alignment: Alignment.center, children: [
            RotationTransition(
                turns: spin,
                child: CustomPaint(
                    size: const Size.square(250),
                    painter: _RingPainter(color))),
            Container(
                width: 206,
                height: 206,
                decoration:
                    BoxDecoration(color: pop.riser, shape: BoxShape.circle)),
            Column(mainAxisSize: MainAxisSize.min, children: [
              if (gap == null)
                Text('${summary.points.length}',
                    style: FloorPop.readout(56, color: color))
              else
                TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: gap),
                    duration: const Duration(milliseconds: 1400),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Text(
                        '${v >= 0 ? '+' : '−'}${formatScore(v.abs().round())}',
                        style: FloorPop.readout(52, color: color))),
              const SizedBox(height: 4),
              Text(gap == null ? 'plays' : 'vs your usual',
                  style: TextStyle(fontSize: 13, color: pop.haze)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
        Transform(
            alignment: Alignment.center,
            transform: FloorPop.titleLean,
            child: Text(headline,
                textAlign: TextAlign.center,
                style: FloorPop.display(30, color: color))),
        const SizedBox(height: 10),
        if (best != null && best.average > best.usual)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Best at ', style: muted),
            LevelNumber(level: best.level, difficulty: 'EXPERT', height: 18),
            Text(', ${formatScore((best.average - best.usual).round())} up',
                style: muted),
          ]),
        const SizedBox(height: 4),
        Text(
            [
              '${summary.upscores} ${summary.upscores == 1 ? 'upscore' : 'upscores'}',
              if (cards > 0)
                '$cards ${cards == 1 ? 'card' : 'cards'} collected',
            ].join(' · '),
            style: muted),
      ]),
    );
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

// Beat two: one card at a time, over rays in what it gained, beside what it
// was.
class _Deal extends StatelessWidget {
  const _Deal(this.cards, {required this.index, required this.spin});
  final List<WrapCard> cards;
  final int index;
  final Animation<double> spin;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final card = cards[index];
    final fresh = card.before == null;
    final layers = {for (final g in card.gains) g.layer};
    final glow = layers.contains(CardLayer.frame)
        ? switch (card.best.lamp) {
            ClearLamp.mfc => Colors.white,
            ClearLamp.pfc => const Color(0xFFFFE3A0),
            ClearLamp.gfc => const Color(0xFFC8F5CF),
            _ => const Color(0xFFEAF1FA),
          }
        : layers.contains(CardLayer.finish)
            ? const Color(0xFFFFE98A)
            : layers.contains(CardLayer.aura)
                ? Colors.white
                : FloorPop.volt;
    final difficulty = card.gains.first.difficulty;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
          Text('${index + 1} / ${cards.length}',
              style: FloorPop.readout(18, color: pop.haze)),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final side = math.min(240.0, box.maxHeight - 40);
          return Stack(alignment: Alignment.center, children: [
            RotationTransition(
                turns: spin,
                child: CustomPaint(
                    size: Size.square(side * 1.8),
                    painter: _RaysPainter(glow))),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 650),
              switchInCurve: FloorPop.step,
              transitionBuilder: (child, a) => AnimatedBuilder(
                animation: a,
                child: child,
                builder: (context, child) => Opacity(
                  opacity: a.value.clamp(0, 1),
                  child: Transform.translate(
                    offset: Offset(0, (1 - a.value) * 140),
                    child: Transform.rotate(
                        angle: (1 - a.value) * -.25,
                        child: Transform.scale(
                            scale: .6 + .4 * a.value, child: child)),
                  ),
                ),
              ),
              child: SizedBox.square(
                key: ValueKey(index),
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
      Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
        for (var i = 0; i < cards.length; i++)
          AnimatedContainer(
              duration: FloorPop.eighth,
              width: i == index ? 18 : 8,
              height: 8,
              decoration: BoxDecoration(
                  color: i <= index ? FloorPop.volt : pop.line,
                  borderRadius: BorderRadius.circular(4))),
      ]),
    ]);
  }
}

// What the card was (an empty pocket for a new one), and each gain from
// what it showed to what it shows now; a new card shows what it came with.
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: pop.riser, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        SizedBox.square(
          dimension: 48,
          child: before == null
              ? DecoratedBox(
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: pop.line, width: 2)),
                  child: Icon(Icons.add, color: pop.haze))
              : _compact(card, before),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: changes),
        ),
        if (best.score case final s?)
          Text(formatScore(s), style: FloorPop.readout(17)),
      ]),
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final paint = Paint()
      ..shader = RadialGradient(colors: [
        color.withValues(alpha: .3),
        color.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: c, radius: r));
    const rays = 20;
    for (var i = 0; i < rays; i++) {
      final a = i * 2 * math.pi / rays;
      canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy)
            ..lineTo(c.dx + r * math.cos(a), c.dy + r * math.sin(a))
            ..lineTo(c.dx + r * math.cos(a + .1), c.dy + r * math.sin(a + .1))
            ..close(),
          paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.color != color;
}

/// A badge per kind of gain in [gains], with its count.
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
    return Wrap(
        spacing: 10,
        runSpacing: 6,
        alignment: alignment,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in _tally(gains))
            Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
              if (t.art == null)
                Container(
                  height: height * .8,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: FloorPop.volt,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('NEW',
                      style: FloorPop.display(ink, color: FloorPop.onVolt)),
                )
              else
                ArtBadge(t.art, aspect: t.aspect, ink: ink, height: height),
              Text('×${t.count}',
                  style: FloorPop.readout(height * .5,
                      color: Theme.of(context).colorScheme.onSurface)),
            ]),
          if (gains.isEmpty)
            Text('No cards', style: TextStyle(color: pop.haze)),
        ]);
  }
}

/// A session's cards as one of its summary's tiles: a few of them stacked,
/// how many, and a badge for each kind of gain. Tapped, it opens the wrap.
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
      required this.gains});

  final Visit visit;
  final SetSummary summary;
  final List<CardGain> gains;

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
        child: Row(children: [
          Expanded(
            child: VoltButton(
              height: 64,
              radius: 20,
              onPressed: () {
                _clear();
                showSessionWrap(context,
                    visit: widget.visit,
                    summary: widget.summary,
                    gains: widget.gains);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Icon(Icons.style, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Session wrapped',
                              style:
                                  FloorPop.display(16, color: FloorPop.onVolt)),
                          Text(
                              [
                                widget.visit.session!.venue.name,
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
                  const Icon(Icons.chevron_right),
                ]),
              ),
            ),
          ),
          IconButton(
              tooltip: 'Dismiss',
              onPressed: _clear,
              icon: const Icon(Icons.close)),
        ]),
      ),
    );
  }
}
