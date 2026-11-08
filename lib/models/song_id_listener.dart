/// Name: SongIdListener
/// Parent: ListenSheet
/// Description: Listens through the mic until Song ID places the song, or
/// gives up after [SongIdListener.maxSeconds]. The fingerprints are read the
/// first time and kept for the run (again after a content update). Audio
/// stays in memory and goes when listening stops.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/song_id.dart';
import 'package:ddr_md/models/song_model.dart';
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
  static const _rate = 16000;

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
        ContentStore.loadBytes('assets/fingerprints/${song.name}.fp')
            .then((bytes) => files[song.name] = bytes, onError: (_) => null),
    ]);
    return Isolate.run(() => SongIdIndex.build(files));
  }

  final _recorder = AudioRecorder();
  final _pcm = BytesBuilder();
  StreamSubscription<Uint8List>? _sub;
  final _elapsed = Stopwatch();
  bool _stopped = false;

  /// Whole seconds heard so far, for the sheet's progress.
  int get seconds => _elapsed.elapsed.inSeconds;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Listens until a match (with where the cab is when it's returned), or
  /// null after [maxSeconds] or [stop]. Throws when the mic can't be opened.
  Future<SongIdFollow?> listen() async {
    final indexFuture = index();
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _rate,
      numChannels: 1,
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
    ));
    _elapsed.start();
    _sub = stream.listen(_pcm.add);
    try {
      final index = await indexFuture;
      // Try every 1.5 s from 3 s in, on everything heard so far.
      for (var at = 3.0; at <= maxSeconds && !_stopped; at += 1.5) {
        final wait = at * 1000 - _elapsed.elapsedMilliseconds;
        if (wait > 0) {
          await Future<void>.delayed(Duration(milliseconds: wait.round()));
        }
        if (_stopped) break;
        final heardAt = _elapsed.elapsedMicroseconds;
        final clip = toSongIdRate(_pcm.toBytes(), _rate);
        final match =
            index.match(landmarks(clip, perSecond: kClipPeaksPerSecond));
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
    await _sub?.cancel();
    await _recorder.stop();
    await _recorder.dispose();
    _pcm.clear();
  }
}
