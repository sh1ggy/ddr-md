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
import 'package:ddr_md/components/settings/privacy_page.dart';
import 'package:ddr_md/constants.dart' show github;
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

/// SHA-256 of every key that signs a store build (Play Console → App
/// integrity → App signing), for Android app links.
const androidSigningFingerprints = <String>[];

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
/.well-known/apple-app-site-association
  Content-Type: application/json
''');
    // Song links (/songs/…) open the app: iOS universal links and Android
    // app links each verify the app against a file on this host.
    Directory('build/content/.well-known').createSync();
    File('build/content/.well-known/apple-app-site-association')
        .writeAsStringSync(jsonEncode({
      'applinks': {
        'details': [
          {
            'appIDs': ['S2JFTMZRP2.com.shiggy.ddrmd'],
            'components': [
              {'/': '/songs/*'}
            ],
          }
        ],
      },
    }));
    File('build/content/.well-known/assetlinks.json').writeAsStringSync(
        jsonEncode([
      {
        'relation': ['delegate_permission/common.handle_all_urls'],
        'target': {
          'namespace': 'android_app',
          'package_name': 'com.shiggy.ddr_md',
          'sha256_cert_fingerprints': androidSigningFingerprints,
        },
      }
    ]));
    // Without one, Pages answers a missing file with its app fallback page.
    File('build/content/404.html').writeAsStringSync('Not found\n');
    // The in-app privacy notice, as the public page both stores ask for
    // (served at /privacy).
    const esc = HtmlEscape();
    File('build/content/privacy.html').writeAsStringSync('''
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DDR MD privacy</title>
<style>body{font:16px/1.5 system-ui,sans-serif;max-width:40em;margin:2em auto;padding:0 1em}</style>
<h1>DDR MD privacy</h1>
<p><small>Last updated $privacyUpdated</small></p>
${[
      for (final (heading, paragraphs) in privacySections) ...[
        '<h2>${esc.convert(heading)}</h2>',
        for (final p in paragraphs)
          p.startsWith('- ')
              ? '<ul><li>${esc.convert(p.substring(2))}</li></ul>'
              : '<p>${esc.convert(p)}</p>',
      ],
    ].join('\n').replaceAll('</li></ul>\n<ul><li>', '</li>\n<li>')}
<h2>Contact</h2>
<p><a href="$github">${github.replaceFirst('https://', '')}</a></p>
''');

    // ignore: avoid_print
    print('content ${manifest.id}${changed ? ' (changed)' : ''}: '
        '${files.length} files');
  }, timeout: Timeout.none);
}
