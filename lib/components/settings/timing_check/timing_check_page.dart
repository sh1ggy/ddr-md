/// Name: TimingCheckPage
/// Parent: AppSettingsPage
/// Description: Runs the tap test and shows the cabinet comparison to try.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/song/notes/ddr_atlas.dart';
import 'package:ddr_md/components/song/notes/noteskin.dart';
import 'package:ddr_md/constants.dart' show kFastColor, kSlowColor;
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'timing_check_audio.dart';
import 'timing_check_chart.dart';
import 'timing_check_protocol.dart';

String _signed(int ms) => ms < 0 ? '−${-ms}' : '+$ms';

class TimingCheckPage extends StatefulWidget {
  const TimingCheckPage({super.key});

  @override
  State<TimingCheckPage> createState() => _TimingCheckPageState();
}

enum _Stage { setup, practice, round, result }

class _TimingCheckPageState extends State<TimingCheckPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _audio = TimingCheckAudio();
  final _clock = Stopwatch();
  final _frame = ValueNotifier<double>(0);
  late final Ticker _ticker;
  _Stage _stage = _Stage.setup;
  TimingOptions _options = (judgement: 0, visual: 0);
  int _constant = 600;
  bool _loading = false;
  bool _ready = false;
  bool _interrupted = false;
  bool _countIn = true;
  String? _error;
  late TimingProtocol _protocol;
  List<TimingRound> _rounds = [];
  final _baseline = <TimingResult>[];
  final _faceOff = <TimingResult>[];
  late Map<TimingDial, TimingOptions> _candidates;
  late TimingTaps _taps;
  int _index = 0;
  bool _faceOffOnly = false;
  late TimingOptions _practiceOptions;
  int _lastPracticeBeat = -1;
  double? _practiceError;
  double _feedbackUntil = 0;

  bool get _inPractice => _stage == _Stage.practice;

  TimingRound get _round => _rounds[_index];
  double get _elapsed => _clock.elapsedMicroseconds / 1000;
  int get _roundCount =>
      _faceOffOnly ? faceOffRounds : baselineRounds + faceOffRounds;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    if (!_loading) unawaited(_audio.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        (_stage != _Stage.round && !_inPractice) ||
        _interrupted) {
      return;
    }
    _stop();
    setState(() => _interrupted = true);
  }

  Future<bool> _prepare() async {
    if (_loading) return false;
    if (!_ready) {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        await Future.wait([
          _audio.load(),
          SpriteNoteskin.tryLoad(),
          DdrAtlas.tryLoad(),
        ]);
      } catch (_) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Audio could not start. Try again.';
          });
        } else {
          await _audio.dispose();
        }
        return false;
      }
      if (!mounted) {
        await _audio.dispose();
        return false;
      }
      _loading = false;
      _ready = true;
      if (WidgetsBinding.instance.lifecycleState case final state?
          when state != AppLifecycleState.resumed) {
        setState(() {});
        return false;
      }
    }
    return true;
  }

  Future<void> _start() async {
    if (!await _prepare() || !mounted) return;
    _protocol = TimingProtocol(_options, math.Random());
    _rounds = _protocol.baseline();
    _baseline.clear();
    _faceOff.clear();
    _index = 0;
    _faceOffOnly = false;
    _startRound();
  }

  Future<void> _openPractice() async {
    if (!await _prepare() || !mounted) return;
    _practiceOptions = _options;
    _startPractice();
  }

  void _startPractice() {
    _lastPracticeBeat = -1;
    _practiceError = null;
    _startPlayback(practice: true);
    setState(() => _stage = _Stage.practice);
  }

  void _leavePractice({bool useSettings = false}) {
    _stop();
    setState(() {
      if (useSettings) _options = _practiceOptions;
      _stage = _Stage.setup;
    });
  }

  void _startRound() {
    _taps = TimingTaps(_round);
    _startPlayback();
    setState(() {
      _countIn = true;
      _stage = _Stage.round;
    });
  }

  void _startPlayback({bool practice = false}) {
    _frame.value = 0;
    _clock
      ..reset()
      ..start();
    _interrupted = false;
    _audio.play(practice: practice);
    _ticker.start();
  }

  void _stop() {
    _clock.stop();
    _ticker.stop();
    _audio.stop();
  }

  void _tick(Duration _) {
    final elapsed = _elapsed;
    if (_inPractice) {
      _frame.value = (elapsed % practiceLoopMs) / 1000;
      if (_practiceError != null && elapsed >= _feedbackUntil) {
        setState(() => _practiceError = null);
      }
    } else if (elapsed >= roundEndMs) {
      _stop();
      _finishRound();
    } else {
      _frame.value = elapsed / 1000;
      if (_countIn && elapsed >= firstBeatMs - beatMs ~/ 2) {
        setState(() => _countIn = false);
      }
    }
  }

  void _tap() {
    if (_interrupted) return;
    final elapsed = _elapsed;
    if (_inPractice) {
      final round = TimingRound(Cue.both, _practiceOptions);
      final (:index, :error) = round.matchTap(elapsed, firstMs: 0);
      if (index <= _lastPracticeBeat) return;
      _lastPracticeBeat = index;
      _feedbackUntil = elapsed + 650;
      setState(() => _practiceError = error);
    } else if (_stage == _Stage.round && elapsed < roundEndMs) {
      _taps.add(elapsed);
    }
  }

  void _finishRound() {
    final result = _taps.finish();
    if (_round.dial == null) {
      _baseline.add(result);
      if (_baseline.length == baselineRounds) {
        _candidates = _protocol.candidates(_baseline);
        _rounds.addAll(_protocol.faceOff(_candidates));
      }
    } else {
      _faceOff.add(result);
    }
    if (_index + 1 < _rounds.length) {
      _index++;
      _startRound();
    } else {
      setState(() => _stage = _Stage.result);
    }
  }

  void _repeatFaceOff() {
    _rounds = _protocol.faceOff(_candidates);
    _faceOff.clear();
    _index = 0;
    _faceOffOnly = true;
    _startRound();
  }

  @override
  Widget build(BuildContext context) {
    final testing = _stage == _Stage.round;
    return PopScope(
      canPop: !_inPractice,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _inPractice) _leavePractice();
      },
      child: Scaffold(
        appBar: AppBar(
          title: PageTitle(_inPractice
              ? 'Timing Lab'
              : testing
                  ? 'Round ${_index + 1} / $_roundCount'
                  : 'Timing Check'),
          leading: _inPractice
              ? BackButton(onPressed: _leavePractice)
              : testing
                  ? IconButton(
                      tooltip: 'Stop check',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
          actions: [
            if (_inPractice)
              TextButton(
                onPressed: () => _leavePractice(useSettings: true),
                child: const Text('Use settings'),
              ),
          ],
        ),
        body: SafeArea(
          child: switch (_stage) {
            _Stage.setup => _setup(),
            _Stage.practice => _practiceBody(),
            _Stage.round => _roundBody(),
            _Stage.result => _results(),
          },
        ),
      ),
    );
  }

  Widget _column(List<Widget> children) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            key: ValueKey(_stage),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            children: children,
          ),
        ),
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _setup() => _column([
        Text('Tap to the beat.', style: FloorPop.display(25)),
        const SizedBox(height: 12),
        const Text('Find which cabinet timing dial to try first.'),
        _heading('What you play on now'),
        ..._timingDials(_options, (value) => _options = value),
        _adjust('CONSTANT', '$_constant ms', _constant, 100, 3000, 10,
            (value) => _constant = value),
        _heading('How it works'),
        const Text('Tap to sound first, then sound and arrows. Six rounds run '
            'back to back, with a count-in before each. You’ll see your DDR '
            'judgements and which cabinet setting to try at the end.'),
        const SizedBox(height: 16),
        const Text('Use wired headphones or the device speaker. Bluetooth '
            'adds delay. Tap the pad or press Space on a keyboard.'),
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Text(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 20),
        VoltButton(
          onPressed: _loading ? null : _start,
          child: Text(_loading ? 'Loading audio…' : 'Start · about 50 seconds'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _loading ? null : _openPractice,
          child: const Text('Practice in Timing Lab'),
        ),
      ]);

  List<Widget> _timingDials(
      TimingOptions options, ValueChanged<TimingOptions> onChanged) {
    return [
      _adjust('Judgement timing', '${_signed(options.judgement)} ms',
          options.judgement, -100, 100, 1, (value) {
        onChanged((judgement: value, visual: options.visual));
      }),
      _adjust('Visual timing', '${_signed(options.visual)} ms', options.visual,
          -100, 100, 1, (value) {
        onChanged((judgement: options.judgement, visual: value));
      }),
    ];
  }

  Widget _adjust(String label, String readout, int value, int min, int max,
      int step, ValueChanged<int> onChanged) {
    void edit() async {
      final edited = await showDialog<int>(
        context: context,
        builder: (_) => _TimingNumberDialog(label, value, min, max, step),
      );
      if (mounted && edited != null) setState(() => onChanged(edited));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(children: [
          Expanded(child: Text(label)),
          IconButton(
            tooltip: 'Decrease $label',
            onPressed: value > min
                ? () => setState(() => onChanged(value - step))
                : null,
            icon: const Icon(Icons.remove),
          ),
          TextButton(
            onPressed: edit,
            child: Text(readout, style: FloorPop.readout(18)),
          ),
          IconButton(
            tooltip: 'Increase $label',
            onPressed: value < max
                ? () => setState(() => onChanged(value + step))
                : null,
            icon: const Icon(Icons.add),
          ),
        ]),
      ),
    );
  }

  Widget _roundBody() {
    final pop = FloorPop.of(context);
    if (_interrupted) {
      return _column([
        _heading('Round paused'),
        const Text('Restart this round when you’re ready.'),
        const SizedBox(height: 16),
        VoltButton(onPressed: _startRound, child: const Text('Restart round')),
      ]);
    }
    final showArrows = _round.cue != Cue.sound;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_round.cue.label, style: FloorPop.display(24)),
              const SizedBox(height: 4),
              Text(showArrows
                  ? 'Tap as each arrow reaches the receptors · any column'
                  : 'Tap on every drum hit. Eyes closed is fine.'),
              const SizedBox(height: 6),
              Text(
                '${_countIn ? 'COUNT-IN · ' : ''}16 BEATS · 150 BPM'
                '${showArrows ? ' · CONSTANT $_constant' : ''}',
                style: pop.label,
              ),
            ],
          ),
        ),
        if (showArrows)
          Expanded(
            flex: 4,
            child: TimingCheckChart(
              playhead: _frame,
              crossingMs: _round.crossingMs,
              constantMs: _constant,
            ),
          ),
        Expanded(child: _tapPad()),
      ],
    );
  }

  Widget _practiceBody() {
    if (_interrupted) {
      return _column([
        _heading('Practice paused'),
        VoltButton(
            onPressed: _startPractice, child: const Text('Resume practice')),
      ]);
    }
    final pop = FloorPop.of(context);
    final error = _practiceError;
    final grade = error == null ? null : TapJudgement.forError(error);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('UNSCORED PRACTICE · 150 BPM', style: pop.label),
          ..._timingDials(
              _practiceOptions, (value) => _practiceOptions = value),
        ],
      ),
    );
    final chart = TimingCheckChart(
      playhead: _frame,
      crossingMs: TimingRound(Cue.both, _practiceOptions).crossingMs,
      constantMs: _constant,
      practice: true,
    );
    final feedback = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: grade?.label ?? 'Tap to the beat',
                style: TextStyle(
                  color: grade == null ? null : _judgementColor(grade, pop),
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (error != null)
                TextSpan(
                  text: error.abs() < 0.5
                      ? '  ON TIME'
                      : '  ${error < 0 ? 'FAST' : 'SLOW'} ${error.abs().round()} ms',
                  style: TextStyle(
                    color: error.abs() < 0.5
                        ? null
                        : error < 0
                            ? kFastColor(isDark)
                            : kSlowColor(isDark),
                  ),
                ),
            ],
          ),
          style: FloorPop.readout(22),
        ),
      ),
    );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 600 && constraints.maxHeight < 450) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: chart),
            SizedBox(
              width: 300,
              child: Column(
                children: [controls, feedback, Expanded(child: _tapPad())],
              ),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          controls,
          Expanded(flex: 3, child: chart),
          feedback,
          Expanded(child: _tapPad()),
        ],
      );
    });
  }

  Widget _tapPad() {
    final pop = FloorPop.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event.logicalKey != LogicalKeyboardKey.space) {
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent) _tap();
          return KeyEventResult.handled;
        },
        child: Semantics(
          button: true,
          onTap: _tap,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _tap(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: pop.stage,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: pop.line, width: 2),
              ),
              child: Center(
                child: Text('TAP', style: FloorPop.display(28)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _results() {
    final winner = TimingProtocol.winner(_faceOff);
    final recommended = winner == null ? null : _candidates[winner]!;
    final follow = TimingProtocol.follow(_baseline);
    final early = _baseline.firstWhere((r) => r.round.pullMs < 0);
    final late = _baseline.firstWhere((r) => r.round.pullMs > 0);
    final current =
        'J ${_signed(_options.judgement)} · V ${_signed(_options.visual)}';
    final trial = recommended == null
        ? null
        : 'J ${_signed(recommended.judgement)} · V ${_signed(recommended.visual)}';
    final target = recommended == null
        ? null
        : winner == TimingDial.judgement
            ? recommended.judgement
            : recommended.visual;
    String shift(TimingResult r, double baseline) => r.center == null
        ? 'No taps'
        : '${_signed((r.center! - baseline).round())} ms';
    final both = TimingProtocol.estimatedCenter(_baseline);

    return _column([
      if (winner != null) const Text('TRY FIRST'),
      Text(winner?.label ?? 'No clear winner', style: FloorPop.display(32)),
      const SizedBox(height: 8),
      Text(
          target == null
              ? 'Keep $current for now.'
              : 'Start at ${_signed(target)} ms',
          style: FloorPop.readout(24, color: FloorPop.of(context).voltText)),
      _heading('What pulls your taps'),
      if (follow == null || both == null)
        const Text('More taps are needed to estimate arrow pull.')
      else ...[
        Text('Arrows $pullShiftMs ms earlier · taps ${shift(early, both)}'),
        Text('Arrows $pullShiftMs ms later · taps ${shift(late, both)}'),
        Text(follow < 0 || follow > 1
            ? 'Arrow pull varied outside the expected range.'
            : 'About ${(follow * 100).round()}% arrow follow'),
      ],
      _heading('Face-off'),
      const Text('Each dot is a tap. Judgements are estimated from the tap’s '
          'distance from the target. Average error includes missed beats.'),
      for (final dial in TimingDial.values)
        _RoundJudgements(
          _faceOff.singleWhere((r) => r.round.dial == dial),
          title: dial.label,
          detail: switch (dial) {
            TimingDial.current => current,
            TimingDial.judgement =>
              'J ${_signed(_candidates[dial]!.judgement)}',
            TimingDial.visual => 'V ${_signed(_candidates[dial]!.visual)}',
          },
        ),
      const SizedBox(height: 8),
      Text(winner == null
          ? 'A setting needs a clear gain in both halves of the round without '
              'losing Marvelous or Perfect hits overall.'
          : 'This setting brought taps closer to the target in both halves '
              'of the round and kept or improved your Marvelous and Perfect total.'),
      Card(
        child: ExpansionTile(
          title: const Text('Cue rounds'),
          children: [
            for (final result in _baseline)
              _RoundJudgements(
                result,
                title: result.round.cue.label,
                detail: result.round.pullMs == 0
                    ? null
                    : 'Arrows ${result.round.pullMs.abs()} ms '
                        '${result.round.pullMs < 0 ? 'earlier' : 'later'}',
              ),
          ],
        ),
      ),
      _heading('Check it on the cab'),
      Text('Use the same easy chart, cabinet and side at CONSTANT $_constant. '
          'The phone measures your taps on this device.'),
      const SizedBox(height: 8),
      Text(trial == null
          ? 'Start with two plays at $current. If it still feels off, change '
              'one dial by 5 ms and play twice more to compare.'
          : '1. Play twice at $current.\n'
              '2. Play twice at $trial.\n'
              '3. If it feels better, try 5 ms either way. If it feels worse, go back.'),
      const SizedBox(height: 20),
      VoltButton(
        onPressed:
            winner == null ? _repeatFaceOff : () => Navigator.of(context).pop(),
        child: Text(
            winner == null ? 'Face-off again · $faceOffRounds rounds' : 'Done'),
      ),
      TextButton(
        onPressed: winner == null
            ? () => Navigator.of(context).pop()
            : () => setState(() => _stage = _Stage.setup),
        child: Text(winner == null ? 'Done' : 'Run again'),
      ),
    ]);
  }
}

class _TimingNumberDialog extends StatefulWidget {
  const _TimingNumberDialog(
      this.label, this.value, this.min, this.max, this.step);
  final String label;
  final int value, min, max, step;

  @override
  State<_TimingNumberDialog> createState() => _TimingNumberDialogState();
}

class _TimingNumberDialogState extends State<_TimingNumberDialog> {
  late final _controller = TextEditingController(text: '${widget.value}')
    ..selection =
        TextSelection(baseOffset: 0, extentOffset: '${widget.value}'.length);

  int? get _valid {
    final value = int.tryParse(_controller.text.trim());
    if (value == null ||
        value < widget.min ||
        value > widget.max ||
        value % widget.step != 0) {
      return null;
    }
    return value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.label),
        content: TextField(
          autofocus: true,
          controller: _controller,
          keyboardType: TextInputType.numberWithOptions(signed: widget.min < 0),
          decoration: InputDecoration(
            suffixText: 'ms',
            helperText: '${widget.min} to ${widget.max} · step ${widget.step}',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_valid != null) Navigator.of(context).pop(_valid);
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed:
                _valid == null ? null : () => Navigator.of(context).pop(_valid),
            child: const Text('Set'),
          ),
        ],
      );
}

