/// Name: EditionFixtureBrowser
/// Parent: EditionLabPage
/// Description: Bounded pages of the seeded score/achievement cross product.
library;

import 'package:flutter/material.dart';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/helpers.dart' show kInGameDifficultyNames;
import 'edition_fixture_store.dart';
import 'edition_model.dart';
import 'jacket_edition.dart';

typedef _Fixture = ({int index, EditionFacts facts, String label});

class EditionFixtureBrowser extends StatefulWidget {
  const EditionFixtureBrowser({super.key, required this.artwork});
  final Widget artwork;
  @override
  State<EditionFixtureBrowser> createState() => _EditionFixtureBrowserState();
}

class _EditionFixtureBrowserState extends State<EditionFixtureBrowser> {
  EditionFixtureStore? _store;
  Future<List<_Fixture>>? _page;
  Object? _error;
  int _start = 0;
  bool _validating = false;
  String? _validation;
  final _jump = TextEditingController();
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final store = await EditionFixtureStore.open();
      if (!mounted) {
        await store.close();
        return;
      }
      setState(() {
        _store = store;
        _page = store.page(0);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _go(int start) {
    final store = _store!;
    final next = start.clamp(0, store.space.count - 1);
    setState(() {
      _start = next;
      _jump.text = '$next';
      _page = store.page(next);
    });
  }

  Future<void> _validate() async {
    setState(() => _validating = true);
    try {
      final result = await _store!.space.validateAll();
      if (mounted) {
        setState(() => _validation =
            '${result['validated']} / ${_store!.space.count} recipes passed');
      }
    } catch (e) {
      if (mounted) setState(() => _validation = 'Validation failed: $e');
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  Widget _axes(EditionFixtureSpace space) {
    final ids = space.address(_start);
    final labels = [
      [for (final r in space.ranges) r.label],
      [for (final r in space.results) r.label],
      [for (final f in space.flares) f ?? 'Unknown'],
      [for (final v in space.versions) v?.name ?? 'Neutral'],
      [for (final l in space.levels) l?.toString() ?? 'Unknown'],
      space.difficulties,
      [for (final m in space.modes) m.name],
    ];
    const names = [
      'Score range',
      'Lamp / precision evidence',
      'Flare',
      'Version group',
      'Level',
      'Chart difficulty',
      'Play style'
    ];
    return ExpansionTile(
      title: const Text('Choose any combination'),
      children: [
        SizedBox(
            height: 240,
            child: SingleChildScrollView(
                child: Column(children: [
              for (var axis = 0; axis < labels.length; axis++)
                DropdownButtonFormField<int>(
                    key: ValueKey('$axis:${ids[axis]}'),
                    initialValue: ids[axis],
                    isExpanded: true,
                    decoration: InputDecoration(labelText: names[axis]),
                    items: [
                      for (var i = 0; i < labels[axis].length; i++)
                        DropdownMenuItem(
                            value: i,
                            child: axis == 5
                                ? DifficultyLabel(
                                    difficulty: kInGameDifficultyNames[
                                        labels[axis][i]]!)
                                : axis == 4 && space.levels[i] != null
                                    ? LevelNumber(
                                        level: space.levels[i]!,
                                        difficulty: 'EXPERT')
                                    : Text(labels[axis][i],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        ids[axis] = v;
                        _go(space.indexOf(ids));
                      }
                    }),
            ])))
      ],
    );
  }

  @override
  void dispose() {
    _jump.dispose();
    _store?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return Scaffold(
        appBar: AppBar(title: const Text('Seeded score combinations')),
        body: _error != null
            ? Center(child: Text('Fixture database unavailable: $_error'))
            : store == null
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(children: [
                          Text(
                              '${store.space.count} combinations • ${store.space.ranges.length} score boundaries • ${store.space.results.length} result/evidence cases'),
                          const Text(
                              'Isolated lab database • 12 static cards per page • tap a card to tune it'),
                          _axes(store.space),
                          Row(children: [
                            IconButton(
                                tooltip: 'Previous page',
                                onPressed:
                                    _start == 0 ? null : () => _go(_start - 12),
                                icon: const Icon(Icons.chevron_left)),
                            Expanded(
                                child: TextField(
                                    controller: _jump,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                        labelText:
                                            'Combination index (0–${store.space.count - 1})'),
                                    onSubmitted: (v) {
                                      final n = int.tryParse(v);
                                      if (n != null) _go(n);
                                    })),
                            IconButton(
                                tooltip: 'Jump',
                                onPressed: () {
                                  final n = int.tryParse(_jump.text);
                                  if (n != null) _go(n);
                                },
                                icon: const Icon(Icons.arrow_forward)),
                            IconButton(
                                tooltip: 'Next page',
                                onPressed: _start + 12 >= store.space.count
                                    ? null
                                    : () => _go(_start + 12),
                                icon: const Icon(Icons.chevron_right)),
                          ]),
                          TextButton(
                              onPressed: _validating ? null : _validate,
                              child: Text(_validating
                                  ? 'Validating off the UI thread…'
                                  : 'Validate every combination')),
                          if (_validation != null) Text(_validation!),
                        ])),
                    Expanded(
                        child: FutureBuilder<List<_Fixture>>(
                            future: _page,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return Center(child: Text('${snapshot.error}'));
                              }
                              if (!snapshot.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              final fixtures = snapshot.data!;
                              return GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 12, 12, 120),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: 270,
                                          childAspectRatio: .73,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12),
                                  itemCount: fixtures.length,
                                  itemBuilder: (context, i) {
                                    final fixture = fixtures[i];
                                    return InkWell(
                                        onTap: () => Navigator.of(context)
                                            .pop(fixture.facts),
                                        child: Column(children: [
                                          Expanded(
                                              child: AspectRatio(
                                                  aspectRatio: 1,
                                                  child: JacketEdition(
                                                      facts: fixture.facts,
                                                      options: (
                                                        borderId: 'gilded',
                                                        effects: true,
                                                        motion: false,
                                                        modeStamp: true,
                                                        gradeStamp: true,
                                                        difficultyStamp: true,
                                                        tierSuffix: true
                                                      ),
                                                      frozenLight:
                                                          const Offset(.35, .3),
                                                      child: widget.artwork))),
                                          Text(
                                              '#${fixture.index} • ${fixture.label}',
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis),
                                          Text(
                                              '${fixture.facts.flare ?? 'No flare'} • ${fixture.facts.version?.name ?? 'Neutral'}'),
                                        ]));
                                  });
                            })),
                  ]));
  }
}
