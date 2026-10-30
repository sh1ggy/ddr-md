/// Name: EditionLabPage
/// Parent: SettingsPage (development only)
/// Description: Production renderer fixtures, comparisons and timing export.
library;

import 'dart:async';
import 'dart:convert';
import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/components/songlist/jacket_image.dart';
import 'package:ddr_md/grades.dart';
import 'package:ddr_md/helpers.dart' show kFlareRanks, kInGameDifficultyNames;
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/models/version_group.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'edition_catalog.dart';
import 'edition_fixture_browser.dart';
import 'edition_model.dart';
import 'edition_rules.dart';
import 'jacket_edition.dart';

class EditionLabPage extends StatefulWidget {
  const EditionLabPage({super.key});
  @override
  State<EditionLabPage> createState() => _EditionLabPageState();
}

class _EditionLabPageState extends State<EditionLabPage> {
  Grade? _grade = Grade.aaa;
  ClearLamp? _lamp = ClearLamp.pfc;
  PrecisionAward _precision = PrecisionAward.pfc;
  FlareGroup? _version = FlareGroup.gold;
  String? _flare = 'EX';
  String _mode = 'singles';
  String _difficulty = 'hard';
  int? _level = 16;
  String _border = 'gilded';
  int _art = 0;
  PrecisionEvidence? _seededEvidence;
  bool _modeStamp = true;
  bool _motion = false,
      _gradeStamp = true,
      _difficultyStamp = true,
      _tierSuffix = true;
  double _x = .35, _y = .3;
  Timer? _timer;
  final _frames = <FrameTiming>[];
  Map<String, Object?>? _report;
  bool get _capturing => _timer != null;

  EditionOptions get _options => (
        borderId: _border,
        effects: true,
        motion: _motion,
        modeStamp: _modeStamp,
        gradeStamp: _gradeStamp,
        difficultyStamp: _difficultyStamp,
        tierSuffix: _tierSuffix
      );
  EditionFacts _facts({PrecisionAward? precision}) => EditionFacts(
          chart: (
            song: _art == 0 ? 'neutral' : Songs.list[_art - 1].name,
            mode: _mode,
            difficulty: _difficulty
          ),
          level: _level,
          grade: _grade,
          lamp: _lamp,
          flare: _flare,
          version: _version,
          precision: _seededEvidence != null &&
                  precision == null &&
                  _seededEvidence!.award == _precision
              ? _seededEvidence
              : (
                  award: precision ?? _precision,
                  sourceRowId: 'lab-fixture',
                  perfects:
                      (precision ?? _precision) == PrecisionAward.sdp ? 9 : null
                ));

