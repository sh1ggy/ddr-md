/// Name: ChartMusic
/// Parent: chart_scroller.dart
/// Description: Plays the player's own copy of a song in time with the chart
/// preview. The app ships no music: with no file for the song this stays silent.
library;

import 'package:flutter_soloud/flutter_soloud.dart';

/// A decoded song, shared because switching difficulty opens the new chart
/// before the old one has closed.
class _SharedSource {
  _SharedSource(this.path, this.source);
  final String path;
  final Future<AudioSource> source;
  int users = 0;
}

class ChartMusic {
  static final _shared = <String, _SharedSource>{};

  /// Closer than this, a resync leaves the voice alone: a rate change or a
  /// re-anchor mustn't make the music hiccup.
  static const _seekTolerance = Duration(milliseconds: 20);

  _SharedSource? _held;
  AudioSource? _source;
  Duration _length = Duration.zero;
  SoundHandle? _voice;
  bool _playing = false;

  Future<void> load(String path) async {
    final shared =
        _shared[path] ??= _SharedSource(path, SoLoud.instance.loadFile(path));
    shared.users++;
    _held = shared;
    final AudioSource source;
    try {
      source = await shared.source;
    } catch (_) {
      _shared.remove(path);
      rethrow;
    }
    if (_held != shared) return; // disposed while decoding
    _source = source;
    _length = SoLoud.instance.getLength(source);
  }

  bool get isReady => _source != null;

  /// Plays from [second] of the file at [rate], from wherever the voice is.
  void play(double second, double rate) {
    final source = _source;
    if (source == null) return;
    final engine = SoLoud.instance;
    final target = Duration(microseconds: (second * 1e6).round());
    final at = target.isNegative ? Duration.zero : target;
    if (at >= _length) {
      pause();
      return;
    }
    var voice = _voice;
    if (voice == null || !engine.getIsValidVoiceHandle(voice)) {
      voice = engine.play(source, paused: true);
      engine.setProtectVoice(voice, true);
      _voice = voice;
    }
    if ((engine.getPosition(voice) - at).abs() > _seekTolerance) {
      engine.seek(voice, at);
    }
    engine.setRelativePlaySpeed(voice, rate);
    engine.setPause(voice, false);
    _playing = true;
  }

  void pause() {
    _playing = false;
    final voice = _voice;
    if (voice != null && SoLoud.instance.getIsValidVoiceHandle(voice)) {
      SoLoud.instance.setPause(voice, true);
    }
  }

  /// Where the music is in the file, in seconds; null unless it's sounding.
  double? get second {
    final voice = _voice;
    if (!_playing || voice == null) return null;
    final engine = SoLoud.instance;
    if (!engine.getIsValidVoiceHandle(voice)) return null;
    return engine.getPosition(voice).inMicroseconds / 1e6;
  }

  void dispose() {
    final voice = _voice;
    final engine = SoLoud.instance;
    if (voice != null && engine.isInitialized) engine.stop(voice);
    _voice = null;
    _playing = false;
    _source = null;
    final shared = _held;
    _held = null;
    if (shared != null && --shared.users == 0) {
      _shared.remove(shared.path);
      shared.source.then((source) {
        if (engine.isInitialized) engine.disposeSource(source);
      }, onError: (_) {});
    }
  }
}
