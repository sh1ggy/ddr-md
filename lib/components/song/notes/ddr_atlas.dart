/// Name: DdrAtlas
/// Parent: ChartPainter
/// Description: DDR PALETTE's arrows, receptors and freezes drawn the way the
/// cabinet draws them. The arrow art is index-coloured: a texel's red value
/// names a band, and the band's colour comes from the arrow's palette. Tap and
/// receptor palettes move with the chart position (a quarter-beat fill and a
/// rippling pulse); a freeze takes one row of a fixed freeze palette. Needs the
/// optional local assets `arrow-atlas.png` and `freeze-palette.png`.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// The palettes the cabinet draws taps and receptors through.
enum DdrPalette { quarter, eighth, sixteenth, other, receptor }

/// The band a texel's red value names; 0 (drawn clear) for any other value.
int ddrBand(int red) => _bands[red] ?? 0;
const _bands = {
  0xf8: 0, 0xe0: 1, 0xd8: 2, 0xc8: 3, 0xc0: 4, 0xb0: 5, 0xa0: 6, //
  0x98: 7, 0x88: 8, 0x80: 9, 0x70: 10, 0x60: 11, 0x58: 12, 0x48: 13,
};

/// ARGB of [band] in palette [p] at chart position [pos] (1024 per beat,
/// negative before the first beat). Band 1 is the outline; bands 2–4 fill in
/// one by one through each beat's 16ths; bands 5–13 pulse on a two-beat cycle,
/// each a ninth of a beat behind the last, so the pulse ripples across them.
int ddrColour(DdrPalette p, int band, int pos) {
  if (band == 0) return 0;
  if (p == DdrPalette.receptor) {
    if (band == 1) return pos < 0 ? 0xff202020 : 0xffe0e0e0;
    if (band < 5) return 0x00080808;
    final k = band - 5;
    final g = (pos < 0
            ? (k + 8) * 8
            : (pos & 0x3ff) < 0x100
                ? k * 8 + 0x80
                : (k + 4) * 8) &
        0xff;
    return 0xff000000 | g << 16 | g << 8 | g;
  }
  if (band == 1) return 0xff080808;
  if (band < 5) {
    if (((pos >> 8) - 1) & 3 <= band - 2) return 0x00080808;
    return switch (p) {
      DdrPalette.quarter => 0xfff88080,
      DdrPalette.eighth => 0xff8080f8,
      DdrPalette.sixteenth => 0xfff8f880,
      _ => 0xff80f880,
    };
  }
  final phase = pos + (5 - band) * 0x400 ~/ 9;
  final s = (math.sin(phase / 4096 * 2 * math.pi) * 4096).truncate();
  if (p == DdrPalette.sixteenth) {
    final b8 = (((s << 4) >> 12).abs() + 15) * 8 & 0xff;
    return (b8 * 0x10100 - 0xffffd8) & 0xffffffff;
  }
  final b8 = (24 - ((s * 24) >> 12).abs()) * 8 & 0xff;
  final argb = switch (p) {
    DdrPalette.quarter => b8 * 0x101 - 0x80000,
    DdrPalette.eighth => b8 * 0x10100 - 0xffff08,
    _ => b8 * 0x10001 - 0xff0800,
  };
  return argb & 0xffffffff;
}

/// The freeze palette column a texel's red value names; 15 (clear) otherwise.
int ddrFreezeColumn(int red) => _freezeColumns[red] ?? 15;
const _freezeColumns = {
  0xd0: 0, 0xcd: 0, 0xc8: 1, 0xc5: 1, 0xb8: 2, 0xa8: 3, 0x98: 4, 0x88: 5, //
  0x78: 6, 0x70: 7, 0x60: 8, 0x50: 9, 0x40: 10, 0x30: 11, 0x77: 12, 8: 13,
  0: 14, 4: 14,
};

/// The freeze palette row a freeze draws on [sinceHead] seconds past its head
/// (negative before it): row 1 until the head is stepped, then one row
/// brighter each 60th of a second up to row 4, where a held freeze stays.
int ddrFreezeRow(double sinceHead) =>
    sinceHead < 0 ? 1 : (1 + (sinceHead * 60).floor()).clamp(1, 4);

/// How long a lane glow lasts and how far it grows: 200 ms, from the arrow's
/// 96 px to 123.5 px.
const double ddrGlowSeconds = 0.2;
const double ddrGlowPeakScale = 1 + 27.5 / 96;

/// A held freeze throws a glow every 4th frame (at 60 fps).
const double ddrGlowInterval = 4 / 60;

/// Vertex colour of a held freeze's glow [progress] through its life: aqua,
/// fading linearly.
ui.Color ddrFreezeGlowColour(double progress) {
  final c = ((1 - progress.clamp(0.0, 1.0)) * 255).truncate();
  return ui.Color.fromARGB(c, c >> 2, c, c);
}

