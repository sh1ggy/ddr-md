/// Name: ChartShare
/// Parent: ChartScroller
/// Description: A stretch of chart (a snippet's section) drawn as an image
/// through the preview's own painter, headed by the song's jacket, title, play
/// style and chart in the cabinet's lettering, and handed to the system share
/// sheet.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ddr_md/components/song/notes/chart_painter.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// What heads a shared image. [difficulty] is the in-game name (EXPERT);
/// [note] reads under the chart, e.g. the snippet's name.
typedef ShareCaption = ({
  String title,
  ImageProvider? jacket,
  Modes mode,
  String difficulty,
  int? level,
  String note,
});

const double _pad = 16;
const double _jacket = 72;
const double _headerHeight = _jacket + 2 * 14;
const double _footerHeight = 28;
const double _minWidth = 320;

// Past this the spacing compresses so the image stays one a phone can open.
const double _maxFieldHeight = 4000;
const double _maxPixels = 8000;

/// Draws the field from [start] down to the row at [last] plus [runOut] px,
/// [fieldWidth] wide over [columns] lanes, under [caption], and shares it as a
/// PNG. [painterAt] builds the preview's painter on a playhead, with its
/// spacing scaled by `spacing` and its arrows by `zoom`.
Future<void> shareChartImage({
  required ChartPainter Function(
          ValueListenable<double> playhead, double spacing, double zoom)
      painterAt,
  required double fieldWidth,
  required int columns,
  required double start,
  required double last,
  required double runOut,
  required ShareCaption caption,
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

  final name = caption.difficulty.toLowerCase();
  final (jacket, style, nameArt, levelArt) = await (
    caption.jacket == null ? Future.value(null) : _resolve(caption.jacket!),
    _asset(caption.mode == Modes.doubles
        ? 'assets/icons/style_double.png'
        : 'assets/icons/style_single.png'),
    _asset('assets/difficulty/name_$name.png'),
    caption.level == null
        ? Future.value(null)
        : _asset('assets/difficulty/level_${name}_${caption.level}.png'),
  ).wait;

  final total = _headerHeight + height + _footerHeight;
  final ratio = math.min(pixelRatio, _maxPixels / total);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio);
  canvas.drawRect(Rect.fromLTWH(0, 0, width, total),
      Paint()..color = const Color(0xFF080A0E));

  var x = _pad;
  if (jacket != null) {
    const box = Rect.fromLTWH(_pad, 14, _jacket, _jacket);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(box, const Radius.circular(8)));
    canvas.drawImageRect(
        jacket,
        Offset.zero & Size(jacket.width.toDouble(), jacket.height.toDouble()),
        box,
        Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
    x += _jacket + 12;
  }
  final textWidth = width - x - _pad;
  _text(
      canvas,
      caption.title,
      Offset(x, 14),
      textWidth,
      const TextStyle(
          color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600));
  // Play style, then the chart, in the cabinet's lettering where it's bundled.
  var rowX = x;
  const rowY = 42.0, rowHeight = 18.0;
  if (style != null) {
    rowX += _image(canvas, style, Offset(rowX, rowY + 1), rowHeight - 2) + 8;
  }
  if (nameArt != null) {
    rowX += _image(canvas, nameArt, Offset(rowX, rowY), rowHeight) + 5;
  } else {
    rowX += _text(
            canvas,
            caption.difficulty,
            Offset(rowX, rowY),
            width - rowX - _pad,
            TextStyle(
                color:
                    kInGameDifficultyColors[caption.difficulty] ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic)) +
        5;
  }
  if (levelArt != null) {
    _image(canvas, levelArt, Offset(rowX, rowY), rowHeight);
  } else if (caption.level != null) {
    _text(
        canvas,
        '${caption.level}',
        Offset(rowX, rowY),
        width - rowX - _pad,
        const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic));
  }
  _text(canvas, caption.note, Offset(x, 68), textWidth,
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

// A bundled image, or null when it isn't (the difficulty art is optional).
Future<ui.Image?> _asset(String path) async {
  try {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}

Future<ui.Image?> _resolve(ImageProvider provider) {
  final done = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    stream.removeListener(listener);
    done.complete(info.image);
  }, onError: (_, __) {
    stream.removeListener(listener);
    done.complete(null);
  });
  stream.addListener(listener);
  return done.future;
}

// Draws [image] [height] tall at [at] and returns its width.
double _image(Canvas canvas, ui.Image image, Offset at, double height) {
  final width = image.width * height / image.height;
  canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      at & Size(width, height),
      Paint()..filterQuality = FilterQuality.medium);
  return width;
}

// Draws one line of [text], cut to [width], and returns how wide it ran.
double _text(
    Canvas canvas, String text, Offset at, double width, TextStyle style,
    {TextAlign align = TextAlign.left}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: align,
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(minWidth: align == TextAlign.left ? 0 : width, maxWidth: width);
  tp.paint(canvas, at);
  final ran = tp.width;
  tp.dispose();
  return ran;
}
