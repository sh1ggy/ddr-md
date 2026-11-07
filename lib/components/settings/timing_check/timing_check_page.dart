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
import 'package:ddr_md/models/settings_model.dart';
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

enum _Stage { setup, practice, round, roundDone, result }

class _TimingCheckPageState extends State<TimingCheckPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _audio = TimingCheckAudio();
  final _stopwatch = Stopwatch();
  final _frame = ValueNotifier<double>(0);
  late final Ticker _ticker;
  _Stage _stage = _Stage.setup;
  TimingOptions _options = (
    judgement: Settings.getInt(Settings.timingJudgementKey),
    visual: Settings.getInt(Settings.timingVisualKey),
  );
  int _constant = switch (Settings.getInt(Settings.timingConstantKey)) {
    0 => 600,
    final saved => saved,
  };
  int _delay = Settings.getInt(Settings.timingDeviceDelayKey);
  late TapClock _clock;
  bool _loading = false;
  bool _ready = false;
  bool _interrupted = false;
  String? _error;
  List<TimingRound> _rounds = [];
  final _played = <TimingResult>[];
  late TimingResult _last;
  int _index = 0;
  late TimingOptions _practiceOptions;
  int _lastPracticeBeat = -1;
  double? _practiceError;
  double _feedbackUntil = 0;

  bool get _inPractice => _stage == _Stage.practice;

  TimingRound get _round => _rounds[_index];
  double get _elapsed => _stopwatch.elapsedMicroseconds / 1000;

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

  void _saveOptions(TimingOptions value) {
    _options = value;
    Settings.setInt(Settings.timingJudgementKey, value.judgement);
    Settings.setInt(Settings.timingVisualKey, value.visual);
  }

  void _saveDelay(int value) {
    _delay = value;
    if (_stage == _Stage.practice) _clock.delayMs = value;
    Settings.setInt(Settings.timingDeviceDelayKey, value);
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
    _rounds = TimingProtocol.rounds(math.Random());
    _played.clear();
    _index = 0;
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

  void _leavePractice() {
    _stop();
    setState(() => _stage = _Stage.setup);
  }

  void _startRound() {
    _startPlayback(muted: _round.cue == Cue.arrows);
    setState(() => _stage = _Stage.round);
  }

  void _startPlayback({bool practice = false, bool muted = false}) {
    _frame.value = 0;
    _clock = TapClock(_delay);
    _stopwatch
      ..reset()
      ..start();
    _interrupted = false;
    _audio.play(practice: practice, muted: muted);
    _ticker.start();
  }

  void _stop() {
    _stopwatch.stop();
    _ticker.stop();
    _audio.stop();
  }

  void _tick(Duration _) {
    final elapsed = _elapsed;
    if (_audio.position case final position?) {
      _clock.audioAt(elapsed, position);
    }
    final music = _clock.music(elapsed);
    if (_inPractice) {
      _frame.value = (music % practiceLoopMs) / 1000;
      if (_practiceError != null && elapsed >= _feedbackUntil) {
        setState(() => _practiceError = null);
      }
    } else if (music >= roundEndMs) {
      _stop();
      _finishRound();
    } else {
      _frame.value = math.max(music, 0) / 1000;
    }
  }

  void _tap([Duration? at]) {
    if (_interrupted) return;
    final elapsed = _elapsed;
    if (_inPractice) {
      final round = TimingRound(Cue.both, _practiceOptions);
      final (:index, :error) =
          round.matchTap(_clock.tap(elapsed, at), firstMs: 0);
      if (index <= _lastPracticeBeat) return;
      _lastPracticeBeat = index;
      _feedbackUntil = elapsed + 650;
      setState(() => _practiceError = error);
    } else if (_stage == _Stage.round) {
      _clock.tap(elapsed, at);
    }
  }

  void _finishRound() {
    final taps = TimingTaps(_round);
    _clock.taps.forEach(taps.add);
    _last = taps.finish();
    _played.add(_last);
    setState(() => _stage = _Stage.roundDone);
  }

  void _next() {
    if (_index + 1 < _rounds.length) {
      _index++;
      _startRound();
    } else {
      setState(() => _stage = _Stage.result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final testing = _stage == _Stage.round || _stage == _Stage.roundDone;
    return PopScope(
      canPop: !_inPractice,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _inPractice) _leavePractice();
      },
      child: Scaffold(
        appBar: AppBar(
          title: _inPractice ? const PageTitle('Timing Lab') : null,
          leading: _inPractice
              ? BackButton(onPressed: _leavePractice)
              : testing || _stage == _Stage.result
                  ? IconButton(
                      tooltip: testing ? 'Stop check' : 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
          actions: [
            if (testing)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text('ROUND ${_index + 1} / $baselineRounds',
                      style: FloorPop.readout(15,
                          color: FloorPop.of(context).haze)),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: switch (_stage) {
            _Stage.setup => _setup(),
            _Stage.practice => _practiceBody(),
            _Stage.round => _roundBody(),
            _Stage.roundDone => _roundDone(),
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: children,
          ),
        ),
      );

  Widget _panel(List<Widget> children, {String? title, String? aside}) {
    final pop = FloorPop.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: pop.stage, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: FloorPop.display(15)),
                    if (aside != null)
                      Text(aside,
                          style: TextStyle(color: pop.haze, fontSize: 12)),
                  ]),
            ),
          ...children,
        ],
      ),
    );
  }

  Widget _title(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: Align(
            alignment: Alignment.centerLeft,
            child: Lean(
                child: Text(text, style: FloorPop.display(36, color: color)))),
      );

  Widget _setup() {
    final pop = FloorPop.of(context);
    return _column([
      _title('Timing\nCheck'),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Text(
            'Tap along to a beat and scrolling arrows. You’ll learn whether '
            'you play by sight or by ear, and which cabinet dial to try first.',
            style: TextStyle(color: pop.haze, fontSize: 15, height: 1.45)),
      ),
      _panel([
        _adjust('CONSTANT', '$_constant', _constant, 100, 3000, 10, (value) {
          _constant = value;
          Settings.setInt(Settings.timingConstantKey, value);
        }),
        Text('Your usual read speed, in ms.',
            style: TextStyle(color: pop.haze, fontSize: 12)),
      ]),
      const SizedBox(height: 16),
      for (final (i, step) in const [
        'Tap through eight short rounds',
        'See which cue pulls your taps',
        'A recipe to confirm it on the cab',
      ].indexed)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Row(children: [
            SizedBox(
                width: 26,
                child: Text('${i + 1}',
                    style: FloorPop.readout(15, color: pop.voltText))),
            Expanded(child: Text(step)),
          ]),
        ),
      _panel([
        Row(children: [
          const Icon(Icons.headset_outlined, size: 20, color: FloorPop.sun),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  'Wired headphones or the device speaker. Bluetooth adds its '
                  'own delay. Tap the pad or press Space.',
                  style: TextStyle(color: pop.haze, fontSize: 13))),
        ]),
      ]),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      const SizedBox(height: 16),
      VoltButton(
        onPressed: _loading ? null : _start,
        child: Text(_loading ? 'Loading audio…' : 'Start · about 2 min'),
      ),
      const SizedBox(height: 8),
      GhostButton(
        onPressed: _loading ? null : _openPractice,
        child: const Text('Practice in Timing Lab'),
      ),
    ]);
  }

  List<Widget> _timingDials(
      TimingOptions options, ValueChanged<TimingOptions> onChanged) {
    return [
      _adjust('Judgement timing', _signed(options.judgement), options.judgement,
          -100, 100, 1, (value) {
        onChanged((judgement: value, visual: options.visual));
      }),
      _adjust('Visual timing', _signed(options.visual), options.visual, -100,
          100, 1, (value) {
        onChanged((judgement: options.judgement, visual: value));
      }),
    ];
  }

  Widget _adjust(String label, String readout, int value, int min, int max,
      int step, ValueChanged<int> onChanged) {
    final pop = FloorPop.of(context);
    void edit() async {
      final edited = await showDialog<int>(
        context: context,
        builder: (_) => _TimingNumberDialog(label, value, min, max, step),
      );
      if (mounted && edited != null) setState(() => onChanged(edited));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600))),
        DecoratedBox(
          decoration: BoxDecoration(
              color: pop.riser, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Decrease $label',
              onPressed: value > min
                  ? () => setState(() => onChanged(value - step))
                  : null,
              icon: const Icon(Icons.remove),
            ),
            TextButton(
              onPressed: edit,
              style: TextButton.styleFrom(
                  minimumSize: const Size(56, 44),
                  padding: EdgeInsets.zero,
                  foregroundColor: Theme.of(context).colorScheme.onSurface),
              child: Text(readout, style: FloorPop.readout(19)),
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
      ]),
    );
  }

  Widget _chip(String text, Color color) => Lean(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(8)),
          child: Upright(
              child: Text(text.toUpperCase(),
                  style: FloorPop.display(13, color: FloorPop.onVolt))),
        ),
      );

  static Color _cueColor(Cue cue) => switch (cue) {
        Cue.sound => FloorPop.coral,
        Cue.arrows => FloorPop.sun,
        Cue.both => FloorPop.volt,
      };

  Widget _progress() {
    final pop = FloorPop.of(context);
    return Row(spacing: 4, children: [
      for (var i = 0; i < baselineRounds; i++)
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: i < _index
                    ? FloorPop.volt
                    : i == _index
                        ? Theme.of(context).colorScheme.onSurface
                        : pop.line),
          ),
        ),
    ]);
  }

  Widget _roundBody() {
    final pop = FloorPop.of(context);
    if (_interrupted) {
      return _column([
        _title('Round\npaused'),
        const SizedBox(height: 14),
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _progress(),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _chip(_round.cue.label, _cueColor(_round.cue)),
                if (showArrows)
                  Text('CONSTANT $_constant',
                      style: FloorPop.readout(14, color: pop.haze)),
              ]),
              const SizedBox(height: 8),
              Text(
                  showArrows
                      ? 'Tap as each arrow reaches the receptors · any column'
                      : 'Tap on every drum hit. Eyes closed is fine.',
                  style: TextStyle(color: pop.haze)),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: showArrows
              ? TimingCheckChart(
                  playhead: _frame,
                  crossingMs: _round.crossingMs,
                  constantMs: _constant,
                )
              : _soundCue(),
        ),
        Expanded(flex: showArrows ? 1 : 3, child: _tapPad()),
      ],
    );
  }

  Widget _soundCue() {
    final pop = FloorPop.of(context);
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Flexible(
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: pop.line, width: 2)),
            child: const Icon(Icons.volume_up_outlined,
                size: 56, color: FloorPop.coral),
          ),
        ),
      ),
      const SizedBox(height: 12),
      ValueListenableBuilder(
        valueListenable: _frame,
        builder: (context, seconds, _) {
          final beat = (seconds * 1000 ~/ beatMs) - 1;
          final on = Theme.of(context).colorScheme.onSurface;
          return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 10,
              children: [
                for (var i = 0; i < countInBeats; i++)
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: i == beat
                            ? FloorPop.coral
                            : i < beat
                                ? on
                                : pop.line),
                  ),
              ]);
        },
      ),
      const SizedBox(height: 10),
      Text('Count-in · then $scoredBeats beats, 150 BPM',
          style: TextStyle(color: pop.haze, fontSize: 13)),
    ]);
  }

  Widget _roundDone() {
    final pop = FloorPop.of(context);
    return _column([
      Text(_last.round.cue.label.toUpperCase(), style: pop.label),
      _panel([
        _TapPlot(_last.hits),
        const SizedBox(height: 14),
        Divider(color: pop.line, height: 1),
        const SizedBox(height: 14),
        Row(children: [
          _stat('${_last.tightHits}', ' / $scoredBeats', 'Marvelous'),
          _stat('${_last.judgements[TapJudgement.miss]}', '', 'missed'),
        ]),
      ]),
      const SizedBox(height: 24),
      VoltButton(
        onPressed: _next,
        child: Text(_index + 1 < _rounds.length ? 'Next round' : 'See result'),
      ),
    ]);
  }

  Widget _stat(String value, String unit, String label) {
    final pop = FloorPop.of(context);
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: value, style: FloorPop.readout(22)),
          TextSpan(text: unit, style: FloorPop.readout(14, color: pop.haze)),
        ])),
        Text(label, style: TextStyle(color: pop.haze, fontSize: 12)),
      ]),
    );
  }

  Widget _practiceBody() {
    if (_interrupted) {
      return _column([
        _title('Practice\npaused'),
        const SizedBox(height: 16),
        VoltButton(
            onPressed: _startPractice, child: const Text('Resume practice')),
      ]);
    }
    final pop = FloorPop.of(context);
    final error = _practiceError;
    final grade = error == null ? null : TapJudgement.forError(error);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('UNSCORED · MOVE DEVICE DELAY UNTIL ARROWS LAND ON THE KICK',
              style: pop.label),
          const SizedBox(height: 8),
          _adjust(
              'Device audio delay', '$_delay', _delay, 0, 300, 1, _saveDelay),
          ..._timingDials(_practiceOptions, (value) {
            _practiceOptions = value;
            _saveOptions(value);
          }),
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
          if (event is KeyDownEvent) _tap(event.timeStamp);
          return KeyEventResult.handled;
        },
        child: Semantics(
          button: true,
          label: 'Tap',
          onTap: _tap,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) => _tap(event.timeStamp),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: pop.stage,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: pop.line, width: 2),
                boxShadow: [
                  BoxShadow(color: pop.riser, offset: const Offset(0, 6))
                ],
              ),
              child: Center(
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 14,
                        children: [
                          const PadGlyph(size: 40, lit: true),
                          Text('TAP', style: FloorPop.display(22)),
                        ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _results() {
    final pop = FloorPop.of(context);
    final type = TimingProtocol.type(_played);
    final follow = TimingProtocol.follow(_played);
    final (title, why, step) = switch (type) {
      PlayerType.visual => (
          'Visual\nplayer',
          'When the arrows moved, your taps moved with them.',
          'Try visual timing first.',
        ),
      PlayerType.audio => (
          'Audio\nplayer',
          'When the arrows moved, your taps stayed with the beat.',
          'Try judgement timing first.',
        ),
      PlayerType.both => (
          'A bit of\nboth',
          'Your taps followed the arrows part of the way.',
          'Either dial could help. Try visual timing first.',
        ),
      null => (
          'Couldn’t\ntell',
          'Too many taps were off the beat to read a pattern.',
          'Run it again when you’re settled in.',
        ),
    };
    return _column([
      _title(title, color: type == null ? null : pop.voltText),
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(why,
            style: TextStyle(color: pop.haze, fontSize: 15, height: 1.45)),
      ),
      if (follow != null)
        _panel(title: 'What pulls your taps', [
          _PullRow('Arrows moved earlier', -pullShiftMs, -follow * pullShiftMs),
          const SizedBox(height: 12),
          _PullRow('Arrows moved later', pullShiftMs, follow * pullShiftMs),
        ]),
      _panel(title: 'Check it on the cab', [
        Text(step, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (type != null)
          Text(
              'Same easy chart, cabinet and side. Play it twice as you are, '
              'then twice with that dial moved a little each way. Keep '
              'whatever scores and feels better.',
              style: TextStyle(color: pop.haze, fontSize: 13, height: 1.4)),
      ]),
      const SizedBox(height: 18),
      VoltButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Done'),
      ),
      const SizedBox(height: 8),
      GhostButton(
        onPressed: () => setState(() => _stage = _Stage.setup),
        child: const Text('Run again'),
      ),
    ]);
  }
}

class _PullRow extends StatelessWidget {
  const _PullRow(this.label, this.arrows, this.taps);
  final String label;
  final int arrows;
  final double taps;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    Widget bar(double ms, Color color) => Align(
          alignment: ms < 0 ? Alignment.centerRight : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (ms.abs() / (2 * pullShiftMs)).clamp(0, 1),
            child: Container(
                height: 7,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(4))),
          ),
        );
    Widget side(bool left) => Expanded(
            child: Column(spacing: 4, children: [
          if ((arrows < 0) == left) ...[
            bar(arrows.toDouble(), FloorPop.padBlue),
            bar(taps, FloorPop.sun),
          ] else
            const SizedBox(height: 18),
        ]));
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: pop.haze, fontSize: 13)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        side(true),
        Container(width: 2, height: 18, color: pop.line),
        side(false),
      ]),
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
