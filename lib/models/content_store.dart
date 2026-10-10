/// Name: Content store
/// Parent: Songs, StepsLoader, PatternsLoader, jacket images
/// Description: Where chart content (songlist, steps, patterns, jackets) is
/// read from. Files the content updater downloaded override the copies bundled
/// in the app, so charts and songs can change without a store release.
///
/// Both sides are described by a [ContentManifest]: the bundle's is
/// assets/content_manifest.json (tool/content_manifest.dart), the download's is
/// the overlay's own. The overlay only applies while it is newer than the
/// bundle, so an app update that ships fresher content wins over an old
/// download, and its patterns only apply when they came from this app's engine.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ddr_md/models/pattern_analysis.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Shape of the content and its manifest. Bump when either changes in a way
/// an older app can't read; a manifest in another format is ignored.
const kContentFormat = 1;

/// Content paths (relative to assets/) the engine version gates.
bool isPatternPath(String path) =>
    path.startsWith('patterns/') || path == 'pattern_levels.json';

class ContentManifest {
  final int format;

  /// Increases with every publish; the newer of bundle and overlay wins.
  final int content;

  /// [kPatternEngineVersion] the patterns were generated with.
  final int engine;

  /// Path relative to assets/ -> sha256 of the file.
  final Map<String, String> files;

  const ContentManifest({
    required this.format,
    required this.content,
    required this.engine,
    required this.files,
  });

  static const empty =
      ContentManifest(format: kContentFormat, content: 0, engine: 0, files: {});

  factory ContentManifest.fromJson(Map<String, dynamic> j) => ContentManifest(
        format: j['format'] as int,
        content: j['content'] as int,
        engine: j['engine'] as int,
        files: (j['files'] as Map<String, dynamic>).cast<String, String>(),
      );

  Map<String, dynamic> toJson() => {
        'format': format,
        'content': content,
        'engine': engine,
        'files': files,
      };
}

class ContentStore {
  /// The bundle's manifest, for the updater to diff against.
  static ContentManifest bundled = ContentManifest.empty;

  /// Content path -> downloaded file, for the paths the overlay overrides.
  static Map<String, File> _overlay = {};

  /// <app support>/content: overlay.json, plus objects/<sha256>.
  static Directory contentDir(Directory support) =>
      Directory('${support.path}/content');

  /// Reads both manifests. [support] is the app support directory; [bundle]
  /// stands in for the bundled manifest in tests.
  static Future<void> init(Directory support, {ContentManifest? bundle}) async {
    bundled = bundle ?? await _bundledManifest();
    _overlay = {};
    final dir = contentDir(support);
    final file = File('${dir.path}/overlay.json');
    if (!file.existsSync()) return;
    final ContentManifest overlay;
    try {
      overlay = ContentManifest.fromJson(
          json.decode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return;
    }
    if (overlay.format != kContentFormat || overlay.content <= bundled.content) {
      return;
    }
    final patternsOk = overlay.engine == kPatternEngineVersion;
    for (final MapEntry(key: path, value: sha) in overlay.files.entries) {
      if (!patternsOk && isPatternPath(path)) continue;
      final object = File('${dir.path}/objects/$sha');
      if (object.existsSync()) _overlay[path] = object;
    }
  }

  static Future<ContentManifest> _bundledManifest() async {
    try {
      return ContentManifest.fromJson(json.decode(await rootBundle
              .loadString('assets/content_manifest.json', cache: false))
          as Map<String, dynamic>);
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
