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
                    if (_recipe.modeStamp != null ||
                        _recipe.difficultyStamp != null)
                      Positioned(
                          left: geometry.width + 8,
                          right: geometry.width +
                              size.width * editionScoreTabWidth,
                          bottom: geometry.width + 8,
                          child: IgnorePointer(
                              child: RepaintBoundary(
                                  child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.bottomLeft,
                                      child: EditionChartStamps(
                                          recipe: _recipe, motion: _motion))))),
                    if (_recipe.scoreStamp case final score?)
                      Positioned(
                          right: geometry.width,
                          bottom: geometry.width,
                          height: size.height * editionScoreTabHeight,
                          child: IgnorePointer(
                              child: EditionScoreTab(
                                  score: score,
                                  corner: geometry.inner.brRadiusX))),
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

/// Play style as a die-cut sticker and the difficulty on its own label.
class EditionChartStamps extends StatelessWidget {
  const EditionChartStamps({super.key, required this.recipe, this.motion});
  final EditionRecipe recipe;
  final EditionMotion? motion;
  @override
  Widget build(BuildContext context) => Row(
          key: const ValueKey('edition-chart-stamp'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (recipe.modeStamp case final mode?) ...[
              EditionStamp(
                  asset:
                      'assets/icons/style_${mode == 'singles' ? 'single' : 'double'}.png',
                  height: 13,
                  label: mode == 'singles' ? 'SINGLE' : 'DOUBLE',
                  motion: motion),
              if (recipe.difficultyStamp != null) const SizedBox(width: 8),
            ],
            if (recipe.difficultyStamp case final difficulty?)
              EditionLabelSticker(
                  motion: motion,
                  child: DifficultyLabel(
                      difficulty: difficulty,
                      level: recipe.levelStamp,
                      levelSuffix: recipe.tierSuffix,
                      height: 15)),
          ]);
}

/// The best score in a tab carved out of the art's bottom right corner, as on
/// the song list's rows: thousands large, the rest small.
class EditionScoreTab extends StatelessWidget {
  const EditionScoreTab({super.key, required this.score, required this.corner});
  final int score;
  // The art's corner radius, which the tab's own corner follows.
  final double corner;
  @override
  Widget build(BuildContext context) {
    final text = formatScore(score);
    final split = text.lastIndexOf(',');
    const figures = [FontFeature.tabularFigures()];
    return LayoutBuilder(builder: (context, constraints) {
      final h = constraints.maxHeight;
      return ClipRRect(
          key: const ValueKey('edition-score-tab'),
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(h * .4),
              bottomRight: Radius.circular(corner)),
          child: ColoredBox(
              color: const Color(0xD916122C),
              child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: h * .45),
                  child: Center(
                      child: FittedBox(
                          child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: text.substring(0, split),
                        style: FloorPop.readout(17, color: Colors.white)
                            .copyWith(fontFeatures: figures)),
                    TextSpan(
                        text: text.substring(split),
                        style: FloorPop.readout(12, color: Colors.white70)
                            .copyWith(fontFeatures: figures)),
                  ])))))));
    });
  }
}
