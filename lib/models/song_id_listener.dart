/// Name: SongIdListener
/// Parent: ListenSheet
/// Description: Listens through the mic until Song ID places the song, or
/// gives up after [SongIdListener.maxSeconds]. The fingerprints are read the
/// first time and kept for the run (again after a content update). Audio
/// stays in memory and goes when listening stops.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/song_id.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:record/record.dart';

/// Where the cab is in a song Song ID placed, carried on from the match.
class SongIdFollow {
  SongIdFollow(this.song, double second, {this.sameMusic = const []})
      : _from = second,
        _since = Stopwatch()..start();

  final String song;

  /// Other songs with the same audio (see [SongIdMatch.sameMusic]).
  final List<String> sameMusic;
  final double _from;
  final Stopwatch _since;

  /// The cab's position in the song's audio now, in seconds.
  double now() => _from + _since.elapsedMicroseconds / 1e6;
}

class SongIdListener {
  static const maxSeconds = 12;
  // The mic's own rate on phones and Macs. Asking for less makes the
  // recorder resample a buffer at a time, which drops audio and left nothing
  // to match; Song ID's resampler does it instead.
  static const _rate = 48000;

  static Future<SongIdIndex>? _index;
  static int _indexRevision = -1;

  /// Every listed song's fingerprint, indexed off the UI thread.
  static Future<SongIdIndex> index() {
    if (_index == null || _indexRevision != ContentStore.revision.value) {
      _indexRevision = ContentStore.revision.value;
      _index = _build().catchError((Object e) {
        _index = null;
        throw e;
      });
    }
    return _index!;
  }

  static Future<SongIdIndex> _build() async {
    final files = <String, Uint8List>{};
    await Future.wait([
      for (final song in Songs.list)
        () async {
          // A song with no audio to fingerprint has no file.
          try {
            files[song.name] = await ContentStore.loadBytes(
                'assets/fingerprints/${song.name}.fp');
          } catch (_) {}
        }(),
    ]);
    return Isolate.run(() => SongIdIndex.build(files));
  }

  /// Stands in for the mic in tests: mono 16-bit PCM at [debugMicRate].
  @visibleForTesting
  static Stream<Uint8List> Function()? debugMic;
  @visibleForTesting
  static int debugMicRate = 16000;

  final _recorder = AudioRecorder();
  static const _session = MethodChannel('ddr_md/song_id_session');
  bool _ownsSession = false;
  final _pcm = BytesBuilder(copy: false);
  final _clip = <double>[];
  int _fed = 0;
  SongIdResampler? _resampler;
  int _peak = 0;
  ({int at, int bytes})? _firstChunk;
  StreamSubscription<Uint8List>? _sub;
  final _elapsed = Stopwatch();
  bool _stopped = false;

  /// Whole seconds heard so far, for the sheet's progress.
  int get seconds => _elapsed.elapsed.inSeconds;

  /// What the mic delivered, for checking a device: its rate as measured
  /// from the first chunk on, the rate it was read at, the loudest sample in
  /// dBFS and the seconds of audio heard. A measured rate well under the one
  /// read at means the recorder is dropping audio.
  ({int measured, int used, double peakDb, double heard}) get stats =>
      _lastStats ?? _stats();
  ({int measured, int used, double peakDb, double heard})? _lastStats;

  /// Keeps what was heard after listening stops, to check a device's audio
  /// (Development tools).
  bool keepRecording = false;
  Uint8List? _recording;

