/// Name: SongId
/// Parent: ListenSheet, tool/generate_fingerprints.dart
/// Description: Names the song a cab is playing from a few seconds of mic
/// audio. Each song's fingerprint is a set of landmarks: pairs of spectrogram
/// peaks, hashed by their two pitches and the time between them. A clip's
/// landmarks that share a hash with a song's, all at the same time shift, say
/// both which song it is and where in it the clip starts. The generator and
/// the app run this same code, so the two always agree.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Bump when a change here alters the landmarks, and regenerate every file:
/// the loader skips files of any other schema.
const kFingerprintSchema = 2;

/// Sample rate everything is fingerprinted at.
const kSongIdRate = 8000;

const _window = 1024;
const _hop = 256; // 32 ms frames
const _lowBin = 20; // ~156 Hz: below it a phone mic hears little
const _highBin = 400; // ~3.1 kHz
const _bins = _highBin - _lowBin;
const _timeRadius = 7;
const _binRadius = 10;
const _block = 31; // ~1 s of frames
const _fan = 3;
const _maxGap = 63;
const _maxPitchStep = 127;
const _magic = [0x44, 0x44, 0x46, 0x50]; // DDFP

/// Seconds a frame lasts.
const kSongIdFrameSeconds = _hop / kSongIdRate;

/// Peaks kept per second. Denser songs answer sooner and from further away
/// (median ~3 s through a room, ~4.5 s far from the speaker, against ~7 and
/// ~8 s at 4 a second) for ~11 KB a song; a clip needs fewer, as its extra
/// peaks are mostly noise.
const kSongPeaksPerSecond = 12;
const kClipPeaksPerSecond = 8;

/// A pair of peaks: [hash] names the pitches and gap, [frame] the first's.
typedef Landmark = ({int hash, int frame});

final _hann = Float64List.fromList([
  for (var i = 0; i < _window; i++) 0.5 - 0.5 * cos(2 * pi * i / (_window - 1))
]);

/// The landmarks of mono [pcm] at [kSongIdRate], keeping [perSecond] of the
/// loudest peaks in each second.
List<Landmark> landmarks(Float32List pcm, {required int perSecond}) {
  final frames = pcm.length < _window ? 0 : (pcm.length - _window) ~/ _hop + 1;
  if (frames == 0) return const [];
  final fft = FFT(_window);
  final spec = Float32List(frames * _bins);
  final buffer = Float64List(_window);
  var total = 0.0;
  for (var f = 0; f < frames; f++) {
    final start = f * _hop;
    for (var i = 0; i < _window; i++) {
      buffer[i] = pcm[start + i] * _hann[i];
    }
    final bins = fft.realFft(buffer);
    for (var b = 0; b < _bins; b++) {
      final z = bins[_lowBin + b];
      final v = log(1 + 100 * sqrt(z.x * z.x + z.y * z.y));
      spec[f * _bins + b] = v;
      total += v;
    }
  }
  final mean = total / spec.length;

  // A peak is the loudest point of its neighbourhood. Max over a rectangle
  // is max over pitch, then over time.
  final byBin = Float32List(spec.length);
  for (var f = 0; f < frames; f++) {
    for (var b = 0; b < _bins; b++) {
      var m = -1.0;
      for (var k = max(0, b - _binRadius);
          k <= min(_bins - 1, b + _binRadius);
          k++) {
        m = max(m, spec[f * _bins + k]);
      }
      byBin[f * _bins + b] = m;
    }
  }
  final peaks = <({int frame, int bin})>[];
  for (var blockStart = 0; blockStart < frames; blockStart += _block) {
    final found = <({int frame, int bin, double v})>[];
    for (var f = blockStart; f < min(frames, blockStart + _block); f++) {
      for (var b = 0; b < _bins; b++) {
        final v = spec[f * _bins + b];
        if (v <= mean) continue;
        var isPeak = true;
        for (var k = max(0, f - _timeRadius);
            isPeak && k <= min(frames - 1, f + _timeRadius);
            k++) {
          if (byBin[k * _bins + b] > v) isPeak = false;
        }
        if (isPeak) found.add((frame: f, bin: b, v: v));
      }
    }
    found.sort((a, b) => b.v.compareTo(a.v));
    peaks
        .addAll(found.take(perSecond).map((p) => (frame: p.frame, bin: p.bin)));
  }
  peaks.sort((a, b) => a.frame != b.frame ? a.frame - b.frame : a.bin - b.bin);

  final out = <Landmark>[];
  for (var i = 0; i < peaks.length; i++) {
    final a = peaks[i];
    var paired = 0;
    for (var j = i + 1; j < peaks.length && paired < _fan; j++) {
      final b = peaks[j];
      final gap = b.frame - a.frame;
      if (gap > _maxGap) break;
      final step = b.bin - a.bin;
      if (gap < 1 || step.abs() > _maxPitchStep) continue;
      out.add((
        hash: a.bin << 15 | (step + 128) << 6 | gap,
        frame: a.frame,
      ));
      paired++;
    }
  }
  return out;
}

