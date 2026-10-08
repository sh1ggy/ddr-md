/// Name: ParityQuizPage
/// Parent: SettingsPage
/// Description: The footing-style questionnaire. One real-chart moment at a
/// time, each footing option drawn as a small chart read bottom to top; tap the
/// one you'd dance. Answers are kept for fitting the player's parity profile.
library;

import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:ddr_md/components/song/notes/chart_timing.dart';
import 'package:ddr_md/components/song/notes/dancing_feet.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/models/steps_model.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/parity_quiz.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/models/parity_labels.dart';
import 'package:ddr_md/models/parity_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const double _leadIn = 1.0, _tail = 0.6;

const Map<String, String> _patternNames = {
  'jack-vs-footswitch': 'Jack or footswitch',
  'slow-doublestep-vs-crossover': 'Slow doublestep',
  'candle': 'Candle',
  'spin': 'Spin',
  'bracket-vs-jump': 'Bracket or jump',
  'hold-with-taps': 'Hold with taps',
  'lateral': 'Lateral',
};

/// The fit plus flag counts before and after, off the UI isolate: a few
/// seconds of solving that would otherwise freeze the page.
(FitResult, Map<ParityFlag, int>, Map<ParityFlag, int>) _fitJob(
    (List<FitCase>, List<List<StepNote>>) job) {
  final (cases, charts) = job;
  final fit = fitProfile(cases);
  return (
    fit,
    flagCounts(charts, ParityWeights.defaults),
    flagCounts(charts, fit.weights),
  );
}

