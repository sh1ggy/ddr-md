/// Name: Content updater
/// Parent: main
/// Description: Fetches newer chart content in the background. Polls the small
/// latest.json at [kContentUrl]; when it names other content, reads the published
/// manifest there, downloads each file that differs from
/// the bundle into <app support>/content/objects/, checks its hash,
/// then swaps in overlay.json with one rename. [ContentUpdater.update] applies
/// it straight away; pages already open keep what they loaded. Published by
/// tool/content_manifest.dart.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ddr_md/models/content_store.dart';
import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:ddr_md/models/pattern_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:flutter/foundation.dart';

/// Where content is published (latest.json, manifest.json, objects/). Release
/// builds (`flutter run --release`, `flutter build`) use the live host unless
/// given another; an empty one turns updating off:
///   flutter build ios --dart-define=CONTENT_URL=https://...
/// Debug and profile builds default to off, so an update never replaces
/// content generated locally.
const kContentUrl = String.fromEnvironment('CONTENT_URL',
    defaultValue: kReleaseMode ? 'https://ddr-md-content.pages.dev' : '');

typedef ContentFetch = Future<List<int>> Function(Uri url);

class ContentUpdater {
  static Future<bool>? _running;

  /// True when the overlay changed (written, or dropped because live is the
  /// bundle again), for [update] to apply. Throws
  /// on a network error or a file whose hash doesn't match, leaving the
  /// current overlay as it was. A check already running (launch, or the
  /// settings page) is joined rather than raced, since both write objects/.
  static Future<bool> check(Directory support,
          {String base = kContentUrl, ContentFetch fetch = _get}) =>
      _running ??=
          _check(support, base, fetch).whenComplete(() => _running = null);

  /// Checks, then applies what's on disk if this run isn't reading it yet:
  /// re-reads the content, reloads the song list and bumps
  /// [ContentStore.revision]. True when other content was applied. Throws like
  /// [check].
  static Future<bool> update(Directory support,
      {String base = kContentUrl, ContentFetch fetch = _get}) async {
    await check(support, base: base, fetch: fetch);
    final onDisk =
        ContentStore.downloaded(support)?.id ?? ContentStore.bundled.id;
    if (onDisk == ContentStore.current) return false;
    await ContentStore.init(support);
    await Songs.load();
    PatternsLoader.reset();
    ContentStore.revision.value++;
    return true;
  }

  static Future<bool> _check(
      Directory support, String base, ContentFetch fetch) async {
    if (base.isEmpty) return false;
    final root = Uri.parse(base.endsWith('/') ? base : '$base/');
    Future<Map<String, dynamic>> read(String path) async =>
        json.decode(utf8.decode(await fetch(root.resolve(path))));
    final bundled = ContentStore.bundled;
    final id = (await read('latest.json'))['id'];
    final dir = ContentStore.contentDir(support);
    final overlay = File('${dir.path}/overlay.json');
    // Live is the bundle again (a rollback, or an app update caught up): the
    // download no longer applies.
    if (id == bundled.id) {
      if (!overlay.existsSync()) return false;
      overlay.deleteSync();
      return true;
    }
    // Already synced, against this same bundle (an app update changes what
    // needs downloading).
    if (ContentStore.downloaded(support)?.id == id) return false;

    final remote = ContentManifest.fromJson(await read('manifest.json'));
    // A publish landed between the two reads; the next check picks it up.
    if (remote.id != id) return false;
    final objects = Directory('${dir.path}/objects')
      ..createSync(recursive: true);
    // Patterns from another engine would disagree with this app's own solve.
    final patternsOk = remote.engine == kPatternEngineVersion;
    // Object name -> sha256, for every file this app reads that differs from
    // the bundle.
    final wanted = {
      for (final MapEntry(key: path, value: sha) in remote.files.entries)
        if (appReads(path) &&
            bundled.files[path] != sha &&
            (patternsOk || !isPatternPath(path)))
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
        json.encode({...remote.toJson(), 'base': bundled.id}),
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