  /// What was heard as a mono 16-bit WAV, when [keepRecording] was on.
  Uint8List? get recordingWav {
    final pcm = _recording;
    final rate = _resampler?.rate;
    if (pcm == null || rate == null) return null;
    final header = ByteData(44)
      ..setUint32(0, 0x52494646) // RIFF
      ..setUint32(4, 36 + pcm.length, Endian.little)
      ..setUint32(8, 0x57415645) // WAVE
      ..setUint32(12, 0x666d7420) // fmt
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, rate, Endian.little)
      ..setUint32(28, rate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(36, 0x64617461) // data
      ..setUint32(40, pcm.length, Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
  }

  ({int measured, int used, double peakDb, double heard}) _stats() {
    final first = _firstChunk;
    final secs =
        first == null ? 0.0 : (_elapsed.elapsedMicroseconds - first.at) / 1e6;
    final samples = (_pcm.length - (first?.bytes ?? 0)) ~/ 2;
    return (
      measured: secs > 0.5 ? (samples / secs).round() : 0,
      used: _resampler?.rate ?? 0,
      peakDb: _peak == 0 ? -96 : 20 * log(_peak / 32768) / ln10,
      heard: _clip.length / kSongIdRate,
    );
  }

  /// The audio so far at [kSongIdRate], converting only what's new.
  Float32List _heard(int rate) {
    final bytes = _pcm.toBytes();
    final resampler = _resampler ??= SongIdResampler(rate);
    final fresh = Uint8List.sublistView(bytes, _fed);
    for (var i = 0; i + 1 < fresh.length; i += 2) {
      final v = (fresh[i] | fresh[i + 1] << 8).toSigned(16).abs();
      if (v > _peak) _peak = v;
    }
    _clip.addAll(resampler.add(fresh));
    _fed = bytes.length;
    return Float32List.fromList(_clip);
  }

  Future<InputDevice?> _builtInMic() async {
    try {
      return (await _recorder.listInputDevices())
          .where((d) => d.type == InputDeviceType.builtIn)
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasPermission() async =>
      debugMic != null || await _recorder.hasPermission();

  /// Listens until a match (with where the cab is when it's returned), or
  /// null after [maxSeconds] or [stop]. Throws when the mic can't be opened.
  /// Resyncing [only] (a song already followed) checks it alone, from 1 s in
  /// every 0.5 s, looking first near [near], where the cab should be.
  Future<SongIdFollow?> listen({String? only, double? near}) async {
    final indexFuture = index();
    if (debugMic == null && Platform.isIOS) {
      // The app sets up the session (see SongIdSession in AppDelegate).
      await _recorder.ios?.manageAudioSession(false);
      await _session.invokeMethod<void>('listen');
      _ownsSession = true;
    }
    final stream = debugMic?.call() ??
        await _recorder.startStream(RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _rate,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
          // The phone's own mic, pointed at the cab: a connected headset's
          // (AirPods in a pocket) hears the room muffled through voice
          // processing and matched nothing.
          device: await _builtInMic(),
          // Unprocessed for recognition: no noise suppression or gain riding.
          androidConfig: const AndroidRecordConfig(
              audioSource: AndroidAudioSource.voiceRecognition),
          iosConfig: const IosRecordConfig(categoryOptions: [
            IosAudioCategoryOption.defaultToSpeaker,
            IosAudioCategoryOption.allowBluetoothA2DP,
            IosAudioCategoryOption.mixWithOthers,
          ]),
        ));
    _elapsed.start();
    _sub = stream.listen((chunk) {
      _firstChunk ??= (at: _elapsed.elapsedMicroseconds, bytes: chunk.length);
      _pcm.add(chunk);
    });
    try {
      final index = await indexFuture;
      // Try often, on everything heard so far: a try takes a few
      // milliseconds, so trying often only answers sooner.
      final (from, step) = only == null ? (1.5, 0.75) : (1.0, 0.5);
      for (var at = from; at <= maxSeconds && !_stopped; at += step) {
        final wait = at * 1000 - _elapsed.elapsedMilliseconds;
        if (wait > 0) {
          await Future<void>.delayed(Duration(milliseconds: wait.round()));
        }
        if (_stopped) break;
        final heardAt = _elapsed.elapsedMicroseconds;
        final clip = _heard(debugMic != null ? debugMicRate : _rate);
        final marks = landmarks(clip, perSecond: kClipPeaksPerSecond);
        final match = only == null
            ? index.match(marks)
            : index.matchSong(marks, only, near: near);
        // A repeated part (a chorus) can't say where the cab is yet.
        if (match != null && !match.settled && at + step <= maxSeconds) {
          continue;
        }
        if (match != null) {
          final since = (_elapsed.elapsedMicroseconds - heardAt) / 1e6;
          // Of songs sharing the audio, the plain one ("MAX 300" over
          // "MAX 300(X-Special)") first.
          final names = [match.song, ...match.sameMusic]
            ..sort((a, b) => a.length - b.length);
          return SongIdFollow(
              names.first, match.second + clip.length / kSongIdRate + since,
              sameMusic: names.skip(1).toList());
        }
      }
      return null;
    } finally {
      await stop();
    }
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _elapsed.stop();
    final stats = _lastStats = _stats();
    if (keepRecording) _recording = _pcm.toBytes();
    debugPrint('Song ID mic: ${stats.measured} Hz measured, read at '
        '${stats.used}, peak ${stats.peakDb.toStringAsFixed(0)} dB, '
        '${stats.heard.toStringAsFixed(1)} s heard');
    await _sub?.cancel();
    await _recorder.stop();
    await _recorder.dispose();
    if (_ownsSession) {
      _ownsSession = false;
      await _session.invokeMethod<void>('done').catchError((_) {});
    }
    _pcm.clear();
  }
}
