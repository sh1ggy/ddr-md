/// Name: ShowcasePage
/// Parent: CirclePage, CirclePersonPage
/// Description: Three best cards shown to a circle, and the shelf that picks them.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart' show sha256;
import 'package:ddr_md/components/circle/circle_credit_card.dart';
import 'package:ddr_md/components/circle/circle_page.dart' show CircleBubble;
import 'package:ddr_md/components/session/recent_plays.dart' show chartOf;
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/compact_jacket_edition.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/components/songlist/flare_card.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/helpers.dart' show formatScore;
import 'package:ddr_md/models/chart_bests.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/database.dart';
import 'package:ddr_md/models/showcase.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/router.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
        appBar: AppBar(title: const Text('Showcase')),
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
                              Text(formatDdrCode(person.ddrCode)),
                              Text(
                                  own
                                      ? 'Your page, as your circle sees it'
                                      : person.friend
                                          ? 'FRIENDS'
                                          : 'IN THEIR CIRCLE',
                                  style:
                                      TextStyle(color: pop.haze, fontSize: 12)),
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
  bool _cheering = false;
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
      Row(children: [
        Expanded(child: Text('SHOWCASE', style: FloorPop.of(context).label)),
        if (own)
          TextButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Edit'),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ShowcasePickerPage()));
                if (mounted) {
                  await _load();
                }
              })
      ]),
      if (_error != null) ...[
        Text(_error!),
        TextButton(onPressed: _load, child: const Text('Try again'))
      ] else if (_cards == null)
        const Center(child: CircularProgressIndicator())
      else
        ShowcaseDisplay(
            cards: _cards!,
            cheering: _cheering,
            onCheer: own
                ? null
                : (card) async {
                    if (_cheering) return;
                    setState(() => _cheering = true);
                    final request = ++_request;
                    try {
                      final cards =
                          await circle.cheerShowcase(widget.person.id, card);
                      if (mounted && request == _request) {
                        setState(() => _cards = cards);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString())));
                      }
                      if (mounted) {
                        await _load();
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _cheering = false);
                      }
                    }
                  }),
    ]);
  }
}

class ShowcaseDisplay extends StatefulWidget {
  const ShowcaseDisplay(
      {super.key, required this.cards, this.onCheer, this.cheering = false});
  final List<ShowcaseCard?> cards;
  final ValueChanged<ShowcaseCard>? onCheer;
  final bool cheering;
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
          child: Text('No showcase cards yet', textAlign: TextAlign.center));
    }
    _active = _active.clamp(0, cards.length - 1);
    final card = cards[_active];
    return Column(children: [
      _CardFan(
          cards: cards,
          active: _active,
          onPick: (i) => setState(() => _active = i)),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < cards.length; i++)
          Container(
              width: i == _active ? 18 : 8,
              height: 8,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                  color:
                      i == _active ? FloorPop.volt : FloorPop.of(context).riser,
                  borderRadius: BorderRadius.circular(4)))
      ]),
      const SizedBox(height: 16),
      _CardDetails(card),
      if (widget.onCheer != null) ...[
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: widget.cheering ? null : () => widget.onCheer!(card),
            icon: Icon(card.cheered ? Icons.favorite : Icons.favorite_border),
            label: Text(
                '${card.cheered ? 'Cheered' : 'Cheer this card'}${card.cheers > 0 ? ' · ${card.cheers}' : ''}'))
      ],
      TextButton(
          onPressed: chartOf(card.song, card.mode, card.difficulty).song == null
              ? null
              : () {
                  final chart = chartOf(card.song, card.mode, card.difficulty);
                  context.read<SongState>().setMode(card.mode);
                  context.push(songPath(chart.song!,
                      difficulty: chart.index < 0 ? 0 : chart.index));
                },
          child: const Text('Open the chart')),
    ]);
  }
}

class _CardDetails extends StatelessWidget {
  const _CardDetails(this.card);
  final ShowcaseCard card;
  @override
  Widget build(BuildContext context) {
    final chart = chartOf(card.song, card.mode, card.difficulty);
    final pop = FloorPop.of(context);
    return Column(children: [
      Text(chart.song?.title ?? card.song,
          textAlign: TextAlign.center, style: FloorPop.display(19)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(card.mode == Modes.singles ? 'SP' : 'DP'),
        const SizedBox(width: 8),
        DifficultyLabel(difficulty: card.difficulty, level: chart.level)
      ]),
      const SizedBox(height: 12),
      Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: pop.stage, borderRadius: BorderRadius.circular(20)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(formatScore(card.best.score ?? 0),
                      style: FloorPop.readout(22)),
                  ChartBestBadges(card.best, ink: 18, height: 24)
                ]),
            if (card.caption.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('“${card.caption}”',
                      style: const TextStyle(fontWeight: FontWeight.w600))),
            if (card.playedAt case final at?)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                      'Earned ${at.toLocal().toString().split(' ').first}',
                      style: TextStyle(color: pop.haze, fontSize: 12))),
          ]))
    ]);
  }
}

