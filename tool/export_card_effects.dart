/// Name: ExportCardEffects
/// Parent: JacketEdition
/// Description: Render portable material references with the production painters.
library;

import 'dart:io';
import 'dart:ui' as ui;
import 'package:ddr_md/components/song/jacket_edition.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_motion.dart';
import 'package:ddr_md/components/song/jacket_edition/edition_catalog.dart'
    show editionNegative;
import 'package:ddr_md/components/song/jacket_edition/edition_painter.dart';
import 'package:ddr_md/models/chart_achievements.dart';
import 'package:ddr_md/models/db_models.dart';
import 'package:ddr_md/grades.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export card effect references', () async {
    const destination = String.fromEnvironment('CARD_EFFECTS_OUTPUT',
        defaultValue: 'build/card-effects');
    final output = Directory(destination)..createSync(recursive: true);
    final samples = <String, EditionFacts>{};
    EditionFacts facts(
            {Grade? grade,
            ClearLamp? lamp,
            String? flare,
            PrecisionAward? precision,
            bool negative = false}) =>
        EditionFacts(
            chart: (song: 'reference', mode: 'singles', difficulty: 'hard'),
            grade: grade,
            lamp: lamp,
            flare: flare,
            hardestTop: negative,
            precision: precision == null
                ? null
                : (award: precision, sourceRowId: 'reference', perfects: 5));
    for (final (name, grade) in [
      ('matte', Grade.c),
      ('satin', Grade.b),
      ('gloss', Grade.a),
      ('silver', Grade.aa),
      ('gold', Grade.aaa)
    ]) {
      samples['material-$name'] = facts(grade: grade);
    }
    for (final (name, lamp) in [
      ('stock', ClearLamp.clear),
      ('bronze', ClearLamp.fc),
      ('silver', ClearLamp.gfc),
      ('gold', ClearLamp.pfc),
      ('rainbow', ClearLamp.mfc)
    ]) {
      samples['frame-$name'] = facts(lamp: lamp);
    }
    samples['frame-platinum'] =
        facts(lamp: ClearLamp.pfc, precision: PrecisionAward.sdp);
    samples['aura-I'] = facts(flare: 'I');
    samples['aura-IX'] = facts(flare: 'IX');
    samples['aura-EX'] = facts(flare: 'EX');
    samples['art-negative'] = facts(negative: true);
    samples['art-failed'] = facts(grade: Grade.e);
    const size = Size.square(280);
    final motion = EditionMotion(const TestVSync());
    for (final entry in samples.entries) {
      final recipe = resolveEdition(entry.value);
      final geometry = EditionGeometry(recipe, size);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.translate(20, 20);
      EditionStaticPainter(geometry).paint(canvas, size);
      canvas.save();
      canvas.clipPath(geometry.inner);
      if (recipe.negative) {
        canvas.saveLayer(
            Offset.zero & size, Paint()..colorFilter = editionNegative);
      }
      // Shared vector jacket makes changes in reflection and colour comparable.
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = const LinearGradient(colors: [
              Color(0xFF132940),
              Color(0xFF277D8B),
              Color(0xFF172A48)
            ], begin: Alignment.topLeft, end: Alignment.bottomRight)
                .createShader(Offset.zero & size));
      canvas.drawCircle(
          const Offset(180, 95),
          52,
          Paint()
            ..shader = const LinearGradient(
                    colors: [Color(0xFFFFCD8C), Color(0xFFE26B7C)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter)
                .createShader(const Rect.fromLTWH(128, 43, 104, 104)));
      canvas.drawPath(
          Path()
            ..moveTo(0, 235)
            ..lineTo(105, 115)
            ..lineTo(170, 204)
            ..lineTo(220, 160)
            ..lineTo(280, 230)
            ..lineTo(280, 280)
            ..lineTo(0, 280)
            ..close(),
          Paint()..color = const Color(0xFF152E4C));
      for (var i = 0; i < 7; i++) {
        canvas.drawLine(
            Offset(i * 50 - 30, 280),
            const Offset(140, 205),
            Paint()
              ..color = const Color(0x9967DFEA)
              ..strokeWidth = 1);
      }
      if (recipe.negative) canvas.restore();
      canvas.restore();
      EditionStaticPainter(geometry, foreground: true).paint(canvas, size);
      EditionLightPainter(geometry, motion).paint(canvas, size);
      EditionFlarePainter(geometry).paint(canvas, size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(320, 320);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${output.path}/${entry.key}.png').writeAsBytes(
          png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
      image.dispose();
      picture.dispose();
      geometry.dispose();
    }
    motion.dispose();
  });
}
