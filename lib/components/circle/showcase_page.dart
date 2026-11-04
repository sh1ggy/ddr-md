/// Name: ShowcasePage
/// Parent: CirclePage, CirclePersonPage
/// Description: Three best cards shown to a circle, and the shelf that picks them.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart' show sha256;
import 'package:ddr_md/components/circle/circle_credit_card.dart';
import 'package:ddr_md/components/circle/circle_page.dart' show CircleBubble;
import 'package:ddr_md/components/circle/circle_widgets.dart' show DdrCodeBadge;
import 'package:ddr_md/components/session/recent_plays.dart' show chartOf;
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/compact_jacket_edition.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/helpers.dart' show formatScore, kInGameDifficultyNames;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/showcase.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ShowcasePage extends StatelessWidget {
  const ShowcasePage({super.key, required this.person});
  final CirclePerson person;
  @override
  Widget build(BuildContext context) {
    final circle = context.watch<CircleState>();
    final own = circle.id == person.id;
    final credits = own ? circle.yours : circle.lastSessionOf(person);
    final pop = FloorPop.of(context);
    return Scaffold(
        appBar: AppBar(),
        body: RefreshIndicator(
            onRefresh: circle.refresh,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  Container(
                      padding: const EdgeInsets.all(16),
                      decoration: pop.stripes(
                          color: pop.stage, radius: BorderRadius.circular(26)),
                      child: Row(children: [
                        CircleBubble(person, size: 56),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(person.name, style: FloorPop.display(22)),
                              const SizedBox(height: 8),
                              DdrCodeBadge(person.ddrCode),
                              if (!own) ...[
                                const SizedBox(height: 8),
                                Text(
                                    person.friend
                                        ? 'FRIENDS'
                                        : 'IN THEIR CIRCLE',
                                    style: TextStyle(
                                        color: pop.haze, fontSize: 12)),
                              ],
                            ]))
                      ])),
                  CircleShowcase(person: person, revision: circle.feedRevision),
                  if (credits.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('LAST SESSION', style: pop.label),
                    const SizedBox(height: 10),
                    CircleSessionCard(credits
                        .where((c) => c.session == credits.first.session)
                        .toList())
                  ],
                ])));
  }
}

/// The showcase on a person's page. A refresh replaces even a previous
/// success with an access error when a membership has been revoked.
class CircleShowcase extends StatefulWidget {
  const CircleShowcase({super.key, required this.person, this.revision = 0});
  final CirclePerson person;
  final int revision;
  @override
  State<CircleShowcase> createState() => _CircleShowcaseState();
}

class _CircleShowcaseState extends State<CircleShowcase> {
  List<ShowcaseCard?>? _cards;
  String? _error;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CircleShowcase oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.person.id != widget.person.id ||
        oldWidget.revision != widget.revision) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final cards =
          await context.read<CircleState>().loadShowcase(widget.person.id);
      if (mounted && request == _request) {
        setState(() {
          _cards = cards;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _cards = null;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final circle = context.watch<CircleState>();
    final own = circle.id == widget.person.id;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) ...[
        Text(_error!),
        TextButton(onPressed: _load, child: const Text('Try again'))
      ] else if (_cards == null)
        const Center(child: CircularProgressIndicator())
      else
        Stack(children: [
          ShowcaseDisplay(cards: _cards!),
          if (own)
            Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                    tooltip: 'Edit cards',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ShowcasePickerPage()));
                      if (mounted) {
                        await _load();
                      }
                    })),
        ]),
    ]);
  }
}

class ShowcaseDisplay extends StatefulWidget {
  const ShowcaseDisplay({super.key, required this.cards});
  final List<ShowcaseCard?> cards;
  @override
  State<ShowcaseDisplay> createState() => _ShowcaseDisplayState();
}