/// Ours (the shipped footing) or Yours (fitted to the questionnaire); Yours
/// stays disabled until there's a fit to use.
class FootingStyleSwitch extends StatelessWidget {
  const FootingStyleSwitch({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        const ButtonSegment(value: false, label: Text('Ours')),
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

class ParityQuizPage extends StatefulWidget {
  const ParityQuizPage({super.key});

  @override
  State<ParityQuizPage> createState() => _ParityQuizPageState();
}

class _ParityQuizPageState extends State<ParityQuizPage>
    with SingleTickerProviderStateMixin {
  List<QuizQuestion> _questions = const [];
  Map<String, int> _answers = {};
  int _index = 0;

  // Fitted once every question is answered; shown past the last question.
  FitResult? _fit;
  Map<ParityFlag, int> _countsBefore = const {}, _countsAfter = const {};

  bool get _onResults => _index == _questions.length;

  // One clock loops the current moment for every option, so their pads and
  // charts move in step and can be compared side by side.
  late final AnimationController _loop = AnimationController(vsync: this)
    ..addListener(_tick);
  final ValueNotifier<double> _playhead = ValueNotifier(0);

  void _tick() {
    if (_onResults) return;
    final rows = _questions[_index].rows;
    final span = rows.last.second - rows.first.second + _leadIn + _tail;
    _playhead.value = rows.first.second - _leadIn + _loop.value * span;
  }

  void _restartLoop() {
    if (_onResults) {
      _loop.stop();
      _runFit();
      return;
    }
    final rows = _questions[_index].rows;
    final span = rows.last.second - rows.first.second + _leadIn + _tail;
    _loop
      ..duration = Duration(milliseconds: (span * 1000).round())
      ..repeat();
  }

  void _show(int index) {
    setState(() => _index = index);
    _restartLoop();
  }

  @override
  void initState() {
    super.initState();
    _answers = QuizAnswers.read();
    // Same skin as the chart preview once it resolves; vector until then.
    SpriteNoteskin.tryLoad().then((_) {
      if (mounted) setState(() {});
    });
    // Same skin as the chart preview once it resolves; vector until then.
    SpriteNoteskin.tryLoad().then((_) {
      if (mounted) setState(() {});
    });
    QuizQuestion.load().then((qs) {
      if (!mounted) return;
      setState(() {
        _questions = qs;
        // Resume at the first unanswered question, or the results.
        final next = qs.indexWhere((q) => !_answers.containsKey(q.id));
        _index = next < 0 ? qs.length : next;
      });
      _restartLoop();
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _playhead.dispose();
    super.dispose();
  }

  // Options are shown rotated per question so the engine's reading (option 0
  // in the data) isn't always in the same place.
  List<int> _order(int questionIndex, int count) =>
      [for (int k = 0; k < count; k++) (k + questionIndex) % count];

  void _choose(QuizQuestion q, int option) {
    setState(() {
      _answers = {..._answers, q.id: option};
      QuizAnswers.write(_answers);
    });
    _fit = null;
    final next = _questions.indexWhere((q) => !_answers.containsKey(q.id));
    _show(next < 0 ? _questions.length : next);
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
      body: _questions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _onResults
              ? _buildResults(context)
              : _buildQuestion(context),
    );
  }

  Future<void> _runFit() async {
    if (_fit != null) return;
    final charts = <List<StepNote>>[];
    for (final q in _questions) {
      final song = await StepsLoader.load(q.song);
      charts.add(song!.chartFor(Modes.singles, q.difficulty)!.notes);
    }
    final cases = [
      for (int i = 0; i < _questions.length; i++)
        _questions[i].fitCase(charts[i], _answers[_questions[i].id]!)
    ];
    final (fit, before, after) = await compute(_fitJob, (cases, charts));
    ParityProfile.saveYours(fit.weights);
    if (!mounted) return;
    setState(() {
      _fit = fit;
      _countsBefore = before;
      _countsAfter = after;
    });
  }

  Widget _buildResults(BuildContext context) {
    final fit = _fit;
    if (fit == null) return const Center(child: CircularProgressIndicator());
    final n = _questions.length;
    final yours = ParityProfile.usingYours;
    const dim = TextStyle(color: Colors.blueGrey, fontSize: 13);
    Widget tick(bool ok) => Icon(ok ? Icons.check_circle : Icons.circle_outlined,
        size: 18, color: ok ? Colors.greenAccent : Colors.white24);
    // Two columns throughout, the one in use tinted.
    Widget row(Widget label, Widget ours, Widget mine, {VoidCallback? onTap}) {
      Widget cell(Widget child, bool active) => Container(
            width: 72,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: active ? Colors.white.withValues(alpha: 0.05) : null,
            child: child,
          );
      return InkWell(
        onTap: onTap,
        child: Row(children: [
          Expanded(child: label),
          cell(ours, !yours),
          cell(mine, yours),
        ]),
      );
    }

    Text count(int? v) => Text('${v ?? 0}',
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]));
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          row(const SizedBox(),
              const Text('Ours', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text('Yours', style: TextStyle(fontWeight: FontWeight.w700))),
          row(
            const Text('Moments read your way'),
            Text('${fit.before.where((x) => x).length}/$n',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('${fit.after.where((x) => x).length}/$n',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          for (int i = 0; i < n; i++)
            row(
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_patternNames[_questions[i].pattern] ??
                        _questions[i].pattern),
                    Text(_questions[i].song,
                        style: dim, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              tick(fit.before[i]),
              tick(fit.after[i]),
              onTap: () => _show(i),
            ),
          const SizedBox(height: 16),
          const Text('Across these 8 charts', style: dim),
          for (final (flag, label) in const [
            (ParityFlag.doublestep, 'Doublesteps'),
            (ParityFlag.crossover, 'Crossovers'),
            (ParityFlag.footswitch, 'Footswitches'),
            (ParityFlag.samePanel, 'Both feet on one arrow'),
          ])
            row(Text(label), count(_countsBefore[flag]), count(_countsAfter[flag])),
          const SizedBox(height: 20),
          Center(
            child: FootingStyleSwitch(onChanged: () => setState(() {})),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(BuildContext context) {
    final q = _questions[_index];
    final chosen = _answers[q.id];
    final answered =
        _questions.where((q) => _answers.containsKey(q.id)).length;
    return SafeArea(
      child: Column(
        children: [
          LinearProgressIndicator(value: answered / _questions.length),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(_patternNames[q.pattern] ?? q.pattern,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          Text.rich(TextSpan(children: [
            TextSpan(text: '${q.song}  '),
            TextSpan(
                text: kInGameDifficultyNames[q.difficulty] ?? q.difficulty,
                style: TextStyle(
                    color: difficultyColor(q.difficulty),
                    fontWeight: FontWeight.w800)),
          ]), style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  for (final option in _order(_index, q.optionCount))
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _OptionCard(
                          question: q,
                          option: option,
                          playhead: _playhead,
                          selected: chosen == option,
                          onTap: () => _choose(q, option),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _index == 0 ? null : () => _show(_index - 1),
              ),
              Text('${_index + 1}/${_questions.length}',
                  style: const TextStyle(color: Colors.blueGrey)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _index == _questions.length - 1 &&
                        _answers.length < _questions.length
                    ? null
                    : () => _show(_index + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.question,
    required this.option,
    required this.playhead,
    required this.selected,
    required this.onTap,
  });

  final QuizQuestion question;
  final int option;
  final ValueListenable<double> playhead;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? scheme.primary : Colors.white12,
              width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                height: DancingFeet.height,
                child: DancePad(
                  stances: question.stancesFor(option),
                  playhead: playhead,
                  columnCount: 4,
                ),
              ),
            ),
            Expanded(child: _OptionChart(question, option, playhead)),
          ],
        ),
      ),
    );
  }
}

/// One option's footing scrolling up into the receptors exactly as the chart
/// preview draws it, on the clock the pads dance to.
class _OptionChart extends StatelessWidget {
  const _OptionChart(this.question, this.option, this.playhead);

  final QuizQuestion question;
  final int option;
  final ValueListenable<double> playhead;

  @override
  Widget build(BuildContext context) {
    final notes = [for (final (n, _) in question.chartNotes) n];
    final rows = question.rows;
    return LayoutBuilder(builder: (context, constraints) {
      // The whole moment, lead-in included, fits the field at the loop's start.
      final travel = constraints.maxHeight - ChartPainter.receptorBase;
      final seconds = rows.last.second - rows.first.second + _leadIn;
      return CustomPaint(
        size: Size.infinite,
        painter: ChartPainter(
          notes: notes,
          holds: [for (final n in notes) if (n.isHold) n],
          shockNotes: const {},
          shocks: const [],
          bpmMarkers: const [],
          stopMarkers: const [],
          feet: {
            for (final (n, q) in question.chartNotes)
              n: q.feet[option] == ParityFoot.left ? Foot.left : Foot.right
          },
          footPrev: const {},
          dirs: kSingleDirs,
          colMap: const [0, 1, 2, 3],
          playhead: playhead,
          pxPerSecond: travel / seconds,
          pxPerBeat: 0,
          timing: ChartTiming.empty,
          columnCount: 4,
          skin: SpriteNoteskin.resolvedSkin ?? const VectorNoteskin(),
          playing: true,
        ),
      );
    });
  }
}
