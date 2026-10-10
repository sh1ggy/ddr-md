/// Name: Content manifest
/// Parent: tool (dev only)
/// Description: Hashes the chart content the app can update over the air
/// (songlist, steps, patterns, jackets, parity moments) into
/// assets/content_manifest.json, which the app bundles, and lays out
/// build/content/ (latest.json, manifest.json, objects/) to upload to
/// CONTENT_URL: objects first and latest.json last, so an app never sees a
/// content number whose files aren't up yet.
/// The content number goes up whenever a file changed, so installed apps fetch
/// only what differs from their bundle. Run after generate_songlist.sh and
/// generate_patterns.dart:
///
///   flutter test tool/content_manifest.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

/// Content paths relative to assets/: single files, then directories with the
/// extension their files carry.
const _files = ['songlist.json', 'parity_patterns.json', 'pattern_levels.json'];
const _dirs = {
  'steps': '.json',
  'patterns': '.json',
  'jackets': '.png',
  'jackets-160': '.png',
};

void main() {
  test('write assets/content_manifest.json and build/content', () {
    final paths = [
      for (final f in _files)
        if (File('assets/$f').existsSync()) f,
      for (final MapEntry(key: dir, value: ext) in _dirs.entries)
        if (Directory('assets/$dir').existsSync())
          for (final f in Directory('assets/$dir').listSync())
            if (f is File && f.path.endsWith(ext))
              '$dir/${f.uri.pathSegments.last}',
    ]..sort();
    final files = {
      for (final p in paths)
        p: sha256.convert(File('assets/$p').readAsBytesSync()).toString()
    };

    final bundled = File('assets/content_manifest.json');
    final previous = bundled.existsSync()
        ? ContentManifest.fromJson(jsonDecode(bundled.readAsStringSync()))
        : ContentManifest.empty;
    final changed = previous.engine != kPatternEngineVersion ||
        previous.files.length != files.length ||
        files.entries.any((e) => previous.files[e.key] != e.value);
    final manifest = ContentManifest(
      format: kContentFormat,
      content: changed ? previous.content + 1 : previous.content,
      engine: kPatternEngineVersion,
      files: files,
    );
    final text = const JsonEncoder.withIndent(' ').convert(manifest);
    bundled.writeAsStringSync(text);

    final out = Directory('build/content/objects')..createSync(recursive: true);
    final names = {
      for (final MapEntry(key: path, value: sha) in files.entries)
        objectName(path, sha): path
    };
    for (final MapEntry(key: name, value: path) in names.entries) {
      final object = File('${out.path}/$name');
      if (!object.existsSync()) File('assets/$path').copySync(object.path);
    }
    for (final f in out.listSync().whereType<File>()) {
      if (!names.containsKey(f.uri.pathSegments.last)) f.deleteSync();
    }
    File('build/content/manifest.json').writeAsStringSync(text);
    File('build/content/latest.json').writeAsStringSync(
        jsonEncode({'format': manifest.format, 'content': manifest.content}));
    // Cloudflare Pages headers: objects never change once published, the two
    // indexes must always be checked.
    File('build/content/_headers').writeAsStringSync('''
/objects/*
  Cache-Control: public, max-age=31536000, immutable
/latest.json
  Cache-Control: no-cache
/manifest.json
  Cache-Control: no-cache
''');
    // Without one, Pages answers a missing file with its app fallback page.
    File('build/content/404.html').writeAsStringSync('Not found\n');

    // ignore: avoid_print
    print('content ${manifest.content}${changed ? ' (changed)' : ''}: '
        '${files.length} files');
  }, timeout: Timeout.none);
}