class _ShowcaseDisplayState extends State<ShowcaseDisplay> {
  int _active = 0;
  @override
  Widget build(BuildContext context) {
    final cards = widget.cards.whereType<ShowcaseCard>().toList();
    if (cards.isEmpty) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text('No cards yet', textAlign: TextAlign.center));
    }
    _active = _active.clamp(0, cards.length - 1);
    return _CardFan(
        cards: cards,
        active: _active,
        onPick: (i) => setState(() => _active = i));
  }
}

class _CardArt extends StatelessWidget {
  const _CardArt(this.card);
  final ShowcaseCard card;
  @override
  Widget build(BuildContext context) {
    final chart = chartOf(card.song, card.mode, card.difficulty);
    final difficulty = kInGameDifficultyNames.entries
            .where((entry) => entry.value == card.difficulty)
            .firstOrNull
            ?.key ??
        card.difficulty;
    return CompactJacketEdition(
        facts: EditionFacts(
            chart: (
              song: card.song,
              mode: card.mode.name,
              difficulty: difficulty
            ),
            level: chart.level,
            score: card.best.score,
            grade: card.best.grade,
            lamp: card.best.lamp,
            flare: card.best.flare),
        options: editionPreferences(),
        fitChart: true,
        flareStamp: true,
        child: SongArtwork(
            songName: card.song, title: chart.song?.title ?? card.song));
  }
}

class _CardFan extends StatelessWidget {
  const _CardFan(
      {required this.cards,
      required this.active,
      required this.onPick,
      this.editor = false,
      this.onClear});
  final List<ShowcaseCard?> cards;
  final int active;
  final ValueChanged<int> onPick;
  final bool editor;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final width = box.maxWidth.clamp(0.0, 520.0);
        final height = width * .78;
        final size = width * .58;
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 420);
        final others = [
          for (var i = 0; i < cards.length; i++)
            if (i != active) i
        ];
        return SizedBox(
            height: height,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                  child: IgnorePointer(
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: RadialGradient(colors: [
                FloorPop.volt.withValues(alpha: editor ? .08 : .14),
                Colors.transparent
              ], radius: .65))))),
              for (final i in [...others, active])
                if (i < cards.length)
                  Builder(
                      key: ValueKey(i),
                      builder: (context) {
                        final on = i == active;
                        final side = on
                            ? 0
                            : others.indexOf(i) == 0
                                ? -1
                                : 1;
                        final card = cards[i];
                        return AnimatedPositioned(
                            key: ValueKey(i),
                            duration: duration,
                            curve: Curves.easeInOutCubic,
                            left: (box.maxWidth - size) / 2 + side * size * .34,
                            top: (height - size) / 2 + (on ? 0 : size * .08),
                            width: size,
                            height: size,
                            child: AnimatedRotation(
                                turns: side * .027,
                                duration: duration,
                                curve: Curves.easeInOutCubic,
                                child: AnimatedScale(
                                    scale: on ? 1 : .9,
                                    duration: duration,
                                    curve: Curves.easeInOutCubic,
                                    child: Semantics(
                                        key: ValueKey('showcase-slot-$i'),
                                        button: true,
                                        selected: on,
                                        label:
                                            'Card ${i + 1}: ${card?.song ?? 'empty'}',
                                        child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => onPick(i),
                                            onHorizontalDragEnd: (details) {
                                              final speed =
                                                  details.primaryVelocity ?? 0;
                                              if (speed.abs() > 80) {
                                                onPick((active +
                                                        (speed < 0 ? 1 : -1)) %
                                                    cards.length);
                                              }
                                            },
                                            child: Container(
                                                padding:
                                                    const EdgeInsets.all(3),
                                                decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                    border: on && editor
                                                        ? Border.all(
                                                            color:
                                                                FloorPop.volt,
                                                            width: 2)
                                                        : null),
                                                child: card == null
                                                    ? DecoratedBox(
                                                        decoration: BoxDecoration(
                                                            color: FloorPop.of(context)
                                                                .stage,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                    10),
                                                            border: Border.all(
                                                                color: FloorPop.of(context)
                                                                    .haze)),
                                                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                          const Icon(Icons.add),
                                                          Text('CARD ${i + 1}')
                                                        ]))
                                                    : Stack(
                                                        fit: StackFit.expand,
                                                        clipBehavior: Clip.none,
                                                        children: [
                                                            _CardArt(card),
                                                            if (editor)
                                                              Positioned(
                                                                  left: 4,
                                                                  bottom: 4,
                                                                  child: CircleAvatar(
                                                                      radius:
                                                                          12,
                                                                      backgroundColor:
                                                                          FloorPop
                                                                              .volt,
                                                                      child: Text(
                                                                          '${i + 1}',
                                                                          style:
                                                                              const TextStyle(color: FloorPop.onVolt)))),
                                                            if (on &&
                                                                onClear != null)
                                                              Positioned(
                                                                  top: 4,
                                                                  right: 4,
                                                                  child: IconButton.filled(
                                                                      tooltip:
                                                                          'Take this card out',
                                                                      onPressed:
                                                                          onClear,
                                                                      icon: const Icon(
                                                                          Icons
                                                                              .close))),
                                                          ])))))));
                      })
            ]));
      });
}

