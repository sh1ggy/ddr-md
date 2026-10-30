/// Name: JacketEdition
/// Parent: SongDetails, EditionLabPage
/// Description: Owns resolved materials, static resources and motion lifetime.
library;

import 'package:ddr_md/components/song/difficulty_label.dart';
import 'package:ddr_md/grades.dart' show gradeIcon, flareRankIcon;
import 'package:ddr_md/helpers.dart' show formatScore;
import 'package:ddr_md/theme.dart' show FloorPop;
import 'package:ddr_md/models/settings_model.dart';
import 'package:flutter/material.dart';
import 'edition_model.dart';
import 'edition_catalog.dart';
import 'edition_rules.dart';
import 'edition_motion.dart';
import 'edition_painter.dart';
import 'edition_stamp.dart';

/// On unless built with JACKET_EDITIONS=false, e.g. to compare frame
/// timings against the plain jacket.
const editionDevelopmentEnabled =
    bool.fromEnvironment('JACKET_EDITIONS', defaultValue: true);

EditionOptions editionPreferences() => (
      borderId: Settings.getString(Settings.jacketBorderKey),
      effects: Settings.getInt(Settings.jacketEffectsOffKey) == 0,
      motion: Settings.getInt(Settings.jacketMotionOffKey) == 0,
      modeStamp: Settings.getInt(Settings.jacketModeOffKey) == 0,
      gradeStamp: Settings.getInt(Settings.jacketGradeOffKey) == 0,
      difficultyStamp: Settings.getInt(Settings.jacketDifficultyOffKey) == 0,
      tierSuffix: Settings.getInt(Settings.jacketTierOffKey) == 0,
    );

class JacketEdition extends StatefulWidget {
  const JacketEdition(
      {super.key,
      required this.facts,
      required this.child,
      this.options = defaultEditionOptions,
      this.frozenLight});
  final EditionFacts facts;
  final Widget child;
  final EditionOptions options;
  final Offset? frozenLight;
  @override
  State<JacketEdition> createState() => _JacketEditionState();
}

