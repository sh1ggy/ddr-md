/// Name: Content manifest
/// Parent: tool (dev only)
/// Description: Hashes the chart content the app can update over the air
/// (songlist, steps, patterns, jackets, parity moments) into
/// assets/content_manifest.json, which the app bundles, and lays out
/// build/content/ (latest.json, manifest.json, objects/) to upload to
/// CONTENT_URL: objects first and latest.json last, so an app never sees an
/// id whose files aren't up yet.
/// The id is a hash of what's published, so it changes exactly when a file (or
/// the pattern engine) does; installed apps follow it and fetch only what
/// differs from their bundle. Run after generate_songlist.sh and
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
/// extension their files carry. Everything any app still in use reads: during
/// a breaking change, both the old path and its replacement (see `appReads`).
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
    final Map<String, dynamic> previous =
        bundled.existsSync() ? jsonDecode(bundled.readAsStringSync()) : {};
    final id = sha256
        .convert(utf8.encode(jsonEncode([kPatternEngineVersion, files])))
        .toString()
        .substring(0, 12);
    final changed = previous['id'] != id;
    final manifest = ContentManifest(
      id: id,
      engine: kPatternEngineVersion,
      files: files,
    );
    // The commits this content was first built from (CI sets both), kept
    // while it doesn't change so an unchanged run matches the live manifest
    // byte for byte.
    final env = Platform.environment;
    final source = !changed
        ? previous['source']
        : env.containsKey('CONTENT_COMMIT')
            ? {'content': env['CONTENT_COMMIT'], 'app': env['APP_COMMIT']}
            : null;
    final text = const JsonEncoder.withIndent(' ')
        .convert({...manifest.toJson(), if (source != null) 'source': source});
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
    File('build/content/latest.json')
        .writeAsStringSync(jsonEncode({'id': manifest.id}));
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
    print('content ${manifest.id}${changed ? ' (changed)' : ''}: '
        '${files.length} files');
  }, timeout: Timeout.none);
}
