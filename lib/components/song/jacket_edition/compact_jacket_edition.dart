/// Name: CompactJacketEdition
/// Parent: SongDetails
/// Description: Static small-card material with no ticker or input controller.
library;

import 'package:flutter/widgets.dart';
import 'edition_model.dart';
import 'edition_rules.dart';
import 'edition_painter.dart';

class CompactJacketEdition extends StatefulWidget {
  const CompactJacketEdition(
      {super.key,
      required this.facts,
      required this.options,
      required this.child});
  final EditionFacts facts;
  final EditionOptions options;
  final Widget child;
  @override
  State<CompactJacketEdition> createState() => _CompactJacketEditionState();
}

class _CompactJacketEditionState extends State<CompactJacketEdition> {
  EditionGeometry? _geometry;
  @override
  void dispose() {
    _geometry?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.options.effects) return widget.child;
    final recipe = resolveEdition(widget.facts, widget.options);
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (!size.isFinite || size.isEmpty) return widget.child;
      var geometry = _geometry;
      if (geometry == null ||
          geometry.recipe != recipe ||
          geometry.size != size) {
        geometry?.dispose();
        geometry = _geometry = EditionGeometry(recipe, size, compact: true);
      }
      return RepaintBoundary(
          child: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: EditionStaticPainter(geometry)),
        Padding(
            padding: EdgeInsets.all(geometry.width),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(geometry.inner.tlRadiusX),
                child: RepaintBoundary(child: widget.child))),
        IgnorePointer(
            child: CustomPaint(
                painter: EditionStaticPainter(geometry, foreground: true))),
      ]));
    });
  }
}