class _JacketEditionState extends State<JacketEdition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final EditionMotion _motion = EditionMotion(this);
  late EditionRecipe _recipe = resolveEdition(widget.facts, widget.options);
  EditionGeometry? _geometry;
  ModalRoute<dynamic>? _route;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      _route?.animation?.removeStatusListener(_routeStatus);
      _route?.secondaryAnimation?.removeStatusListener(_routeStatus);
      _route = route;
      route?.animation?.addStatusListener(_routeStatus);
      route?.secondaryAnimation?.addStatusListener(_routeStatus);
    }
    _syncMotion();
  }

  @override
  void didUpdateWidget(JacketEdition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recipe = resolveEdition(widget.facts, widget.options);
    _syncMotion();
  }

  void _routeStatus(AnimationStatus _) => _syncMotion();
  void _syncMotion() {
    final route = _route;
    final visible = route == null ||
        (route.isCurrent &&
            (route.animation == null ||
                route.animation!.status == AnimationStatus.completed) &&
            (route.secondaryAnimation == null ||
                route.secondaryAnimation!.status == AnimationStatus.dismissed));
    _motion.configure(
        _recipe.animated &&
            _foreground &&
            visible &&
            TickerMode.valuesOf(context).enabled &&
            !MediaQuery.disableAnimationsOf(context) &&
            widget.frozenLight == null,
        frozenLight: widget.frozenLight);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _route?.animation?.removeStatusListener(_routeStatus);
    _route?.secondaryAnimation?.removeStatusListener(_routeStatus);
    _motion.dispose();
    _geometry?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_recipe.effects) return widget.child;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (!size.isFinite || size.isEmpty) return widget.child;
      var geometry = _geometry;
      if (geometry == null ||
          geometry.size != size ||
          geometry.recipe != _recipe) {
        geometry?.dispose();
        geometry = _geometry = EditionGeometry(_recipe, size);
      }
      final staticGeometry = geometry;
      return MouseRegion(
        onHover: (e) => _motion.point(e.localPosition, size),
        onExit: (_) => _motion.release(),
        child: Listener(
          onPointerDown: (e) => _motion.point(e.localPosition, size),
          onPointerMove: (e) => _motion.point(e.localPosition, size),
          onPointerCancel: (_) => _motion.release(),
          onPointerUp: (_) => _motion.release(),
          child: AnimatedBuilder(
              animation: _motion,
              builder: (context, child) => Transform(
                  key: const ValueKey('edition-tilt'),
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, .0012)
                    ..rotateX(-_motion.tilt.dy * editionTiltRadians)
                    ..rotateY(_motion.tilt.dx * editionTiltRadians),
                  child: child),
              child: RepaintBoundary(
                  child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.none,
                      children: [
                    RepaintBoundary(
                        child: CustomPaint(
                            painter: EditionStaticPainter(staticGeometry))),
                    Padding(
                        padding: EdgeInsets.all(geometry.width),
                        child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(geometry.inner.tlRadiusX),
                            child: RepaintBoundary(
                                key: const ValueKey('edition-art'),
                                child: _recipe.negative
                                    ? ColorFiltered(
                                        colorFilter: editionNegative,
                                        child: widget.child)
                                    : widget.child))),
                    IgnorePointer(
                        child: RepaintBoundary(
                            child: CustomPaint(
                                painter: EditionStaticPainter(staticGeometry,
                                    foreground: true)))),
                    // Only this sibling listens to light. The decoded image and both
                    // display lists retain separate layers throughout a sweep.
                    IgnorePointer(
                        child: RepaintBoundary(
                            child: CustomPaint(
                                painter: EditionLightPainter(
                                    staticGeometry, _motion),
                                foregroundPainter: EditionFlarePainter(
                                    staticGeometry, _motion)))),
                    if (_recipe.gradeStamp != null ||
                        _recipe.flareStamp != null)
                      Positioned(
                          left: geometry.width + 8,
                          right: geometry.width + 8,
                          top: geometry.width + 8,
                          child: IgnorePointer(
                              child: RepaintBoundary(
                                  child: EditionAchievementStamps(
                                      recipe: _recipe, motion: _motion)))),
                    if (EditionFooter.shows(_recipe))
                      Positioned(
                          left: geometry.width,
                          right: geometry.width,
                          bottom: geometry.width,
                          height: size.height * editionFooterHeight,
                          child: IgnorePointer(
                              child: EditionFooter(
                                  recipe: _recipe,
                                  corner: geometry.inner.blRadiusX))),
                  ]))),
        ),
      );
    });
  }
}

/// The flare in the card's top left corner and the grade in its top right,
/// across the width it's given.
class EditionAchievementStamps extends StatelessWidget {
  const EditionAchievementStamps(
      {super.key, required this.recipe, this.motion});
  final EditionRecipe recipe;
  final EditionMotion? motion;
  @override
  Widget build(BuildContext context) => Row(
          key: const ValueKey('edition-achievement-stamp'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (recipe.flareStamp case final flare?)
              Flexible(
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: EditionStamp(
                          key: const ValueKey('edition-flare-stamp'),
                          asset: flareRankIcon(flare),
                          height: 22,
                          label: flare,
                          motion: motion))),
            if (recipe.flareStamp == null) const SizedBox.shrink(),
            if (recipe.gradeStamp case final grade?)
              Flexible(
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topRight,
                      child: EditionStamp(
                          key: const ValueKey('edition-grade-stamp'),
                          asset: gradeIcon(grade),
                          height: 22,
                          label: grade.label,
                          motion: motion))),
          ]);
}

/// A band across the art's foot, as on the song list's rows: play style and
/// difficulty on the left, the best score in a darker tab flush right,
/// thousands large and the rest small. Everything scales with the band's
/// height alone; the score's tab is as wide as 999,999 would be, so a
/// 1,000,000 shrinks within it and nothing else moves.
class EditionFooter extends StatelessWidget {
  const EditionFooter(
      {super.key,
      required this.recipe,
      required this.corner,
      this.shortStyle = false});
  final EditionRecipe recipe;
  // The art's corner radius, which the band's corners follow.
  final double corner;
  // SINGLE or DOUBLE without STYLE, for the small card.
  final bool shortStyle;

