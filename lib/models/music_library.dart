/// Name: MusicLibrary
/// Parent: MusicPage, ChartScroller
/// Description: The player's own music, in a music folder in the app's
/// documents. Files are matched to songs by name alone, in any subfolder, so
/// there is no index to go stale: what's in the folder is what's in the library.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _audioExtensions = {'.ogg', '.mp3', '.flac', '.wav'};

/// What a folder of files means against the song list.
class MusicScan {
  MusicScan({
    required this.matched,
    required this.close,
    required this.unused,
    required this.missing,
  });

  /// Song name to its file.
  final Map<String, String> matched;

  /// Song name to a file that nearly matches, which plays once confirmed.
  final Map<String, String> close;

  /// Audio files that match nothing, or repeat a song that already has a file.
  final List<String> unused;

  /// Songs with no file, confirmed or not.
  final List<String> missing;
}

/// The name a file claims, or null when it isn't a song file. AppleDouble `._`
/// files are skipped, but other dotfiles aren't: a song can start with a dot.
String? _claimedName(String path, Set<String> songs) {
  final base = p.basename(path);
  if (base.startsWith('._')) return null;
  final extension = p.extension(base);
  if (!_audioExtensions.contains(extension.toLowerCase())) return null;
  final stem = base.substring(0, base.length - extension.length);
  if (songs.contains(stem) || !stem.endsWith('-song')) return stem;
  return stem.substring(0, stem.length - '-song'.length);
}

String _loose(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

MusicScan matchMusic(Iterable<String> files, Iterable<String> songs) {
  final names = songs.toSet();
  final matched = <String, String>{};
  final leftover = <String>[];
  final claims = <String>[];
  for (final file in files.toList()..sort()) {
    final name = _claimedName(file, names);
    if (name == null) continue;
    if (names.contains(name) && !matched.containsKey(name)) {
      matched[name] = file;
    } else {
      leftover.add(file);
      claims.add(name);
    }
  }

  // A loose spelling counts only when it can mean one song.
  final byLoose = <String, List<String>>{};
  for (final song in names) {
    (byLoose[_loose(song)] ??= []).add(song);
  }
  final close = <String, String>{};
  final unused = <String>[];
  for (var i = 0; i < leftover.length; i++) {
    final candidates = byLoose[_loose(claims[i])];
    final song = candidates?.length == 1 ? candidates!.single : null;
    if (song != null &&
        !matched.containsKey(song) &&
        !close.containsKey(song)) {
      close[song] = leftover[i];
    } else {
      unused.add(leftover[i]);
    }
  }

  return MusicScan(
    matched: matched,
    close: close,
    unused: unused,
    missing: [
      for (final song in names)
        if (!matched.containsKey(song)) song
    ]..sort(),
  );
}

class MusicLibrary {
  static Future<Directory> folder() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/music').create(recursive: true);
  }

  static Future<List<String>> _files() async {
    final folder = await MusicLibrary.folder();
    return [
      await for (final entry
          in folder.list(recursive: true, followLinks: false))
        if (entry is File) entry.path
    ];
  }

  static Future<MusicScan> scan(Iterable<String> songs) async =>
      matchMusic(await _files(), songs);

  /// The song's file, or null when the player hasn't added one.
  static Future<String?> pathFor(String song) async =>
      matchMusic(await _files(), [song]).matched[song];

  /// Accepts a close match by giving the file its song's exact name.
  static Future<void> confirm(String song, String file) async {
    await File(file).rename(
        p.join(p.dirname(file), '${fileNameFor(song)}${p.extension(file)}'));
  }

  /// A song's file name, before the extension.
  static String fileNameFor(String song) => '$song-song';
}
