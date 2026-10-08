/// Name: FootingStylePage
/// Parent: SettingsPage
/// Description: An overview of the parity engine: the patterns it finds most
/// divisive, each looping a real-chart moment as the active style (Default,
/// or Yours learned from footing edits) dances it, chart and pad side by side.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:ddr_md/components/song/notes/chart_timing.dart';
import 'package:ddr_md/components/song/notes/dancing_feet.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/parity_profile.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Default (the shipped footing) or Yours (learned from your edits); Yours stays
/// disabled until there's a fit to use.
class FootingStyleSwitch extends StatelessWidget {
  const FootingStyleSwitch({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        const ButtonSegment(value: false, label: Text('Default')),
        ButtonSegment(
            value: true,
            label: const Text('Yours'),
            enabled: ParityProfile.yours != null),
      ],
      selected: {ParityProfile.usingYours},
      onSelectionChanged: (s) {
        ParityProfile.usingYours = s.first;
        onChanged?.call();
      },
    );
  }
}

const Map<String, String> _patternNames = {
  'jack-vs-footswitch': 'Jack or footswitch',
  'slow-doublestep-vs-crossover': 'Slow doublestep',
  'candle': 'Candle',
  'spin': 'Spin',
  'bracket-vs-jump': 'Bracket or jump',
  'hold-with-taps': 'Hold with taps',
  'lateral': 'Lateral',
};

/// Arrow scale in the moment charts, small enough to keep a few rows in view.
const double _zoom = 0.6;

/// Seconds shown before a moment's first row and held after its last.
const double _leadIn = 1.0, _tail = 0.6;

/// One divisive pattern's moment (picked by tool/mine_parity_quiz.dart), with
/// its chart and the active style's solve of it.
class _Moment {
  final String pattern, song, difficulty;
  final double from, to;
  final List<StepNote> notes;
  Map<StepNote, Foot> feet = const {};
  List<ParityStance> stances = const [];
  final ValueNotifier<double> playhead;

  _Moment(this.pattern, this.song, this.difficulty, this.from, this.to,
      this.notes)
      : playhead = ValueNotifier(from - _leadIn);

  double get loop => to - from + _leadIn + _tail;
}

/// Each chart solved whole with [weights]; feet come back by note index since
/// the notes are copied across the isolate.
List<(List<ParityFoot?>, List<ParityStance>)> _solveAll(
    (List<List<StepNote>>, ParityWeights) job) {
  final (charts, weights) = job;
  return [
    for (final notes in charts)
      () {
        final r = analyseParity(notes, Modes.singles, weights: weights);
        return ([for (final n in notes) r.feet[n]], r.stances);
      }()
  ];
}

class FootingStylePage extends StatefulWidget {
  const FootingStylePage({super.key});

  @override
  State<FootingStylePage> createState() => _FootingStylePageState();
}

