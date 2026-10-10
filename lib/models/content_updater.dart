/// Name: Content updater
/// Parent: main
/// Description: Fetches newer chart content in the background. Polls the small
/// latest.json at [kContentUrl]; when it is newer, reads the published
/// manifest there, downloads each file that differs from
/// the bundle into <app support>/content/objects/, checks its hash,
/// then swaps in overlay.json with one rename. [ContentStore] reads it on the
/// next launch, so content never changes under an open page. Published by
/// tool/content_manifest.dart.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/pattern_analysis.dart';

/// Where content is published (latest.json, manifest.json, objects/), set per
/// build:
///   flutter build ios --dart-define=CONTENT_URL=https://...
/// Empty, the default, turns updating off.
const kContentUrl = String.fromEnvironment('CONTENT_URL');

typedef ContentFetch = Future<List<int>> Function(Uri url);

class ContentUpdater {
  /// True when a new overlay was written, to apply on the next launch. Throws
  /// on a network error or a file whose hash doesn't match, leaving the
  /// current overlay as it was.
  static Future<bool> check(Directory support,
      {String base = kContentUrl, ContentFetch fetch = _get}) async {
    if (base.isEmpty) return false;
    final root = Uri.parse(base.endsWith('/') ? base : '$base/');
    Future<Map<String, dynamic>> read(String path) async =>
        json.decode(utf8.decode(await fetch(root.resolve(path))));
    final bundled = ContentStore.bundled;
    final latest = await read('latest.json');
    if (latest['format'] != kContentFormat ||
        latest['content'] as int <= bundled.content) {
      return false;
    }
    final dir = ContentStore.contentDir(support);
    final overlay = File('${dir.path}/overlay.json');
    // Already synced, against this same bundle (an app update changes what
    // needs downloading).
    if (overlay.existsSync()) {
      try {
        final current = json.decode(overlay.readAsStringSync());
        if (current['content'] == latest['content'] &&
            current['base'] == bundled.content) {
          return false;
        }
      } catch (_) {}
    }

    final remote = ContentManifest.fromJson(await read('manifest.json'));
    if (remote.format != kContentFormat || remote.content <= bundled.content) {
      return false;
    }
    final objects = Directory('${dir.path}/objects')
      ..createSync(recursive: true);
    // Patterns from another engine would disagree with this app's own solve.
    final patternsOk = remote.engine == kPatternEngineVersion;
    // Object name -> sha256, for every file that differs from the bundle.
    final wanted = {
      for (final MapEntry(key: path, value: sha) in remote.files.entries)
        if (bundled.files[path] != sha && (patternsOk || !isPatternPath(path)))
          objectName(path, sha): sha
    };
    final missing = [
      for (final name in wanted.keys)
        if (!File('${objects.path}/$name').existsSync()) name
    ];

    // A few at a time: a publish of every pattern file is ~1,300 requests.
    for (int i = 0; i < missing.length; i += 8) {
      await Future.wait([
        for (final name in missing.skip(i).take(8))
          () async {
            final bytes = await fetch(root.resolve('objects/$name'));
            if (sha256.convert(bytes).toString() != wanted[name]) {
              throw FormatException('content object $name failed its hash');
            }
            final part = File('${objects.path}/$name.part');
            await part.writeAsBytes(bytes, flush: true);
            await part.rename('${objects.path}/$name');
          }()
      ]);
    }

    final part = File('${overlay.path}.part');
    await part.writeAsString(
        json.encode({...remote.toJson(), 'base': bundled.content}),
        flush: true);
    await part.rename(overlay.path);

    final keep = {...wanted.keys, ...ContentStore.inUse};
    for (final f in objects.listSync().whereType<File>()) {
      if (!keep.contains(f.uri.pathSegments.last)) f.deleteSync();
    }
    return true;
  }

  static Future<List<int>> _get(Uri url) async {
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(url)).close();
      if (res.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${res.statusCode}', uri: url);
      }
      final bytes = BytesBuilder(copy: false);
      await res.forEach(bytes.add);
      return bytes.takeBytes();
    } finally {
      client.close();
    }
  }
}