class _CardArt extends StatelessWidget {
  const _CardArt(this.card);
  final ShowcaseCard card;
  @override
  Widget build(BuildContext context) => CompactJacketEdition(
      facts: EditionFacts(
          chart: (
            song: card.song,
            mode: card.mode.name,
            difficulty: card.difficulty
          ),
          level: chartOf(card.song, card.mode, card.difficulty).level,
          score: card.best.score,
          grade: card.best.grade,
          lamp: card.best.lamp,
          flare: card.best.flare),
      options: editionPreferences(),
      flareStamp: true,
      child: SongArtwork(
          songName: card.song,
          title: chartOf(card.song, card.mode, card.difficulty).song?.title ??
              card.song));
}

class _CardFan extends StatelessWidget {
  const _CardFan(
      {required this.cards,
      required this.active,
      required this.onPick,
      this.editor = false});
  final List<ShowcaseCard?> cards;
  final int active;
  final ValueChanged<int> onPick;
  final bool editor;
  @override
  Widget build(BuildContext context) => SizedBox(
      height: editor ? 180 : 232,
      child: LayoutBuilder(builder: (context, box) {
        final size = (box.maxWidth * (editor ? .29 : .4))
            .clamp(70.0, editor ? 112.0 : 150.0);
        final others = [
          for (var i = 0; i < cards.length; i++)
            if (i != active) i
        ];
        return Stack(clipBehavior: Clip.none, children: [
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
              Builder(builder: (context) {
                final on = i == active;
                final side = editor
                    ? i - 1
                    : on
                        ? 0
                        : others.indexOf(i) == 0
                            ? -1
                            : 1;
                final card = cards[i];
                return AnimatedPositioned(
                    key: ValueKey(i),
                    duration: const Duration(milliseconds: 200),
                    left: (box.maxWidth - size) / 2 +
                        side * size * (editor ? 1.05 : .74),
                    top: (editor ? 30 : 38) + (on ? 0 : 16),
                    width: size,
                    height: size,
                    child: Transform.rotate(
                        angle: side * .12,
                        child: Transform.scale(
                            scale: on ? 1.06 : .88,
                            child: Semantics(
                                key: ValueKey('showcase-slot-$i'),
                                button: true,
                                selected: on,
                                label:
                                    'Card ${i + 1}: ${card?.song ?? 'empty'}',
                                child: GestureDetector(
                                    onTap: () => onPick(i),
                                    child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: on && editor
                                                ? Border.all(
                                                    color: FloorPop.volt,
                                                    width: 2)
                                                : null),
                                        child: card == null
                                            ? DecoratedBox(
                                                decoration: BoxDecoration(
                                                    color:
                                                        FloorPop.of(context).stage,
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(color: FloorPop.of(context).haze)),
                                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.add), Text('CARD ${i + 1}')]))
                                            : _CardArt(card)))))));
              })
        ]);
      }));
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
  final _caption = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
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
          _caption.text = _slots[_active]?.caption ?? '';
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
        _caption.text = _slots[i]?.caption ?? '';
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
        _caption.text = _slots[_active]?.caption ?? '';
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
        appBar: AppBar(title: const Text('SHOWCASE'), actions: [
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
                              Text('Three cards your circle sees on your page',
                                  style: TextStyle(color: pop.haze)),
                              _CardFan(
                                  cards: _slots,
                                  active: _active,
                                  onPick: _saving ? (_) {} : _select,
                                  editor: true),
                              if (active == null)
                                Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(children: [
                                      Text('CARD ${_active + 1}',
                                          style: pop.label),
                                      const Text('Pick a best below'),
                                      const Text("Any chart you've a score on")
                                    ])),
                              if (active != null) ...[
                                Row(children: [
                                  Expanded(
                                      child: Text('CARD ${_active + 1}',
                                          style: pop.label)),
                                  IconButton(
                                      tooltip: 'Take this card out',
                                      onPressed: _saving
                                          ? null
                                          : () => setState(() {
                                                _slots[_active] = null;
                                                _caption.clear();
                                              }),
                                      icon: const Icon(Icons.close))
                                ]),
                                _CardDetails(active),
                                const SizedBox(height: 12),
                                TextField(
                                    controller: _caption,
                                    enabled: !_saving,
                                    maxLength: 40,
                                    decoration: const InputDecoration(
                                        labelText: 'WHY THIS ONE · OPTIONAL',
                                        hintText:
                                            'A line your circle sees under it'),
                                    onChanged: (value) => setState(() =>
                                        _slots[_active] =
                                            active.withCaption(value))),
                              ],
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