Color _judgementColor(TapJudgement grade, FloorPop pop) => switch (grade) {
      TapJudgement.marvelous => pop.voltText,
      TapJudgement.perfect => pop.sunText,
      TapJudgement.great => pop.up,
      TapJudgement.good => FloorPop.padBlue,
      TapJudgement.miss => pop.down,
    };

class _RoundJudgements extends StatelessWidget {
  const _RoundJudgements(this.result, {required this.title, this.detail});

  final TimingResult result;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final center = result.center;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text([
              if (detail != null) detail!,
              if (center != null) '${_signed(center.round())} ms median',
              '${result.meanError.round()} ms avg. error',
            ].join(' · ')),
            const SizedBox(height: 8),
            _TapPlot(result.hits),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final entry in result.judgements.entries)
                  Text('${entry.key.label} ${entry.value}',
                      style: TextStyle(color: _judgementColor(entry.key, pop))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TapPlot extends StatelessWidget {
  const _TapPlot(this.hits);

  final List<double> hits;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final range = hits.fold(TapJudgement.good.limitMs,
        (max, hit) => math.max(max, hit.abs().ceil()));
    return Column(
      children: [
        SizedBox(
          height: 42,
          width: double.infinity,
          child: CustomPaint(painter: _TapPlotPainter(hits, range, pop)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('−$range early'),
            const Text('0'),
            Text('late +$range')
          ],
        ),
      ],
    );
  }
}

class _TapPlotPainter extends CustomPainter {
  const _TapPlotPainter(this.hits, this.range, this.pop);

  final List<double> hits;
  final int range;
  final FloorPop pop;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double ms) => 5 + (ms + range) / (2 * range) * (size.width - 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      Paint()..color = pop.riser,
    );
    canvas.drawRect(
      Rect.fromLTRB(x(-TapJudgement.marvelous.limitMs.toDouble()), 0,
          x(TapJudgement.marvelous.limitMs.toDouble()), size.height),
      Paint()..color = pop.voltText.withValues(alpha: 0.14),
    );
    canvas.drawLine(
        Offset(x(0), 0), Offset(x(0), size.height), Paint()..color = pop.haze);
    final dot = Paint();
    for (final (index, hit) in hits.indexed) {
      dot.color = _judgementColor(TapJudgement.forError(hit), pop);
      canvas.drawCircle(Offset(x(hit), 7 + 7 * (index % 5).toDouble()), 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _TapPlotPainter oldDelegate) =>
      oldDelegate.hits != hits ||
      oldDelegate.range != range ||
      oldDelegate.pop != pop;
}