/// [pcm] (16-bit little-endian, [channels] interleaved, at [rate]) as mono
/// at [kSongIdRate]. Each output sample averages the input it spans, which
/// is low-pass enough for what the landmarks look at.
Float32List toSongIdRate(Uint8List pcm, int rate, {int channels = 1}) {
  final samples = ByteData.sublistView(pcm);
  final frames = pcm.length ~/ (2 * channels);
  final step = rate / kSongIdRate;
  final out = Float32List((frames / step).floor());
  for (var i = 0; i < out.length; i++) {
    final from = (i * step).floor();
    final to = max(from + 1, ((i + 1) * step).floor());
    var sum = 0.0;
    for (var f = from; f < to && f < frames; f++) {
      for (var c = 0; c < channels; c++) {
        sum += samples.getInt16((f * channels + c) * 2, Endian.little);
      }
    }
    out[i] = sum / ((to - from) * channels * 32768);
  }
  return out;
}

void _varint(BytesBuilder out, int v) {
  while (v >= 0x80) {
    out.addByte(v & 0x7f | 0x80);
    v >>= 7;
  }
  out.addByte(v);
}

/// A song's file: landmarks by hash, as gzipped varint deltas.
Uint8List encodeFingerprint(List<Landmark> marks) {
  final sorted = [...marks]
    ..sort((a, b) => a.hash != b.hash ? a.hash - b.hash : a.frame - b.frame);
  final out = BytesBuilder()
    ..add(_magic)
    ..addByte(kFingerprintSchema);
  _varint(out, sorted.length);
  var last = 0;
  for (final m in sorted) {
    _varint(out, m.hash - last);
    _varint(out, m.frame);
    last = m.hash;
  }
  return Uint8List.fromList(gzip.encode(out.takeBytes()));
}

/// The landmarks in a song's file, or null when it isn't one of this schema.
List<Landmark>? decodeFingerprint(Uint8List file) {
  final packed = _decodePacked(file, 0);
  return packed == null
      ? null
      : [for (final e in packed) (hash: e >> 32, frame: e & 0xffff)];
}

/// A song's file straight into the index's packing (see [SongIdIndex]) as
/// song [id], skipping the per-landmark records the index would only repack.
Int64List? _decodePacked(Uint8List file, int id) {
  final Uint8List bytes;
  try {
    bytes = Uint8List.fromList(gzip.decode(file));
  } on FormatException {
    return null;
  }
  if (bytes.length < 5 ||
      bytes[0] != _magic[0] ||
      bytes[1] != _magic[1] ||
      bytes[2] != _magic[2] ||
      bytes[3] != _magic[3] ||
      bytes[4] != kFingerprintSchema) {
    return null;
  }
  var at = 5;
  int next() {
    var v = 0, shift = 0;
    while (true) {
      final b = bytes[at++];
      v |= (b & 0x7f) << shift;
      if (b < 0x80) return v;
      shift += 7;
    }
  }

  final count = next();
  final out = Int64List(count);
  var hash = 0, kept = 0;
  for (var i = 0; i < count; i++) {
    hash += next();
    final frame = next();
    if (frame <= 0xffff) out[kept++] = hash << 32 | id << 16 | frame;
  }
  return kept == count ? out : Int64List.sublistView(out, 0, kept);
}

/// What a clip turned out to be.
class SongIdMatch {
  const SongIdMatch(this.song, this.second, this.votes,
      {this.sameMusic = const [], this.settled = true});

  final String song;

  /// Other songs with this same audio, any of which it could be.
  final List<String> sameMusic;

  /// False while a repeated part of the song leaves where it is unclear.
  final bool settled;

  /// Where in the song the clip starts, in seconds of its audio file.
  final double second;

  /// Landmarks that agreed; more is surer.
  final int votes;
}

/// Every song's landmarks in one list sorted by hash, packed as
/// hash << 32 | song << 16 | frame.
class SongIdIndex {
  SongIdIndex._(this.songs, this._entries);

  final List<String> songs;
  final Int64List _entries;

  int get length => _entries.length;

  /// From song name to its file; files that don't decode are left out.
  factory SongIdIndex.build(Map<String, Uint8List> files) {
    final songs = <String>[];
    final packed = <Int64List>[];
    for (final MapEntry(key: song, value: file) in files.entries) {
      if (songs.length > 0xffff) break;
      final marks = _decodePacked(file, songs.length);
      if (marks == null) continue;
      songs.add(song);
      packed.add(marks);
    }
    // Sorted by bucketing on the hash's top bits first, then sorting each
    // small bucket: one sort of millions of entries is most of the build.
    const shift = 32 + 10;
    final counts = Int32List((1 << 24 >> 10) + 1);
    for (final p in packed) {
      for (final e in p) {
        counts[(e >> shift) + 1]++;
      }
    }
    for (var i = 1; i < counts.length; i++) {
      counts[i] += counts[i - 1];
    }
    final entries = Int64List(counts.last);
    final next = Int32List.fromList(counts);
    for (final p in packed) {
      for (final e in p) {
        entries[next[e >> shift]++] = e;
      }
    }
    for (var b = 0; b + 1 < counts.length; b++) {
      if (counts[b + 1] - counts[b] > 1) {
        Int64List.sublistView(entries, counts[b], counts[b + 1]).sort();
      }
    }
    return SongIdIndex._(songs, entries);
  }

