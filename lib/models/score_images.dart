/// Name: ScoreImages
/// Description: Owns the app-documents "scores/" directory holding the proof
/// image captured with each saved score. Images are written at save time and
/// referenced from the scores table by a path relative to the documents dir
/// (the absolute container path changes across iOS app updates).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class ScoreImages {
  static const String _dirName = 'scores';

  // Writes [bytes] as the proof image for the score with [id] (the scores
  // table primary key, a UUID) and returns the relative path to store on the
  // row. The id is already filesystem-safe so it becomes the filename as-is.
  // The native pipeline hands back PNG (ROI overlay) or JPEG (camera capture)
  // — sniff the magic bytes so the file extension matches the content.
  static Future<String> save(Uint8List bytes, String id) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dirName');
    await dir.create(recursive: true);
    final isJpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    final relativePath = '$_dirName/$id.${isJpeg ? 'jpg' : 'png'}';
    await File('${docs.path}/$relativePath').writeAsBytes(bytes, flush: true);
    return relativePath;
  }

  // Resolves a stored relative path back to a file, or null when the score
  // has no image or the file no longer exists on disk.
  static Future<File?> resolve(String relativePath) async {
    if (relativePath.isEmpty) return null;
    final docs = await getApplicationDocumentsDirectory();
    final file = File('${docs.path}/$relativePath');
    return await file.exists() ? file : null;
  }
}