class DdrAtlas {
  DdrAtlas._(this._tapBands, this._freeze);

  // The tap cell split into one white mask per band, carrying the texel alpha.
  final Map<int, ui.Image> _tapBands;
  // [row][part]: 0 head, 1–4 tails and 5–8 bodies by cell (L, D, U, R).
  final List<List<ui.Image>> _freeze;

  static Future<DdrAtlas?>? _loadFuture;
  static DdrAtlas? _loaded;
  static bool _resolved = false;
  static bool get resolved => _resolved;
  static DdrAtlas? get resolvedAtlas => _loaded;

  static Future<DdrAtlas?> tryLoad() => _loadFuture ??= _doLoad();

  static Future<DdrAtlas?> _doLoad() async {
    try {
      final atlas = await _rgba('assets/noteskin/arrow-atlas.png');
      final pal = await _rgba('assets/noteskin/freeze-palette.png');
      // A cell of the atlas as (width, height, rgba).
      (int, int, Uint8List) cell(int x, int y, int w, int h) {
        final out = Uint8List(w * h * 4);
        for (var j = 0; j < h; j++) {
          final from = ((y + j) * atlas.$1 + x) * 4;
          out.setRange(j * w * 4, (j + 1) * w * 4, atlas.$3, from);
        }
        return (w, h, out);
      }

      final tap = cell(0, 0, 96, 96);
      final bands = <int, ui.Image>{};
      for (var band = 1; band <= 13; band++) {
        final mask = Uint8List(tap.$3.length);
        var any = false;
        for (var i = 0; i < mask.length; i += 4) {
          if (tap.$3[i + 3] == 0 || ddrBand(tap.$3[i]) != band) continue;
          final a = tap.$3[i + 3];
          mask
            ..[i] = a
            ..[i + 1] = a
            ..[i + 2] = a
            ..[i + 3] = a;
          any = true;
        }
        if (any) bands[band] = await _image(96, 96, mask);
      }

      final parts = [
        cell(96, 0, 96, 96),
        for (var c = 0; c < 4; c++) cell(96 * c, 96, 96, 96),
        for (var c = 0; c < 4; c++) cell(384 + 96 * c, 0, 96, 192),
      ];
      final freeze = <List<ui.Image>>[];
      for (var row = 0; row < 16; row++) {
        final images = <ui.Image>[];
        for (final (w, h, px) in parts) {
          final out = Uint8List(px.length);
          for (var i = 0; i < px.length; i += 4) {
            final p = (row * 16 + ddrFreezeColumn(px[i])) * 4;
            final a = px[i + 3] * pal.$3[p + 3] ~/ 255;
            out
              ..[i] = pal.$3[p] * a ~/ 255
              ..[i + 1] = pal.$3[p + 1] * a ~/ 255
              ..[i + 2] = pal.$3[p + 2] * a ~/ 255
              ..[i + 3] = a;
          }
          images.add(await _image(w, h, out));
        }
        freeze.add(images);
      }
      return _loaded = DdrAtlas._(bands, freeze);
    } catch (_) {
      return null;
    } finally {
      _resolved = true;
    }
  }

  static Future<(int, int, Uint8List)> _rgba(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final image = (await codec.getNextFrame()).image;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (image.width, image.height, bytes!.buffer.asUint8List());
  }

  // [rgba] is premultiplied: that is how the engine reads raw pixels.
  static Future<ui.Image> _image(int w, int h, Uint8List rgba) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  final Map<int, ui.Image> _tapCache = {};

  /// The tap cell coloured through [p] at chart position [pos]. Composed once
  /// per distinct set of band colours.
  ui.Image tap(DdrPalette p, int pos) {
    final colours = [
      for (final band in _tapBands.keys) ddrColour(p, band, pos),
    ];
    final key = Object.hashAll(colours);
    final hit = _tapCache.remove(key);
    if (hit != null) return _tapCache[key] = hit;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    var i = 0;
    for (final mask in _tapBands.values) {
      final c = colours[i++];
      if (c >>> 24 == 0) continue;
      canvas.drawImage(
          mask,
          ui.Offset.zero,
          ui.Paint()
            ..colorFilter =
                ui.ColorFilter.mode(ui.Color(c), ui.BlendMode.srcIn));
    }
    final image = recorder.endRecording().toImageSync(96, 96);
    if (_tapCache.length >= 64) _tapCache.remove(_tapCache.keys.first);
    return _tapCache[key] = image;
  }

  ui.Image freezeHead(int row) => _freeze[row][0];
  ui.Image freezeTail(int row, int cell) => _freeze[row][1 + cell];
  ui.Image freezeBody(int row, int cell) => _freeze[row][5 + cell];
}