  int _firstAtLeast(int key) {
    var lo = 0, hi = _entries.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_entries[mid] < key) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The song [clip]'s landmarks agree on, or null when none stands out.
  SongIdMatch? match(List<Landmark> clip) {
    // Votes per song and time shift: shift + 2^17 keeps it positive.
    final votes = <int, int>{};
    for (final m in clip) {
      final first = _firstAtLeast(m.hash << 32);
      // A hash this common (a kick drum at a common tempo) says nothing.
      final end = _firstAtLeast((m.hash + 1) << 32);
      if (end - first > _maxPostings) continue;
      for (var i = first; i < end; i++) {
        final e = _entries[i];
        final shift = (e & 0xffff) - m.frame + (1 << 17);
        final vote = ((e >> 16) & 0xffff) << 18 | shift;
        votes[vote] = (votes[vote] ?? 0) + 1;
      }
    }
    // Each song's best shift, its votes counted with its neighbours', as
    // frames can round either way.
    final perSong = <int, ({int votes, int shift})>{};
    for (final key in votes.keys) {
      final n = votes[key]! + (votes[key - 1] ?? 0) + (votes[key + 1] ?? 0);
      final song = key >> 18;
      if (n > (perSong[song]?.votes ?? 0)) {
        perSong[song] = (votes: n, shift: (key & ((1 << 18) - 1)) - (1 << 17));
      }
    }
    if (perSong.isEmpty) return null;
    final ranked = perSong.entries.toList()
      ..sort((a, b) => b.value.votes - a.value.votes);
    final top = ranked.first.value;
    // Songs that agree at the same moment are the same cut under two names
    // (a song and its special chart, say); anything else is a rival.
    bool sameCut(({int votes, int shift}) v) =>
        (v.shift - top.shift).abs() <= 3 && v.votes * 10 >= top.votes * 6;
    final rival = ranked
        .skip(1)
        .where((e) => !sameCut(e.value))
        .fold(0, (n, e) => max(n, e.value.votes));
    if (top.votes < kMinVotes || top.votes < 2 * rival) return null;
    // A part the song repeats (a chorus) matches at each time it plays; only
    // more listening tells which one the cab is on.
    final id = ranked.first.key;
    var repeat = 0;
    for (final MapEntry(:key, :value) in votes.entries) {
      if (key >> 18 != id) continue;
      final shift = (key & ((1 << 18) - 1)) - (1 << 17);
      if ((shift - top.shift).abs() > 3) {
        repeat =
            max(repeat, value + (votes[key - 1] ?? 0) + (votes[key + 1] ?? 0));
      }
    }
    return SongIdMatch(
      songs[id],
      top.shift * kSongIdFrameSeconds,
      top.votes,
      settled: repeat * 10 < top.votes * 6,
      sameMusic: [
        for (final e in ranked.skip(1))
          if (sameCut(e.value)) songs[e.key]
      ],
    );
  }
}

/// Fewest agreeing landmarks that count as a match.
const kMinVotes = 6;

extension SongIdResync on SongIdIndex {
  /// [clip] against [song] alone, for a resync: with no other song to tell
  /// apart, fewer landmarks will do. [near] is where in its audio the clip
  /// should start; a shift within [window] seconds of it wins over a repeat
  /// elsewhere in the song.
  SongIdMatch? matchSong(List<Landmark> clip, String song,
      {double? near, double window = 4}) {
    final id = songs.indexOf(song);
    if (id < 0) return null;
    final votes = <int, int>{};
    for (final m in clip) {
      final first = _firstAtLeast(m.hash << 32);
      final end = _firstAtLeast((m.hash + 1) << 32);
      for (var i = first; i < end; i++) {
        final e = _entries[i];
        if ((e >> 16) & 0xffff != id) continue;
        final shift = (e & 0xffff) - m.frame;
        votes[shift] = (votes[shift] ?? 0) + 1;
      }
    }
    int sum(int s) => votes[s]! + (votes[s - 1] ?? 0) + (votes[s + 1] ?? 0);
    bool inWindow(int s) =>
        near == null || (s * kSongIdFrameSeconds - near).abs() <= window;
    int? best;
    for (final s in votes.keys) {
      if (inWindow(s) && (best == null || sum(s) > sum(best))) best = s;
    }
    if (best == null || sum(best) < kMinResyncVotes) return null;
    var repeat = 0;
    for (final s in votes.keys) {
      if ((s - best).abs() > 3 && inWindow(s)) repeat = max(repeat, sum(s));
    }
    return SongIdMatch(song, best * kSongIdFrameSeconds, sum(best),
        settled: repeat * 10 < sum(best) * 6);
  }
}

/// Fewest agreeing landmarks for a resync, which only has one song to fit.
const kMinResyncVotes = 4;

/// Songs' landmarks sharing a hash past which it's ignored.
const _maxPostings = 150;
