/// Name: ChartShare
/// Parent: ChartScroller
/// Description: A stretch of chart (a snippet's section) drawn as an image
/// through the preview's own painter, captioned with the song, chart and bars,
/// and handed to the system share sheet.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const double _pad = 16;
const double _headerHeight = 60;
const double _footerHeight = 28;
const double _minWidth = 320;

// Past this the spacing compresses so the image stays one a phone can open.
const double _maxFieldHeight = 4000;
const double _maxPixels = 8000;

/// Draws the field from [start] down to the row at [last] plus [runOut] px,
/// [fieldWidth] wide over [columns] lanes, and shares it as a PNG.
/// [painterAt] builds the preview's painter on a playhead, with its spacing
/// scaled by `spacing` and its arrows by `zoom`.
Future<void> shareChartImage({
  required ChartPainter Function(
          ValueListenable<double> playhead, double spacing, double zoom)
      painterAt,
  required double fieldWidth,
  required int columns,
  required double start,
  required double last,
  required double runOut,
  required String title,
  required String subtitle,
  required double pixelRatio,
  Rect? origin,
}) async {
  final width = math.max(fieldWidth + 2 * _pad, _minWidth);
  // The painter sizes arrows to the canvas width; this zoom brings them back to
  // the screen's.
  final zoom = fieldWidth / width;
  // At least one cabinet screen tall, else the painter shrinks the arrows to
  // fit its height.
  final minHeight = ChartPainter.receptorBase +
      width / columns * ChartPainter.cabinetTravelArrows;
  final playhead = ValueNotifier(start);
  double heightAt(ChartPainter p, double spacing) =>
      p.rowY(last, Size(width, width)) + runOut * spacing;

  var spacing = 1.0;
  var painter = painterAt(playhead, spacing, zoom);
  var height = heightAt(painter, spacing);
  if (height > _maxFieldHeight) {
    spacing = (_maxFieldHeight - ChartPainter.receptorBase) /
        (height - ChartPainter.receptorBase);
    painter = painterAt(playhead, spacing, zoom);
    height = heightAt(painter, spacing);
  }
  height = math.max(height, minHeight);

  final total = _headerHeight + height + _footerHeight;
  final ratio = math.min(pixelRatio, _maxPixels / total);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio);
  canvas.drawRect(Rect.fromLTWH(0, 0, width, total),
      Paint()..color = const Color(0xFF080A0E));
  _text(
      canvas,
      title,
      const Offset(_pad, 12),
      width - 2 * _pad,
      const TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600));
  _text(canvas, subtitle, const Offset(_pad, 36), width - 2 * _pad,
      const TextStyle(color: Colors.white70, fontSize: 13));
  canvas.save();
  canvas.translate(0, _headerHeight);
  canvas.clipRect(Rect.fromLTWH(0, 0, width, height));
  painter.paint(canvas, Size(width, height));
  canvas.restore();
  _text(canvas, 'DDR MD', Offset(_pad, _headerHeight + height + 6),
      width - 2 * _pad, const TextStyle(color: Colors.white38, fontSize: 11),
      align: TextAlign.right);
  playhead.dispose();

  final image = await recorder
      .endRecording()
      .toImage((width * ratio).round(), (total * ratio).round());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (png == null) return;
  final file = File('${(await getTemporaryDirectory()).path}/snippet.png');
  await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'image/png')],
    sharePositionOrigin: origin,
  ));
}

void _text(Canvas canvas, String text, Offset at, double width, TextStyle style,
    {TextAlign align = TextAlign.left}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: align,
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(minWidth: width, maxWidth: width);
  tp.paint(canvas, at);
  tp.dispose();
}
