/// Name: ParityQuizPage
/// Parent: SettingsPage
/// Description: The footing-style questionnaire. One real-chart moment at a
/// time, each footing option drawn as a small chart read bottom to top; tap the
/// one you'd dance. Answers are kept for fitting the player's parity profile.
library;

import 'package:ddr_md/components/song/notes/chart_models.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/parity.dart';
import 'package:ddr_md/models/parity_quiz.dart';
import 'package:flutter/material.dart';

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

class _ParityQuizPageState extends State<ParityQuizPage> {
  List<QuizQuestion> _questions = const [];
  Map<String, int> _answers = {};
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _answers = QuizAnswers.read();
    QuizQuestion.load().then((qs) {
      if (!mounted) return;
      setState(() {
        _questions = qs;
        // Resume at the first unanswered question.
        final next = qs.indexWhere((q) => !_answers.containsKey(q.id));
        _index = next < 0 ? 0 : next;
      });
    });
  }

  // Options are shown rotated per question so the engine's reading (option 0
  // in the data) isn't always in the same place.
  List<int> _order(int questionIndex, int count) =>
      [for (int k = 0; k < count; k++) (k + questionIndex) % count];

  void _choose(QuizQuestion q, int option) {
    setState(() {
      _answers = {..._answers, q.id: option};
      QuizAnswers.write(_answers);
      if (_index < _questions.length - 1) _index++;
    });
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
                onPressed:
                    _index == 0 ? null : () => setState(() => _index--),
              ),
              Text('${_index + 1}/${_questions.length}',
                  style: const TextStyle(color: Colors.blueGrey)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _index == _questions.length - 1
                    ? null
                    : () => setState(() => _index++),
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
    required this.selected,
    required this.onTap,
  });

  final QuizQuestion question;
  final int option;
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
        child: CustomPaint(
          painter: _MiniChart(question, option),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// One option's footing as a small chart: lanes L D U R, earliest row at the
/// bottom, rows spaced by their real timing so tempo reads as distance.
class _MiniChart extends CustomPainter {
  _MiniChart(this.question, this.option);

  final QuizQuestion question;
  final int option;

  static const _glyphs = [
    Icons.arrow_back_rounded,
    Icons.arrow_downward_rounded,
    Icons.arrow_upward_rounded,
    Icons.arrow_forward_rounded,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rows = question.rows;
    final first = rows.first.second, last = rows.last.second;
    final lane = size.width / 4;
    final glyph = lane * 0.8;
    final pad = glyph * 0.8;
    double yFor(double s) => last == first
        ? size.height / 2
        : size.height - pad - (s - first) / (last - first) * (size.height - 2 * pad);

    for (final row in rows) {
      final y = yFor(row.second);
      if (row.key) {
        canvas.drawRect(
            Rect.fromCenter(
                center: Offset(size.width / 2, y),
                width: size.width,
                height: glyph * 1.2),
            Paint()..color = Colors.white.withValues(alpha: 0.06));
      }
      for (final n in row.notes) {
        final color = n.feet[option] == ParityFoot.left
            ? kLeftFootColor
            : kRightFootColor;
        final x = lane * n.col + lane / 2;
        if (n.hold) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(x - glyph * 0.12, y - glyph * 1.2,
                      glyph * 0.24, glyph * 1.2),
                  Radius.circular(glyph * 0.12)),
              Paint()..color = color.withValues(alpha: 0.35));
        }
        final icon = _glyphs[n.col % 4];
        final tp = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
                fontSize: glyph,
                fontFamily: icon.fontFamily,
                package: icon.fontPackage,
                color: color),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_MiniChart old) =>
      old.question != question || old.option != option;
}
