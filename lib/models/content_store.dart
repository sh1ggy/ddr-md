/// Name: Content store
/// Parent: Songs, StepsLoader, PatternsLoader, jacket images
/// Description: Where chart content (songlist, steps, patterns, jackets) is
/// read from. Files the content updater downloaded override the copies bundled
/// in the app, so charts and songs can change without a store release.
///
/// Both sides are described by a [ContentManifest]: the bundle's is
/// assets/content_manifest.json (tool/content_manifest.dart), the download's is
/// the overlay's own, read at launch and again when an update is applied
/// mid-run (ContentUpdater.update). Each is identified by [ContentManifest.id],
/// a hash of what it holds; the app follows whatever is live, so there's no
/// "newer". The overlay only applies to the bundle it was diffed against (an app
/// update re-syncs), and its patterns only when they came from this app's
/// engine.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Whether this app reads [path] (relative to assets/), and so downloads it.
/// Content only changes additively; a breaking change to a file ships its new
/// shape under a new path next to the old one, which older apps never fetch.
bool appReads(String path) =>
    const ['songlist.json', 'parity_patterns.json', 'pattern_levels.json']
        .contains(path) ||
    const ['steps/', 'patterns/', 'jackets/', 'jackets-160/']
        .any(path.startsWith);

/// Content paths (relative to assets/) the engine version gates.
bool isPatternPath(String path) =>
    path.startsWith('patterns/') || path == 'pattern_levels.json';

/// [path]'s file in objects/: its sha256 plus its extension, so the host
/// serves JSON as JSON (and compresses it).
String objectName(String path, String sha) {
  final dot = path.lastIndexOf('.');
  return dot > path.lastIndexOf('/') ? '$sha${path.substring(dot)}' : sha;
}

class ContentManifest {
  /// Hash of [engine] and [files]: the same content always has the same id.
  /// Which commits built it is in the published manifest's `source`.
  final String id;

  /// [kPatternEngineVersion] the patterns were generated with.
  final int engine;

  /// Path relative to assets/ -> sha256 of the file.
  final Map<String, String> files;

  const ContentManifest({
    required this.id,
    required this.engine,
    required this.files,
  });

  static const empty = ContentManifest(id: '', engine: 0, files: {});

  factory ContentManifest.fromJson(Map<String, dynamic> j) => ContentManifest(
        id: j['id'] as String,
        engine: j['engine'] as int,
        files: (j['files'] as Map<String, dynamic>).cast<String, String>(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'engine': engine,
        'files': files,
      };
}

class ContentStore {
  /// The bundle's manifest, for the updater to diff against.
  static ContentManifest bundled = ContentManifest.empty;

  /// Id of the content this run reads: the overlay's when it applied, else
  /// the bundle's.
  static String current = '';

  /// Bumped when an update is applied mid-run, so pages built from the content
  /// (the song list) rebuild. Pages already open keep what they loaded.
  static final revision = ValueNotifier<int>(0);

  /// Content path -> downloaded file, for the paths the overlay overrides.
  static Map<String, File> _overlay = {};

  /// Downloaded files this run reads from, which the updater must keep.
  static Set<String> get inUse =>
      {for (final f in _overlay.values) f.uri.pathSegments.last};

  /// <app support>/content: overlay.json, plus objects/ ([objectName]).
  static Directory contentDir(Directory support) =>
      Directory('${support.path}/content');

  /// Reads both manifests. [support] is the app support directory; [bundle]
  /// stands in for the bundled manifest in tests.
  static Future<void> init(Directory support, {ContentManifest? bundle}) async {
    bundled = bundle ?? await _bundledManifest();
    current = bundled.id;
    _overlay = {};
    final overlay = downloaded(support);
    if (overlay == null) return;
    final dir = contentDir(support);
    final patternsOk = overlay.engine == kPatternEngineVersion;
    for (final MapEntry(key: path, value: sha) in overlay.files.entries) {
      if (!patternsOk && isPatternPath(path)) continue;
      final object = File('${dir.path}/objects/${objectName(path, sha)}');
      if (object.existsSync()) _overlay[path] = object;
    }
    current = overlay.id;
  }

  /// The downloaded overlay, when it was diffed against this bundle; null when
  /// there's none or the app has been updated since.
  static ContentManifest? downloaded(Directory support) {
    try {
      final j = json.decode(
          File('${contentDir(support).path}/overlay.json').readAsStringSync());
      if (j['base'] != bundled.id) return null;
      final overlay = ContentManifest.fromJson(j);
      return overlay.id == bundled.id ? null : overlay;
    } catch (_) {
      return null;
    }
  }

  static Future<ContentManifest> _bundledManifest() async {
    try {
      return ContentManifest.fromJson(json.decode(await rootBundle.loadString(
          'assets/content_manifest.json',
          cache: false)) as Map<String, dynamic>);
    } catch (_) {
      return ContentManifest.empty;
    }
  }

  static String _relative(String assetPath) =>
      assetPath.startsWith('assets/') ? assetPath.substring(7) : assetPath;

  /// [assetPath] as text (e.g. "assets/steps/Foo.json"), downloaded copy
  /// first. Throws like [AssetBundle.loadString] when neither has it.
  static Future<String> loadString(String assetPath) {
    final file = _overlay[_relative(assetPath)];
    if (file != null) return file.readAsString();
    // `cache: false`: these are large and parsed once by their loader.
    return rootBundle.loadString(assetPath, cache: false);
  }

  static ImageProvider image(String assetPath) {
    final file = _overlay[_relative(assetPath)];
    if (file != null) return FileImage(file);
    return AssetImage(assetPath);
  }
}
