/// Name: TickClock
/// Parent: chart_scroller.dart
/// Description: Sample-accurate assist-tick scheduler for the chart preview.
///
/// The chart preview scrolls silently and pings a short "tick" sample as each
/// note row crosses the receptors. Under dense streams the render loop can't be
/// the timing source — frames get long exactly when notes are closest together,
/// so scheduling ticks on frame boundaries drops or smears them. `audioplayers`
/// can't fix this either: it has no scheduling API, only fire-and-forget play.
///
/// This module drives the tick off SoLoud's audio-thread clock instead of the
/// render loop. SoLoud runs a dedicated mixing thread whose position (via
/// [SoLoud.getPosition] on an always-running silent "clock" voice) advances
/// smoothly regardless of UI jank. A short-period poller reads that clock and
/// releases each tick when the clock reaches the row's timestamp, one voice per
/// row, from a pre-primed pool of paused voices so no decode/setup happens at
/// fire time. The residual error is bounded by the poll period (sub-frame,
/// consistent), not by frame timing — which is what "predictable" requires.
///
/// The SoLoud Dart binding does not expose the engine's native clocked-play
/// (delay-by-samples) primitive, so this is the tightest scheduling available
/// without patching the plugin. If that primitive is ever surfaced, the poller
/// can be replaced with a single scheduled release per row.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

/// Owns the SoLoud engine lifecycle and the tick sample, and schedules ticks
/// against the audio clock. One instance per chart-scroller state; [dispose]
/// releases the sample and the clock voice (the shared engine stays up).
class TickClock {
  TickClock();

  /// The decoded tick sample. Null until [load] completes or if loading failed
  /// (then every schedule call is a silent no-op — the toggle just does nothing).
  AudioSource? _sample;

  /// An always-playing, muted, NON-looping voice over a long silent buffer.
  /// Its [SoLoud.getPosition] is the monotonic audio-thread clock we schedule
  /// against. It must not loop: [SoLoud.getPosition] reports the offset within
  /// the current loop, so a looping carrier would wrap to zero periodically and
  /// desync every tick after the first wrap. The buffer is [_clockLengthSeconds]
  /// long — comfortably past any chart — so it never runs out mid-preview.
  SoundHandle? _clockVoice;
  AudioSource? _clockSource;

  /// Length of the silent clock carrier. Longer than any real chart; a stepped
  /// song tops out around 10 minutes, so 30 leaves generous headroom.
  static const int _clockLengthSeconds = 30 * 60;
  static const int _clockSampleRate = 8000; // clock reads position, not audio

  /// Row timestamps (chart seconds, ascending) that should tick, and the index
  /// of the next row we haven't scheduled yet. Only trusted while [_anchored]:
  /// a seek/rate change/pause clears the anchor and forces a re-seat.
  List<double> _rows = const [];
  int _cursor = 0;
  bool _anchored = false;

  /// Maps chart-seconds to clock-voice-seconds. When playback (re)starts we
  /// anchor the audio clock's current reading to the current chart position and
  /// note the rate, so `clockSecond = _clockAtAnchor + (chartSecond - _chartAtAnchor)/rate`.
  double _chartAtAnchor = 0;
  double _clockAtAnchor = 0;
  double _rate = 1.0;

  /// The poller. Runs only while ticks are pending; a tight period so the
  /// release lands within a fraction of a frame of the true row time.
  Timer? _poller;
  static const Duration _pollPeriod = Duration(milliseconds: 4);

  /// How far ahead of the clock we pre-prime a paused voice for a row, so the
  /// release is just an unpause (no decode/voice-alloc at fire time). Must
  /// exceed one poll period comfortably.
  static const double _primeLead = 0.05;

  /// Voices primed-but-not-yet-fired, keyed by the row index they belong to.
  final Map<int, SoundHandle> _primed = {};

  bool get isReady => _sample != null && _clockVoice != null;

  // --- test hooks (integration_test/tick_clock_test.dart) ---
  void Function(double chartSecond, double clockError)? _onFire;
  int _firedCount = 0;

  /// Current audio-clock reading in seconds; null if the clock isn't up.
  double? debugClockSecond() => _clockSecond();

  /// Register a callback fired at each tick release with (row chart-second,
  /// clock error in seconds — negative means fired early, positive late).
  void debugSetOnFire(void Function(double, double) cb) => _onFire = cb;

  /// How many ticks have been released since load.
  int get debugFiredCount => _firedCount;