class _FootingStylePageState extends State<FootingStylePage>
    with SingleTickerProviderStateMixin {
  List<_Moment> _moments = const [];
  FootingFit? _fit;

  // One ticker loops every moment at its own real tempo.
  late final Ticker _ticker = createTicker((elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    for (final m in _moments) {
      m.playhead.value = m.from - _leadIn + t % m.loop;
    }
  });

  @override
  void initState() {
    super.initState();
    SpriteNoteskin.tryLoad().then((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    // Learn from the latest edits first, so Yours is current.
    final fit = await refitFromEdits();
    final picks =
        json.decode(await rootBundle.loadString('assets/parity_patterns.json'))
            as List;
    final moments = <_Moment>[];
    for (final p in picks) {
      final song = await StepsLoader.load(p['song'] as String);
      final notes = song?.chartFor(Modes.singles, p['difficulty'] as String)?.notes;
      if (notes == null) continue;
      moments.add(_Moment(p['pattern'] as String, p['song'] as String,
          p['difficulty'] as String, (p['from'] as num).toDouble(),
          (p['to'] as num).toDouble(), notes));
    }
    _moments = moments;
    _fit = fit;
    await _solve();
    _ticker.start();
  }

  Future<void> _solve() async {
    final solved = await compute(
        _solveAll, ([for (final m in _moments) m.notes], ParityProfile.active));
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _moments.length; i++) {
        final (feet, stances) = solved[i];
        final m = _moments[i];
        m.feet = {
          for (int j = 0; j < m.notes.length; j++)
            if (feet[j] case final f?)
              m.notes[j]: f == ParityFoot.left ? Foot.left : Foot.right
        };
        m.stances = stances;
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final m in _moments) {
      m.playhead.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Footing Style',
            style: TextStyle(
                fontSize: 20,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.blueGrey),
      ),
      body: _moments.isEmpty || _moments.first.stances.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  Center(
                    child: FootingStyleSwitch(onChanged: () {
                      setState(() {});
                      _solve();
                    }),
                  ),
                  const SizedBox(height: 8),
                  for (final m in _moments) _MomentCard(m),
                  if (_fit case final fit?) _editsLine(fit),
                ],
              ),
            ),
    );
  }

  // How many hand-set feet each style places on its own.
  Widget _editsLine(FootingFit fit) {
    final total = fit.pinCounts.fold(0, (a, b) => a + b);
    final byDefault = fit.result.before.fold(0, (a, b) => a + b);
    final yours = fit.result.after.fold(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text('Your edits  ·  Default $byDefault/$total  ·  Yours $yours/$total',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard(this.m);

  final _Moment m;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_patternNames[m.pattern] ?? m.pattern,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${m.song}  '),
                TextSpan(
                    text: kInGameDifficultyNames[m.difficulty] ?? m.difficulty,
                    style: TextStyle(
                        color: difficultyColor(m.difficulty),
                        fontWeight: FontWeight.w800)),
              ]),
              style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: Row(
                children: [
                  Expanded(child: _MomentChart(m)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 132,
                    height: DancingFeet.height,
                    child: DancePad(
                        stances: m.stances,
                        playhead: m.playhead,
                        columnCount: 4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The moment scrolling up into the receptors as the chart preview draws it.
class _MomentChart extends StatelessWidget {
  const _MomentChart(this.m);

  final _Moment m;

  @override
  Widget build(BuildContext context) {
    final notes = [
      for (final n in m.notes)
        if (n.second >= m.from - _leadIn && n.second <= m.to + _tail) n
    ];
    // Scroll fast enough that the closest rows sit an arrow and a half apart,
    // as the chart preview reads, and let the moment pass through.
    final rows = {for (final n in notes) n.second}.toList()..sort();
    double gap = double.infinity;
    for (int i = 1; i < rows.length; i++) {
      gap = math.min(gap, rows[i] - rows[i - 1]);
    }
    return LayoutBuilder(builder: (context, constraints) {
      final arrow = constraints.maxWidth / 4 * 0.92 * _zoom;
      final travel = constraints.maxHeight - ChartPainter.receptorBase;
      final fit = travel / (m.to - m.from + _leadIn);
      final pxPerSecond = gap.isFinite ? math.max(fit, arrow * 1.5 / gap) : fit;
      return ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: ChartPainter(
            notes: notes,
            holds: [for (final n in notes) if (n.isHold) n],
            shockNotes: const {},
            shocks: const [],
            bpmMarkers: const [],
            stopMarkers: const [],
            feet: m.feet,
            footPrev: const {},
            dirs: kSingleDirs,
            colMap: const [0, 1, 2, 3],
            playhead: m.playhead,
            pxPerSecond: pxPerSecond,
            zoom: _zoom,
            pxPerBeat: 0,
            timing: ChartTiming.empty,
            columnCount: 4,
            skin: SpriteNoteskin.resolvedSkin ?? const VectorNoteskin(),
            playing: true,
          ),
        ),
      );
    });
  }
}