class ShowcasePickerPage extends StatefulWidget {
  const ShowcasePickerPage({super.key});
  @override
  State<ShowcasePickerPage> createState() => _ShowcasePickerPageState();
}

class _ShowcasePickerPageState extends State<ShowcasePickerPage> {
  List<ShowcaseCard?> _slots = [null, null, null];
  List<ShowcaseCard> _bests = [];
  final _levels = <String, int>{};
  int _active = 0;
  String _sort = 'Hardest';
  bool _loading = true, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final circle = context.read<CircleState>();
      final slots = await circle.loadShowcase(circle.id!);
      final dates = <String, DateTime>{};
      for (final mode in Modes.values) {
        final records = await DatabaseProvider.getScoreRecordsByMode(mode);
        for (final r in records) {
          final key = jsonEncode([r.song, mode.name, r.difficulty, r.score]);
          final at = r.playedAt;
          if (at == null) continue;
          if (dates[key] == null || at.isBefore(dates[key]!)) dates[key] = at;
        }
        await ChartBests.ensure(mode);
      }
      for (final r in await DatabaseProvider.getAllScores()) {
        final song = Songs.list
            .where((s) =>
                (s.titletranslit.isEmpty ? s.title : s.titletranslit) ==
                r.songTitle)
            .firstOrNull;
        if (song == null) continue;
        final key = jsonEncode([song.name, r.mode.name, r.difficulty, r.score]);
        final at = DateTime.tryParse(r.playedAt);
        if (at != null && (dates[key] == null || at.isBefore(dates[key]!))) {
          dates[key] = at;
        }
      }
      final bests = <ShowcaseCard>[];
      for (final mode in Modes.values) {
        for (final song in ChartBests.bestsOf(mode).entries) {
          for (final chart in song.value.entries) {
            if (chart.value.score == null) continue;
            final key = jsonEncode([song.key, mode.name, chart.key]);
            final id = sha256.convert(utf8.encode(key)).toString();
            _levels[id] = chartOf(song.key, mode, chart.key).level ?? 0;
            bests.add(ShowcaseCard(
                id: id,
                song: song.key,
                mode: mode,
                difficulty: chart.key,
                best: chart.value,
                playedAt: dates[jsonEncode(
                    [song.key, mode.name, chart.key, chart.value.score])]));
          }
        }
      }
      if (mounted) {
        setState(() {
          _slots = slots;
          _bests = bests;
          _loading = false;
          _active = slots.indexWhere((c) => c == null);
          if (_active < 0) {
            _active = 0;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _select(int i) => setState(() {
        _active = i;
      });
  void _place(ShowcaseCard card) => setState(() {
        final was = _slots.indexWhere((c) =>
            c?.song == card.song &&
            c?.mode == card.mode &&
            c?.difficulty == card.difficulty);
        final chosen = was < 0 ? card : _slots[was]!;
        if (was >= 0) _slots[was] = _slots[_active];
        _slots[_active] = chosen;
        final empty = _slots.indexWhere((c) => c == null);
        if (empty >= 0) _active = empty;
      });
  Future<void> _save() async {
    setState(() => _saving = true);
    final circle = context.read<CircleState>();
    final ok = await circle.saveShowcase(_slots);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(circle.error)));
    }
  }

  int _level(ShowcaseCard c) => _levels[c.id] ?? 0;
  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final bests = [..._bests]..sort((a, b) {
        final primary = switch (_sort) {
          'Lamp' =>
            (b.best.lamp?.index ?? 0).compareTo(a.best.lamp?.index ?? 0),
          'Recent' =>
            (b.playedAt ?? DateTime(0)).compareTo(a.playedAt ?? DateTime(0)),
          _ => _level(b).compareTo(_level(a)),
        };
        return primary != 0 ? primary : _level(b).compareTo(_level(a));
      });
    final active = _slots[_active];
    return Scaffold(
        appBar: AppBar(actions: [
          Center(child: Text('${_slots.whereType<ShowcaseCard>().length} / 3')),
          const SizedBox(width: 16)
        ]),
        bottomNavigationBar: _loading || _error != null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.all(16),
                child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Show my circle'))),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: const Text('Try again'))
                  ]))
                : CustomScrollView(slivers: [
                    SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              _CardFan(
                                  cards: _slots,
                                  active: _active,
                                  onPick: _saving ? (_) {} : _select,
                                  editor: true,
                                  onClear: active == null || _saving
                                      ? null
                                      : () => setState(
                                          () => _slots[_active] = null)),
                              const SizedBox(height: 16),
                              Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text('YOUR BESTS', style: pop.label),
                                    SegmentedButton<String>(
                                        segments: [
                                          for (final sort in [
                                            'Hardest',
                                            'Lamp',
                                            'Recent'
                                          ])
                                            ButtonSegment(
                                                value: sort, label: Text(sort))
                                        ],
                                        selected: {
                                          _sort
                                        },
                                        showSelectedIcon: false,
                                        onSelectionChanged: (s) =>
                                            setState(() => _sort = s.first))
                                  ]),
                              const SizedBox(height: 16),
                              if (bests.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                        'Sync e-amusement or save a score to collect your first card.')),
                            ]))),
                    SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 16,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: .70),
                            delegate: SliverChildBuilderDelegate((context, i) {
                              final c = bests[i];
                              final at = _slots.indexWhere((s) =>
                                  s?.song == c.song &&
                                  s?.mode == c.mode &&
                                  s?.difficulty == c.difficulty);
                              return Semantics(
                                  button: true,
                                  key: ValueKey(
                                      'showcase-best-${c.mode.name}:${c.song}:${c.difficulty}'),
                                  label:
                                      '${c.song}, ${c.mode.name}, ${c.difficulty}, ${c.best.score}',
                                  child: InkWell(
                                      onTap: _saving ? null : () => _place(c),
                                      child: Column(children: [
                                        AspectRatio(
                                            aspectRatio: 1,
                                            child: Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  Positioned.fill(
                                                      child: _CardArt(c)),
                                                  if (at >= 0)
                                                    Positioned(
                                                        top: 0,
                                                        left: 0,
                                                        child: CircleAvatar(
                                                            radius: 12,
                                                            backgroundColor:
                                                                FloorPop.volt,
                                                            child: Text(
                                                                '${at + 1}',
                                                                style: const TextStyle(
                                                                    color: FloorPop
                                                                        .onVolt))))
                                                ])),
                                        const SizedBox(height: 8),
                                        Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (_level(c) > 0)
                                                LevelNumber(
                                                    level: _level(c),
                                                    difficulty: c.difficulty,
                                                    height: 13),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                  child: Text(
                                                      formatScore(
                                                          c.best.score!),
                                                      style:
                                                          FloorPop.readout(13)))
                                            ]),
                                      ])));
                            }, childCount: bests.length))),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ]));
  }
}
