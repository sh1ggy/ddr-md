import 'dart:math';
import 'dart:typed_data';

import 'package:ddr_md/models/song_id.dart';
import 'package:flutter_test/flutter_test.dart';

/// Forty seconds of random three-note plucks, a quarter second apart.
Float32List _song(Random rng) {
  final out = Float32List(40 * kSongIdRate);
  for (var start = 0; start < out.length; start += kSongIdRate ~/ 4) {
    final pitches = List.generate(3, (_) => 100 + rng.nextDouble() * 2400);
    for (var i = start; i < min(out.length, start + kSongIdRate ~/ 4); i++) {
      for (final hz in pitches) {
        out[i] += 0.6 *
            exp(-(i - start) / (0.06 * kSongIdRate)) *
            sin(2 * pi * hz * i / kSongIdRate);
      }
    }
  }
  return out;
}

void main() {
  test('a noisy clip names its song and where in it it starts', () {
    final rng = Random(7);
    final songs = [for (var i = 0; i < 6; i++) _song(rng)];
    final index = SongIdIndex.build({
      for (var i = 0; i < songs.length; i++)
        'song $i': encodeFingerprint(landmarks(songs[i], kSongDensity)),
    });

    final from = (17.3 * kSongIdRate).round();
    final clip = Float32List.fromList([
      for (var i = from; i < from + 8 * kSongIdRate; i++)
        songs[3][i] + (rng.nextDouble() - 0.5) * 0.9,
    ]);
    final match = index.match(landmarks(clip, kClipDensity))!;
    expect(match.song, 'song 3');
    expect(match.second, closeTo(17.3, 0.1));
    expect(
        index.match(landmarks(
            Float32List.fromList(
                List.generate(8 * kSongIdRate, (_) => rng.nextDouble() - 0.5)),
            kClipDensity)),
        isNull);
  });
}