  static bool shows(EditionRecipe recipe) =>
      recipe.modeStamp != null ||
      recipe.difficultyStamp != null ||
      recipe.scoreStamp != null;

  // The band's content height before scaling.
  static const _content = 18.0;
  static const _figures = [FontFeature.tabularFigures()];

  static TextSpan _score(String text) {
    final split = text.lastIndexOf(',');
    return TextSpan(children: [
      TextSpan(
          text: text.substring(0, split),
          style: FloorPop.readout(17, color: Colors.white)
              .copyWith(fontFeatures: _figures)),
      TextSpan(
          text: text.substring(split),
          style: FloorPop.readout(12, color: Colors.white70)
              .copyWith(fontFeatures: _figures)),
    ]);
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final h = constraints.maxHeight;
        final scale = h / (_content * 1.6);
        final score = recipe.scoreStamp;
        final slot = (TextPainter(
                text: _score('999,999'),
                textDirection: TextDirection.ltr,
                textScaler: TextScaler.noScaling)
              ..layout())
            .width;
        return ClipRRect(
            key: const ValueKey('edition-chart-stamp'),
            borderRadius:
                BorderRadius.vertical(bottom: Radius.circular(corner)),
            child: ColoredBox(
                color: const Color(0xB316122C),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: _content * .45 * scale),
                      Expanded(
                          child: ClipRect(
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Transform.scale(
                                      scale: scale,
                                      alignment: Alignment.centerLeft,
                                      child: OverflowBox(
                                          alignment: Alignment.centerLeft,
                                          maxWidth: double.infinity,
                                          child: _chart()))))),
                      if (score != null)
                        DecoratedBox(
                            key: const ValueKey('edition-score-tab'),
                            decoration: BoxDecoration(
                                color: const Color(0x66000000),
                                borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(h * .4))),
                            child: SizedBox(
                                width: (slot + _content * .9) * scale,
                                child: Center(
                                    child: SizedBox(
                                        width: slot * scale,
                                        child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerRight,
                                            child: Text.rich(
                                                _score(formatScore(score)),
                                                textScaler: TextScaler.linear(
                                                    scale))))))),
                    ])));
      });

  Widget _chart() => Row(mainAxisSize: MainAxisSize.min, children: [
        if (recipe.modeStamp case final mode?) ...[
          _Style(mode: mode, short: shortStyle, height: 13),
          if (recipe.difficultyStamp != null) const SizedBox(width: 8),
        ],
        if (recipe.difficultyStamp case final difficulty?)
          DifficultyLabel(
              difficulty: difficulty,
              level: recipe.levelStamp,
              levelSuffix: recipe.tierSuffix,
              height: 15),
      ]);
}

// The play style's lettering; [short] keeps SINGLE or DOUBLE and crops STYLE.
class _Style extends StatelessWidget {
  const _Style({required this.mode, required this.short, required this.height});
  final String mode;
  final bool short;
  final double height;

  // Of the 314×42 artwork: where the word starts and STYLE begins.
  static const _source = Size(314, 42);
  static const _crop = {'singles': (22.0, 155.0), 'doubles': (6.0, 155.0)};

  @override
  Widget build(BuildContext context) {
    final name = mode == 'singles' ? 'SINGLE' : 'DOUBLE';
    final image = Image.asset(
        'assets/icons/style_${mode == 'singles' ? 'single' : 'double'}.png',
        height: height,
        semanticLabel: name,
        errorBuilder: (_, __, ___) => Text(name,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900)));
    final crop = _crop[mode];
    if (!short || crop == null) return image;
    final unit = height / _source.height;
    return SizedBox(
        width: (crop.$2 - crop.$1) * unit,
        height: height,
        child: ClipRect(
            child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: _source.width * unit,
                minWidth: _source.width * unit,
                child: Transform.translate(
                    offset: Offset(-crop.$1 * unit, 0), child: image))));
  }
}
