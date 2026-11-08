/// Name: Fingerprint generator
/// Parent: tool (dev only)
/// Description: Writes assets/fingerprints/<name>.fp, each listed song's Song
/// ID landmarks, from its audio in DDR-BPM-prep/data (decoded with ffmpeg).
/// Then listens to noisy clips of a sample of songs and prints how many it
/// placed, so a change to song_id.dart shows what it costs. Rerun after
/// adding songs or changing song_id.dart (bump kFingerprintSchema if the
/// landmarks change).
///
///   flutter test tool/generate_fingerprints.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ddr_md/models/song_id.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Float32List> _decode(String path) async {
  final run = await Process.run(
      'ffmpeg',
      [
        '-v',
        'quiet',
        '-i',
        path,
        '-ac',
        '1',
        '-ar',
        '$kSongIdRate',
        '-f',
        's16le',
        '-'
      ],
      stdoutEncoding: null);
  return toSongIdRate(run.stdout as Uint8List, kSongIdRate);
}

void main() {
  test('write assets/fingerprints', () async {
    final listed = jsonDecode(File('assets/songlist.json').readAsStringSync());
    final songs = {
      for (final s in (listed is List ? listed : listed['songs']) as List)
        s['name'] as String
    };
    final audio = <String, String>{};
    final files = Directory('DDR-BPM-prep/data')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.ogg') && f.lengthSync() > 0)
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final stem = f.uri.pathSegments.last.replaceAll(RegExp(r'\.ogg$'), '');
      if (songs.contains(stem)) audio.putIfAbsent(stem, () => f.path);
    }

    final out = Directory('assets/fingerprints')..createSync();
    for (final f in out.listSync().whereType<File>()) {
      f.deleteSync();
    }
    final written = <String, Uint8List>{};
    final names = audio.keys.toList()..sort();
    for (var i = 0; i < names.length; i += 8) {
      final batch = names.skip(i).take(8).toList();
      final pcms =
          await Future.wait([for (final n in batch) _decode(audio[n]!)]);
      for (var j = 0; j < batch.length; j++) {
        final file = encodeFingerprint(
            landmarks(pcms[j], perSecond: kSongPeaksPerSecond));
        File('${out.path}/${batch[j]}.fp').writeAsBytesSync(file);
        written[batch[j]] = file;
      }
    }
    final bytes = written.values.fold(0, (n, f) => n + f.length);
    // ignore: avoid_print
    print('fingerprints: ${written.length} of ${songs.length} songs, '
        '${(bytes / 1e6).toStringAsFixed(1)} MB');

    // Twelve seconds (as long as the app listens) from somewhere in 40
    // songs, under noise as loud as the music.
    final index = SongIdIndex.build(written);
    final rng = Random(1);
    var placed = 0, wrong = 0;
    final sample = (names.toList()..shuffle(rng)).take(40);
    for (final name in sample) {
      final pcm = await _decode(audio[name]!);
      if (pcm.length < 30 * kSongIdRate) continue;
      final from = rng.nextInt(pcm.length - 20 * kSongIdRate) + 5 * kSongIdRate;
      var power = 0.0;
      for (var i = from; i < from + 12 * kSongIdRate; i++) {
        power += pcm[i] * pcm[i];
      }
      final rms = sqrt(power / (12 * kSongIdRate));
      final clip = Float32List.fromList([
        for (var i = from; i < from + 12 * kSongIdRate; i++)
          pcm[i] + rms * sqrt(3) * (2 * rng.nextDouble() - 1),
      ]);
      final match =
          index.match(landmarks(clip, perSecond: kClipPeaksPerSecond));
      if (match == null) continue;
      if ((match.song == name || match.sameMusic.contains(name)) &&
          (match.second - from / kSongIdRate).abs() < 0.2) {
        placed++;
      } else {
        wrong++;
      }
    }
    // ignore: avoid_print
    print('noisy 12 s clips: $placed of ${sample.length} placed, $wrong wrong');
  }, timeout: Timeout.none);
}