  Widget _artwork() => _art == 0
      ? const DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
          Color(0xFF354260),
          Color(0xFFD7CDBA),
          Color(0xFF22293D)
        ], begin: Alignment.topLeft, end: Alignment.bottomRight)))
      : SongArtwork(
          songName: Songs.list[_art - 1].name,
          title: Songs.list[_art - 1].title,
          fullResolution: true,
          fade: Duration.zero);

  void _record(List<FrameTiming> frames) {
    // A bounded sample also protects the inspector if a device stalls.
    _frames.addAll(frames.take(1200 - _frames.length));
  }

  void _capture() {
    _frames.clear();
    _report = null;
    final recipe = resolveEdition(_facts(), _options).toJson();
    final display = View.of(context).display;
    final hz = display.refreshRate;
    final side = MediaQuery.sizeOf(context).width;
    SchedulerBinding.instance.addTimingsCallback(_record);
    setState(() => _timer = Timer(const Duration(seconds: 5), () {
          SchedulerBinding.instance.removeTimingsCallback(_record);
          int percentile(List<int> values, double p) {
            values.sort();
            return values.isEmpty
                ? 0
                : values[((values.length - 1) * p).round()];
          }

          final ui =
              _frames.map((f) => f.buildDuration.inMicroseconds).toList();
          final raster =
              _frames.map((f) => f.rasterDuration.inMicroseconds).toList();
          if (!mounted) return;
          setState(() {
            _timer = null;
            _report = {
              'buildMode': kReleaseMode
                  ? 'release'
                  : kProfileMode
                      ? 'profile'
                      : 'debug',
              'platform': defaultTargetPlatform.name,
              'refreshHz': hz,
              'viewportWidth': side,
              'art': _facts().chart.song,
              'frozenLight': _motion ? null : [_x, _y],
              'recipe': recipe,
              'sampleFrames': ui.length,
              'p50UiUs': percentile(ui.toList(), .5),
              'p95UiUs': percentile(ui.toList(), .95),
              'p50RasterUs': percentile(raster.toList(), .5),
              'p95RasterUs': percentile(raster.toList(), .95),
              'overBudget': _frames
                  .where((f) =>
                      f.buildDuration.inMicroseconds > 1000000 / hz ||
                      f.rasterDuration.inMicroseconds > 1000000 / hz)
                  .length,
              'uiUs': ui,
              'rasterUs': raster,
              'note':
                  'Viewer-wide timings. Separate cold opens and steady sweeps; verify on phones.',
            };
          });
        }));
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_record);
    super.dispose();
  }

  Widget _select<T>(String label, T value, Iterable<T> values,
          ValueChanged<T> change, String Function(T) name) =>
      DropdownButtonFormField<T>(
          key: ValueKey('$label:$value'),
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final v in values)
              DropdownMenuItem(value: v, child: Text(name(v)))
          ],
          onChanged: _capturing
              ? null
              : (v) {
                  if (v != null) setState(() => change(v));
                });
  Widget _toggle(String label, bool value, ValueChanged<bool> change) =>
      SwitchListTile(
          title: Text(label),
          value: value,
          onChanged: _capturing ? null : (v) => setState(() => change(v)));

  void _fixture(String id) => setState(() {
        _seededEvidence = null;
        _grade = id == 'no data'
            ? null
            : id == 'failed'
                ? Grade.e
                : Grade.aaa;
        _lamp = switch (id) {
          'PFC' || 'SDP' => ClearLamp.pfc,
          'MFC + EX' => ClearLamp.mfc,
          'failed' => ClearLamp.failed,
          _ => null
        };
        _flare = id == 'EX only' || id == 'MFC + EX' ? 'EX' : null;
        _precision = switch (id) {
          'PFC' => PrecisionAward.pfc,
          'SDP' => PrecisionAward.sdp,
          'MFC + EX' => PrecisionAward.mfc,
          _ => PrecisionAward.unknown
        };
        if (id == 'no data' || id == 'EX only') _grade = null;
        if (id == 'partial') {
          _grade = Grade.b;
          _level = null;
          _version = null;
        } else {
          _level = 16;
          _version = FlareGroup.gold;
        }
      });

  Future<void> _browseSeeds() async {
    final facts = await Navigator.of(context).push<EditionFacts>(
        MaterialPageRoute(
            builder: (_) => EditionFixtureBrowser(artwork: _artwork())));
    if (!mounted || facts == null) return;
    setState(() {
      _grade = facts.grade;
      _lamp = facts.lamp;
      _flare = facts.flare;
      _version = facts.version;
      _level = facts.level;
      _difficulty = facts.chart.difficulty;
      _mode = facts.chart.mode;
      _precision = facts.precision?.award ?? PrecisionAward.unknown;
      _seededEvidence = facts.precision;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recipe = resolveEdition(_facts(), _options);
    final json = const JsonEncoder.withIndent('  ').convert({
      'chart': {
        'song': _facts().chart.song,
        'mode': _mode,
        'difficulty': _difficulty
      },
      'precision': _precision.name,
      'evidenceRowId': _seededEvidence?.sourceRowId,
      'recipe': recipe.toJson(),
      'timings': _report
    });
    return Scaffold(
        appBar: AppBar(title: const Text('Jacket edition lab')),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              const Text(
                  'Development preview • phone performance approval pending'),
              OutlinedButton(
                  onPressed: _capturing ? null : _browseSeeds,
                  child: const Text('Browse seeded score combinations')),
              Center(
                  child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: editionMaxSide),
                      child: AspectRatio(
                          aspectRatio: 1,
                          child: JacketEdition(
                              facts: _facts(),
                              options: _options,
                              frozenLight: _motion ? null : Offset(_x, _y),
                              child: _artwork())))),
              _toggle('Animate this preview', _motion, (v) => _motion = v),
              if (!_motion) ...[
                const Text('Frozen light X / Y'),
                Slider(
                    value: _x,
                    onChanged:
                        _capturing ? null : (v) => setState(() => _x = v)),
                Slider(
                    value: _y,
                    onChanged:
                        _capturing ? null : (v) => setState(() => _y = v)),
              ],
              Wrap(spacing: 8, children: [
                for (final id in [
                  'no data',
                  'partial',
                  'failed',
                  'EX only',
                  'PFC',
                  'SDP',
                  'MFC + EX'
                ])
                  ActionChip(
                      label: Text(id),
                      onPressed: _capturing ? null : () => _fixture(id))
              ]),
              _select(
                  'Artwork',
                  _art,
                  List.generate(1 + Songs.list.take(3).length, (i) => i),
                  (v) => _art = v,
                  (v) => v == 0 ? 'Neutral test' : Songs.list[v - 1].title),
              _select(
                  'Grade',
                  _grade?.name ?? '',
                  ['', ...Grade.values.map((g) => g.name)],
                  (v) => _grade = Grade.values.asNameMap()[v],
                  (v) => Grade.values.asNameMap()[v]?.label ?? 'Unknown'),
              _select(
                  'Flare',
                  _flare ?? '',
                  ['', ...kFlareRanks],
                  (v) => _flare = v.isEmpty ? null : v,
                  (v) => v.isEmpty ? 'Unknown' : v),
              _select(
                  'Version group',
                  _version?.name ?? '',
                  ['', ...FlareGroup.values.map((v) => v.name)],
                  (v) => _version = FlareGroup.values.asNameMap()[v],
                  (v) => v.isEmpty ? 'Neutral' : v),
              DropdownButtonFormField<int>(
                  key: ValueKey('lab-level:$_level'),
                  initialValue: _level ?? 0,
                  decoration: const InputDecoration(labelText: 'Actual level'),
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('Unknown')),
                    for (var level = 1; level <= 20; level++)
                      DropdownMenuItem(
                          value: level,
                          child: LevelNumber(
                              level: level,
                              difficulty: kInGameDifficultyNames[_difficulty] ??
                                  'EXPERT')),
                  ],
                  onChanged: _capturing
                      ? null
                      : (v) => setState(() => _level = v == 0 ? null : v)),
              _select('Play style', _mode, ['singles', 'doubles'],
                  (v) => _mode = v, (v) => v),
              DropdownButtonFormField<String>(
                  key: ValueKey('lab-difficulty:$_difficulty'),
                  initialValue: _difficulty,
                  decoration:
                      const InputDecoration(labelText: 'Chart difficulty'),
                  items: [
                    for (final e in kInGameDifficultyNames.entries)
                      DropdownMenuItem(
                          value: e.key,
                          child: DifficultyLabel(difficulty: e.value))
                  ],
                  onChanged: _capturing
                      ? null
                      : (v) => setState(() => _difficulty = v!)),
              _select(
                  'Lamp',
                  _lamp?.name ?? '',
                  ['', ...ClearLamp.values.map((v) => v.name)],
                  (v) => _lamp = ClearLamp.values.asNameMap()[v],
                  (v) => v.isEmpty ? 'Unknown' : v.toUpperCase()),
              _select('Precision fixture', _precision, PrecisionAward.values,
                  (v) => _precision = v, (v) => v.name.toUpperCase()),
              _select('Border study', _border, editionBorders.keys,
                  (v) => _border = v, (v) => v),
              _toggle('Play style stamp', _modeStamp, (v) => _modeStamp = v),
              _toggle('Grade stamp', _gradeStamp, (v) => _gradeStamp = v),
              _toggle('Difficulty / level stamp', _difficultyStamp,
                  (v) => _difficultyStamp = v),
              _toggle(
                  'Optical tier suffix', _tierSuffix, (v) => _tierSuffix = v),
              const Text('Fixed-light PFC / SDP / MFC • same axes and artwork'),
              Row(children: [
                for (final award in [
                  PrecisionAward.pfc,
                  PrecisionAward.sdp,
                  PrecisionAward.mfc
                ])
                  Expanded(
                      child: Column(children: [
                    Text(award.name.toUpperCase()),
                    AspectRatio(
                        aspectRatio: 1,
                        child: JacketEdition(
                            facts: EditionFacts(
                                chart: _facts().chart,
                                level: _level,
                                version: _version,
                                grade: _grade,
                                flare: _flare,
                                lamp: ClearLamp.pfc,
                                precision: (
                                  award: award,
                                  sourceRowId: 'lab-fixture',
                                  perfects:
                                      award == PrecisionAward.sdp ? 9 : null
                                )),
                            options: (
                              borderId: _border,
                              effects: true,
                              motion: false,
                              modeStamp: false,
                              gradeStamp: false,
                              difficultyStamp: false,
                              tierSuffix: false
                            ),
                            frozenLight: Offset(_x, _y),
                            child: _artwork()))
                  ]))
              ]),
              const Text('Plain-jacket baseline'),
              Center(child: SizedBox.square(dimension: 180, child: _artwork())),
              FilledButton(
                  onPressed: _capturing ? null : _capture,
                  child: Text(_capturing
                      ? 'Capturing 5 seconds…'
                      : 'Capture frame timings')),
              TextButton(
                  onPressed: _capturing
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: json));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Recipe and timings copied')));
                          }
                        },
                  child: const Text('Export recipe + timing JSON')),
              SelectableText(json),
            ]));
  }
}