  /// Initialise the shared engine (idempotent across instances) and decode the
  /// tick. Also starts the silent clock voice. Safe to call once per state.
  Future<void> load(String assetPath) async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      // Low latency + a small buffer: we want the unpause→sound gap tight.
      await soloud.init(lowLatency: true, bufferSize: 1024);
    }
    _sample = await soloud.loadAsset(assetPath);

    // A long silent buffer, played once (no loop), is the monotonic clock. We
    // synthesise it in memory rather than bundling an asset — it's pure silence
    // and only its position is ever read.
    _clockSource = await soloud.loadMem(
      "tick_clock_silence.wav",
      _silentWav(_clockLengthSeconds, _clockSampleRate),
    );
    final clock = soloud.play(_clockSource!, volume: 0);
    // Keep the mixer from evicting the clock voice under polyphony pressure.
    soloud.setProtectVoice(clock, true);
    _clockVoice = clock;
  }

  /// A mono 16-bit PCM WAV of pure silence, [seconds] long at [sampleRate]. All
  /// sample bytes are zero; only the 44-byte header carries real data.
  static Uint8List _silentWav(int seconds, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    final dataBytes = seconds * byteRate;
    final buf = Uint8List(44 + dataBytes);
    final bd = ByteData.view(buf.buffer);
    // "RIFF" <chunkSize> "WAVE"
    buf.setAll(0, 'RIFF'.codeUnits);
    bd.setUint32(4, 36 + dataBytes, Endian.little);
    buf.setAll(8, 'WAVE'.codeUnits);
    // "fmt " sub-chunk (PCM)
    buf.setAll(12, 'fmt '.codeUnits);
    bd.setUint32(16, 16, Endian.little); // sub-chunk size
    bd.setUint16(20, 1, Endian.little); // audio format = PCM
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    // "data" sub-chunk — the samples are already zero-filled.
    buf.setAll(36, 'data'.codeUnits);
    bd.setUint32(40, dataBytes, Endian.little);
    return buf;
  }

  /// Current audio-clock reading in seconds, or null if the clock isn't up.
  double? _clockSecond() {
    final v = _clockVoice;
    if (v == null) return null;
    final soloud = SoLoud.instance;
    if (!soloud.getIsValidVoiceHandle(v)) return null;
    return soloud.getPosition(v).inMicroseconds / 1e6;
  }

  /// Install the row list (ascending chart-seconds). Clears any schedule.
  void setRows(List<double> rows) {
    _rows = rows;
    _reset();
  }

  /// Begin (or resume) scheduling: anchor the chart→clock mapping at
  /// [chartSecond] with playback [rate], re-seat the cursor to the first row
  /// after [chartSecond], and start polling. Call on play, and after any seek
  /// or rate change while playing.
  void start({required double chartSecond, required double rate}) {
    if (!isReady) return;
    final clockNow = _clockSecond();
    if (clockNow == null) return;
    _cancelPrimed();
    _chartAtAnchor = chartSecond;
    _clockAtAnchor = clockNow;
    _rate = rate <= 0 ? 1.0 : rate;
    _cursor = _firstRowAfter(chartSecond);
    _anchored = true;
    _ensurePolling();
  }

  /// Stop scheduling and drop any primed-but-unfired voices (they must not
  /// sound past a pause/seek). The clock voice and sample stay loaded.
  void stop() => _reset();

  void _reset() {
    _anchored = false;
    _cursor = 0;
    _cancelPrimed();
    _poller?.cancel();
    _poller = null;
  }

  void _cancelPrimed() {
    if (_primed.isEmpty) return;
    final soloud = SoLoud.instance;
    for (final h in _primed.values) {
      soloud.stop(h);
    }
    _primed.clear();
  }

  int _firstRowAfter(double chartSecond) {
    int lo = 0, hi = _rows.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_rows[mid] <= chartSecond) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Convert a chart-second to the audio clock's timeline via the current anchor.
  double _rowClockSecond(double chartSecond) =>
      _clockAtAnchor + (chartSecond - _chartAtAnchor) / _rate;

  void _ensurePolling() {
    _poller ??= Timer.periodic(_pollPeriod, (_) => _pump());
  }

  /// One poll: prime voices for rows entering the lead window, release any
  /// whose clock time has arrived, and stop polling once the stream is done.
  void _pump() {
    if (!_anchored || _sample == null) return;
    final clockNow = _clockSecond();
    if (clockNow == null) return;
    final soloud = SoLoud.instance;

    // Prime upcoming rows: give the mixer a paused voice ahead of time so the
    // release is a cheap unpause. Walk the cursor over rows within the lead.
    while (_cursor < _rows.length &&
        _rowClockSecond(_rows[_cursor]) <= clockNow + _primeLead) {
      final idx = _cursor;
      _cursor++;
      if (!_primed.containsKey(idx)) {
        _primed[idx] = soloud.play(_sample!, paused: true);
      }
    }

    // Release primed voices whose time has come. A row already past its time
    // (a stalled poll, a big rate) still fires now — one late tick beats a
    // dropped one, and the next rows realign to the clock immediately.
    if (_primed.isNotEmpty) {
      final due = <int>[];
      _primed.forEach((idx, _) {
        if (_rowClockSecond(_rows[idx]) <= clockNow) due.add(idx);
      });
      for (final idx in due) {
        final h = _primed.remove(idx)!;
        soloud.setPause(h, false);
        _firedCount++;
        // Error = how far the audio clock is from the row's target at release.
        _onFire?.call(_rows[idx], clockNow - _rowClockSecond(_rows[idx]));
      }
    }

    // Nothing left to schedule or release: idle the poller until the next start.
    if (_cursor >= _rows.length && _primed.isEmpty) {
      _poller?.cancel();
      _poller = null;
    }
  }

  /// Release everything owned by this instance. The shared engine is left up
  /// (other charts/instances may still use it); only per-instance voices and
  /// the decoded sample go.
  void dispose() {
    _reset();
    final soloud = SoLoud.instance;
    final clock = _clockVoice;
    if (clock != null && soloud.isInitialized) {
      soloud.stop(clock);
    }
    _clockVoice = null;
    final clockSrc = _clockSource;
    if (clockSrc != null && soloud.isInitialized) {
      soloud.disposeSource(clockSrc);
    }
    _clockSource = null;
    final sample = _sample;
    if (sample != null && soloud.isInitialized) {
      soloud.disposeSource(sample);
    }
    _sample = null;
  }
}
