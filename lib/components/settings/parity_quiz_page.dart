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

  // One clock loops the current moment for every option, so their pads and
  // charts move in step and can be compared side by side.
  late final AnimationController _loop = AnimationController(vsync: this)
    ..addListener(_tick);
  final ValueNotifier<double> _playhead = ValueNotifier(0);

  void _tick() {
    final rows = _questions[_index].rows;
    final span = rows.last.second - rows.first.second + _leadIn + _tail;
    _playhead.value = rows.first.second - _leadIn + _loop.value * span;
  }

  void _restartLoop() {
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
        // Resume at the first unanswered question.
        final next = qs.indexWhere((q) => !_answers.containsKey(q.id));
        _index = next < 0 ? 0 : next;
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
    if (_index < _questions.length - 1) _show(_index + 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Footing style',
            style: TextStyle(
                fontSize: 20,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.blueGrey),
      ),
      body: _questions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _buildQuestion(context),
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
                onPressed: _index == _questions.length - 1
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
