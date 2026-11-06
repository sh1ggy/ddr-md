/// Name: TimingCheckAudio
/// Parent: TimingCheckPage
/// Description: A single PCM drum track keeps the round on a fixed beat grid.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'timing_check_protocol.dart';

class TimingCheckAudio {
  final _engine = SoLoud.instance;
  AudioSource? _track;
  AudioSource? _practiceTrack;
  SoundHandle? _voice;

  Future<void> load() async {
    if (!_engine.isInitialized) {
      await _engine.init(lowLatency: true, bufferSize: 1024);
    }
    _track ??= await _engine.loadMem('timing_check_drums.wav', _drumTrack());
    _practiceTrack ??= await _engine.loadMem(
        'timing_check_practice.wav', _drumTrack(practice: true));
  }

  void play({bool practice = false}) {
    final track = practice ? _practiceTrack : _track;
    if (track != null) _voice = _engine.play(track, looping: practice);
  }

  void stop() {
    final voice = _voice;
    _voice = null;
    if (voice != null && _engine.getIsValidVoiceHandle(voice)) {
      _engine.stop(voice);
    }
  }

  Future<void> dispose() async {
    stop();
    final track = _track;
    _track = null;
    if (track != null) await _engine.disposeSource(track);
    final practiceTrack = _practiceTrack;
    _practiceTrack = null;
    if (practiceTrack != null) await _engine.disposeSource(practiceTrack);
  }

  static Uint8List _drumTrack({bool practice = false}) {
    const rate = 24000;
    final duration = practice ? practiceLoopMs : roundEndMs + beatMs;
    final byteLength = duration * rate ~/ 1000 * 2;
    final bytes = Uint8List(44 + byteLength);
    final header = ByteData.sublistView(bytes);
    bytes.setAll(0, 'RIFF'.codeUnits);
    header.setUint32(4, 36 + byteLength, Endian.little);
    bytes.setAll(8, 'WAVEfmt '.codeUnits);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, rate, Endian.little);
    header.setUint32(28, rate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    bytes.setAll(36, 'data'.codeUnits);
    header.setUint32(40, byteLength, Endian.little);

    final first = practice ? 0 : 1;
    final end = practice ? scoredBeats : countInBeats + scoredBeats + 1;
    for (var beat = first; beat < end; beat++) {
      final start = beat * beatMs * rate ~/ 1000;
      final accent = !practice && beat <= countInBeats ? 0.55 : 1.0;
      for (var sample = 0; sample < rate ~/ 16; sample++) {
        final seconds = sample / rate;
        final phase =
            2 * math.pi * (85 * seconds + 1 - math.exp(-100 * seconds));
        final kick = math.sin(phase) * math.exp(-75 * seconds);
        final click =
            math.sin(2 * math.pi * 1300 * seconds) * math.exp(-420 * seconds);
        final value = (20000 * accent * (0.8 * kick + 0.2 * click)).round();
        header.setInt16(44 + 2 * (start + sample), value, Endian.little);
      }
    }
    return bytes;
  }
}
